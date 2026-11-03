FROM python:3.11-slim

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

CMD ["python", "start_server.py", "--port", "8765"]
