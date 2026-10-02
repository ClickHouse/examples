import unittest

from reviewdesk.validation import MAX_BYTES, ReviewError, parse_csv, validate_records


class CSVValidationTests(unittest.TestCase):
    def test_quoted_utf8_and_exact_integer_text(self):
        rows = parse_csv(
            'sku,name,price_cents\r\nA,"Café, tray",1299\r\nB,Free sample,0\r\n'.encode()
        )
        self.assertEqual(rows[0]["name"], "Café, tray")
        self.assertEqual(rows[0]["price_cents"], "1299")
        self.assertEqual(validate_records(rows), [[], []])

    def test_exact_header_and_encoding(self):
        for value in [
            b"sku,name,price\nA,a,1\n",
            b"name,sku,price_cents\n",
            b"\xef\xbb\xbfsku,name,price_cents\nA,a,1\n",
            b"sku,name,price_cents\nA,\xff,1\n",
        ]:
            with self.subTest(value=value), self.assertRaises(ReviewError):
                parse_csv(value)

    def test_shape_quoting_and_bounds(self):
        for value in [
            b"",
            b"sku,name,price_cents\n",
            b"sku,name,price_cents\nA,a\n",
            b"sku,name,price_cents\n\n",
            b'sku,name,price_cents\nA,"broken,1\n',
            b"x" * (MAX_BYTES + 1),
            b"sku,name,price_cents\n" + b"A,a,1\n" * 201,
            b"sku,name,price_cents\nA," + b"a" * 241 + b",1\n",
        ]:
            with self.subTest(length=len(value)), self.assertRaises(ReviewError):
                parse_csv(value)
        self.assertEqual(len(parse_csv(b"sku,name,price_cents\n" + b"A,a,1\n" * 200)), 200)

    def test_invalid_values_survive_for_correction(self):
        rows = parse_csv(b"sku,name,price_cents\nA,,3.50\nA,Second,01\n")
        issues = validate_records(rows)
        self.assertEqual(rows[0]["price_cents"], "3.50")
        self.assertEqual(len(issues[0]), 3)
        self.assertEqual(len(issues[1]), 2)

    def test_price_limits_and_unicode_controls(self):
        for value in ["-1", "+1", "1.0", "1e3", "01", "1000000001", "９", ""]:
            self.assertTrue(
                validate_records([{"sku": "A", "name": "Item", "price_cents": value}])[0]
            )
        self.assertEqual(
            validate_records([{"sku": "A", "name": "Item", "price_cents": "1000000000"}]), [[]]
        )
        for control in ["\x7f", "\x85", "\t"]:
            self.assertTrue(
                validate_records([{"sku": "A", "name": "Item" + control, "price_cents": "1"}])[0]
            )

    def test_formula_text_is_literal_and_catalogue_conflicts(self):
        rows = parse_csv(b"sku,name,price_cents\nA,=1+1,1\n")
        self.assertEqual(rows[0]["name"], "=1+1")
        self.assertEqual(validate_records(rows), [[]])
        self.assertIn("already exists", validate_records(rows, ["A"])[0][0])


if __name__ == "__main__":
    unittest.main()
