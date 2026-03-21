FROM python:3.11-slim

WORKDIR /app

COPY taking_the_story/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY taking_the_story/ .

RUN mkdir /data

# DB_PATH is hardcoded as "story_game.db" (relative) in main.py.
# Symlink it to /data so it lands in the named volume and survives rebuilds.
CMD ["sh", "-c", "ln -sfn /data/story_game.db /app/story_game.db && exec uvicorn main:app --host 0.0.0.0 --port 8000 --root-path /story"]
