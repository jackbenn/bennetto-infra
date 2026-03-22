FROM python:3.11-slim

WORKDIR /app

# requirements.txt lists psycopg2 (source build); swap for the binary wheel
# which bundles libpq and needs no compiler or system packages
COPY gengo/requirements.txt .
RUN sed 's/^psycopg2$/psycopg2-binary/' requirements.txt \
    | pip install --no-cache-dir -r /dev/stdin
RUN pip install --no-cache-dir gunicorn

COPY gengo/ .

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "gengo.app.routes:app"]
