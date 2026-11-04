FROM python:3.11-slim@sha256:db20d8506e2f15b6db39b40b6015ca46bae855dec6dd326d462cfe79ae972893

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
