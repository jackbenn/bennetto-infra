FROM python:3.11-slim

WORKDIR /app

COPY gengo/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY gengo/ .

CMD ["python", "start_server.py", "--port", "8765"]
