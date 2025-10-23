#!/usr/bin/env bash
# Simple build script dùng Rojo để build rbxlx file

set -e

ROJO_CMD=$(command -v rojo || true)
if [ -z "$ROJO_CMD" ]; then
  echo "Rojo CLI is not installed or not in PATH. Install via 'npm i -g @rojo-rbx/rojo' or see Rojo docs."
  exit 1
fi

OUT="build/game.rbxlx"
PROJECT_FILE="default.project.json"

echo "Building project with Rojo..."
$ROJO_CMD build -o "$OUT" "$PROJECT_FILE"
echo "Built -> $OUT"
