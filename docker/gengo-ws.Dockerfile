FROM python:3.11-slim@sha256:db20d8506e2f15b6db39b40b6015ca46bae855dec6dd326d462cfe79ae972893

WORKDIR /app

# Keep these two steps identical to gengo-web.Dockerfile's, so BuildKit builds
# the dependency layer once and both images share it. See INFRA-2.
COPY gengo/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Only what start_server.py imports, so a change to the web front end
# (gengo/gengo/app/) doesn't rebuild this image and restart the game server,
# which would end every game in progress.
COPY gengo/start_server.py .
COPY gengo/gengo/__init__.py gengo/
COPY gengo/gengo/server/ gengo/server/
COPY gengo/gengo/src/ gengo/src/

# Python fully buffers stdout when it isn't a terminal, so the server's prints
# never reached `docker compose logs`. See INFRA-4.
ENV PYTHONUNBUFFERED=1

CMD ["python", "start_server.py", "--port", "8765"]
