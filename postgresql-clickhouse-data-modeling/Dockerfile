FROM python:3.12-slim
WORKDIR /app
COPY python/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY python ./python
CMD ["python", "python/import_parquet.py"]
