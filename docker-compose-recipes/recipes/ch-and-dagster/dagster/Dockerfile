FROM python:3.12-slim

ENV DAGSTER_HOME=/opt/dagster/dagster_home
ENV PYTHONDONTWRITEBYTECODE=1
WORKDIR /opt/dagster/app

COPY dagster/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
RUN mkdir -p "$DAGSTER_HOME"
COPY dagster/dagster.yaml ${DAGSTER_HOME}/dagster.yaml
COPY user_code ./user_code

CMD ["dagster", "dev", "-h", "0.0.0.0", "-p", "3000", "-m", "user_code"]
