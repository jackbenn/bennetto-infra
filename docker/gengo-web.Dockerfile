FROM python:3.11-slim

WORKDIR /app

# Keep these two steps identical to gengo-ws.Dockerfile's, so BuildKit builds
# the dependency layer once and both images share it. See INFRA-2.
COPY gengo/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN pip install --no-cache-dir gunicorn==26.2.0

COPY gengo/ .

# Send prints straight to `docker compose logs` (stdout is otherwise fully
# buffered). See INFRA-4.
ENV PYTHONUNBUFFERED=1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "gengo.app.routes:app"]
