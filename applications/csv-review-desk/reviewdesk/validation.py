import csv
import io
import re
import unicodedata
from collections import Counter

MAX_BYTES = 262_144
MAX_ROWS = 200
HEADERS = ["sku", "name", "price_cents"]
RAW_LIMITS = {"sku": 80, "name": 240, "price_cents": 32}
SKU = re.compile(r"[A-Z0-9][A-Z0-9_-]{0,39}", re.ASCII)
PRICE = re.compile(r"0|[1-9][0-9]{0,9}", re.ASCII)


class ReviewError(Exception):
    pass


def raw_record(record):
    if set(record) != set(HEADERS):
        raise ReviewError("Each row must contain sku, name and price_cents.")
    result = {}
    for field, limit in RAW_LIMITS.items():
        value = record[field]
        if not isinstance(value, str) or len(value) > limit or "\x00" in value:
            raise ReviewError(f"{field} must be text of at most {limit} characters, without NUL.")
        result[field] = value
    return result


def parse_csv(data):
    if not isinstance(data, bytes) or not data or len(data) > MAX_BYTES:
        raise ReviewError("Upload 1–262,144 bytes.")
    try:
        text = data.decode("utf-8")
        reader = csv.reader(io.StringIO(text, newline=""), strict=True)
        if next(reader, None) != HEADERS:
            raise ReviewError("Use exactly the UTF-8 header sku,name,price_cents (no BOM).")
        rows = []
        for values in reader:
            if len(values) != 3:
                raise ReviewError(
                    "Every CSV record must have exactly three fields; blank records are rejected."
                )
            rows.append(raw_record(dict(zip(HEADERS, values))))
            if len(rows) > MAX_ROWS:
                raise ReviewError("A batch can contain at most 200 records.")
        if not rows:
            raise ReviewError("Include at least one record below the header.")
        return rows
    except (UnicodeDecodeError, csv.Error) as exc:
        raise ReviewError("Use well-formed UTF-8 CSV with valid quoting.") from exc


def validate_records(records, existing=()):
    counts = Counter(r["sku"] for r in records)
    existing = set(existing)
    errors = []
    for row in records:
        issues = []
        if not SKU.fullmatch(row["sku"]):
            issues.append(
                "SKU: 1–40 uppercase letters, digits, underscore or hyphen; begin with a letter/digit."
            )
        if (
            not 1 <= len(row["name"]) <= 120
            or row["name"].strip() != row["name"]
            or any(unicodedata.category(c) == "Cc" for c in row["name"])
        ):
            issues.append(
                "Name: 1–120 characters, no surrounding whitespace or control characters."
            )
        if not PRICE.fullmatch(row["price_cents"]) or int(row["price_cents"]) > 1_000_000_000:
            issues.append(
                "Price: whole cents from 0 to 1,000,000,000; no signs, decimals or leading zeros."
            )
        if counts[row["sku"]] > 1:
            issues.append("SKU is repeated in this batch.")
        if row["sku"] in existing:
            issues.append("SKU already exists in the catalogue; choose a different SKU.")
        errors.append(issues)
    return errors
