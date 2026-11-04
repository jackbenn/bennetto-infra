FROM python:3.11-slim@sha256:db20d8506e2f15b6db39b40b6015ca46bae855dec6dd326d462cfe79ae972893

WORKDIR /app

COPY taking_the_story/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY taking_the_story/ .

RUN mkdir /data

# DB_PATH is hardcoded as "story_game.db" (relative) in main.py.
# Symlink it to /data so it lands in the named volume and survives rebuilds.
CMD ["sh", "-c", "ln -sfn /data/story_game.db /app/story_game.db && exec uvicorn main:app --host 0.0.0.0 --port 8000 --root-path /story"]
