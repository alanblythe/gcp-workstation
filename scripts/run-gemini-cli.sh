export GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo "your-project-id")}"
# Gemini 3 Pro Preview is available on the global endpoint
export GOOGLE_CLOUD_LOCATION=global
export GOOGLE_GENAI_USE_VERTEXAI=true
export GOOGLE_GENAI_USE_VERTEXAI_V1BETA1=True
export GOOGLE_API_VERSION=v1beta1


case "$1" in
  --interactive)
    shift
    gemini --model gemini-3-pro-preview "$@"
    ;;
  *)
    gemini --model gemini-3-pro-preview "$@" 2>&1 | grep --line-buffered -vE "\[STARTUP\]|Attempt [0-9]+ failed with status 429|ApiError:|at throwErrorIfNotOK|at process\.processTicks|at async|status: 429|RESOURCE_EXHAUSTED"
    ;;
esac

