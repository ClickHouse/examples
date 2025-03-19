import os
import sys
import pandas as pd
import psycopg2
import requests
from tqdm import tqdm

# Parquet file URLs
datasets = {
    "posts": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/posts/2023.parquet",
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/posts/2024.parquet"
    ],
    "votes": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/votes/2023.parquet",
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/votes/2024.parquet"
    ],
    "comments": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/comments/2023.parquet",
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/comments/2024.parquet"
    ],
    "users": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/users.parquet"
    ]
}

def download_parquet(url, output_path):
    print(f"Downloading {url}...")
    response = requests.get(url, stream=True)
    if response.status_code == 200:
        with open(output_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        print(f"Downloaded {output_path}")
    else:
        print(f"Failed to download {url}")
        sys.exit(1)

def main():
    if len(sys.argv) != 7:
        print("Usage: python import_parquet.py <database> <user> <password> <host> <port> <chunk_size>")
        sys.exit(1)

    database, user, password, host, port, chunk_size = sys.argv[1:]
    chunk_size = int(chunk_size)
    temp_dir = "data"
    os.makedirs(temp_dir, exist_ok=True)

    # Connect to PostgreSQL
    try:
        conn = psycopg2.connect(dbname=database, user=user, password=password, host=host, port=port)
        conn.autocommit = True
        cursor = conn.cursor()
    except Exception as e:
        print(f"Error connecting to PostgreSQL: {e}")
        sys.exit(1)

    for table, urls in datasets.items():
        for url in urls:
            parquet_file = os.path.join(temp_dir, os.path.basename(url))
            csv_file = parquet_file.replace(".parquet", ".csv")
            
            download_parquet(url, parquet_file)
            
            # Convert Parquet to CSV
            print(f"Read {parquet_file}...")
            df = pd.read_parquet(parquet_file)
            print(f"Convert {parquet_file} to CSV...")
            df.to_csv(csv_file, index=False)
            
            # Read CSV in chunks and import to PostgreSQL
            try:
                for i, chunk in enumerate(tqdm(pd.read_csv(csv_file, chunksize=chunk_size, dtype=str, keep_default_na=False))):
                    print(f"Importing chunk {i} into {table}...")
                    chunk_file = os.path.join(temp_dir, f"chunk_{i}.csv")
                    chunk.to_csv(chunk_file, index=False, header=(i == 0))  # Write header only for the first chunk
                    try:
                        with open(chunk_file, "r", encoding="utf-8") as f:
                            cursor.copy_expert(f"COPY {table} FROM STDIN WITH CSV HEADER", f)
                    except Exception as e:
                        print(f"Error importing chunk {i}: {e}")
                        continue

            except Exception as e:
                print(f"Error processing CSV: {e}")

            os.remove(parquet_file)
            os.remove(csv_file)

    cursor.close()
    conn.close()
    print("All imports completed successfully!")

if __name__ == "__main__":
    main()
