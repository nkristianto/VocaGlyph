#!/bin/bash

# Generates a CoreML model using the whisper.cpp script and copies it to the app's models directory.
# Usage: ./generate-coreml.sh <model-name> (e.g., base.en)

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <model-name>"
    exit 1
fi

MODEL_NAME=$1
WHISPER_DIR="${WHISPER_DIR:-$HOME/Workspace/Personal/whisper.cpp}"
MODELS_DEST="$HOME/.voice-to-text/models"

echo "==> Setting up Python virtual environment for CoreML generation..."
# We use a venv to avoid messing with the global python environment,
# which is strictly controlled in modern macOS versions.
if [ ! -d "$WHISPER_DIR/models/venv" ]; then
    python3 -m venv "$WHISPER_DIR/models/venv"
fi
source "$WHISPER_DIR/models/venv/bin/activate"

echo "==> Installing CoreML Python requirements..."
pip3 install --quiet --disable-pip-version-check -r "$WHISPER_DIR/models/requirements-coreml.txt"

echo "==> Generating CoreML model for $MODEL_NAME..."
cd "$WHISPER_DIR"
sh models/generate-coreml-model.sh "$MODEL_NAME"

echo "==> Copying .mlmodelc to application directory..."
mkdir -p "$MODELS_DEST"
cp -R "models/ggml-${MODEL_NAME}-encoder.mlmodelc" "$MODELS_DEST/"

echo "==> CoreML model generation for $MODEL_NAME complete."
