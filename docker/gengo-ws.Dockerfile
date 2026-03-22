FROM python:3.11-slim

WORKDIR /app

COPY gengo/requirements.txt .
RUN sed 's/^psycopg2$/psycopg2-binary/' requirements.txt \
    | pip install --no-cache-dir -r /dev/stdin

COPY gengo/ .

CMD ["python", "start_server.py", "--port", "8765"]
