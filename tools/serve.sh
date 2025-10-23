#!/usr/bin/env bash
# Start rojo serve for live editing

ROJO_CMD=$(command -v rojo || true)
if [ -z "$ROJO_CMD" ]; then
  echo "Rojo CLI not found. Install via npm i -g @rojo-rbx/rojo"
  exit 1
fi

PROJECT_FILE="default.project.json"
PORT=34872

echo "Starting rojo serve on port $PORT (project: $PROJECT_FILE)"
$ROJO_CMD serve "$PROJECT_FILE" --port $PORT
