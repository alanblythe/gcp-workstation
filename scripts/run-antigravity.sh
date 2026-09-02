#!/usr/bin/env bash
#
# Helper script to launch Antigravity CLI (agy) configured for Vertex AI.
#

set -euo pipefail

export GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo "your-project-id")}"
export GOOGLE_CLOUD_LOCATION="${GOOGLE_CLOUD_LOCATION:-global}"
export GOOGLE_GENAI_USE_VERTEXAI=true
export GOOGLE_GENAI_USE_VERTEXAI_V1BETA1=True
export GOOGLE_API_VERSION=v1beta1

# Prefer agy from PATH or local user bin
AGY_BIN="$(command -v agy || echo "${HOME}/.local/bin/agy")"

if [ ! -x "${AGY_BIN}" ]; then
  echo "Error: Antigravity CLI (agy) is not installed. Run scripts/post-create.sh to install it." >&2
  exit 1
fi

exec "${AGY_BIN}" "$@"
