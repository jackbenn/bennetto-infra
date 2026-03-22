FROM python:3.11-slim

WORKDIR /app

COPY gengo/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn

COPY gengo/ .

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "gengo.app.routes:app"]
