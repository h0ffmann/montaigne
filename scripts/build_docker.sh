#!/bin/bash
set -e

# Check required Environment Variables passed from justfile
: "${DOCKER_IMAGE_NAME?Env Var DOCKER_IMAGE_NAME not set}"
: "${DOCKER_TAG_LATEST?Env Var DOCKER_TAG_LATEST not set}"
: "${DOCKER_TAG_GIT?Env Var DOCKER_TAG_GIT not set}"
: "${GHCR_TAG_LATEST?Env Var GHCR_TAG_LATEST not set}"
: "${GHCR_TAG_COMMIT?Env Var GHCR_TAG_COMMIT not set}"
# MANUAL_TAG and GHCR_IMAGE_BASE are optional, check below

_DOCKER_BUILD_ARGS=""
_DOCKER_FLAGS=""
USE_LOCAL_ARG_FOUND="false"

# Process all arguments passed to this script ($@)
for arg in "$@"; do
    if [[ "$arg" == *=* ]]; then
       _DOCKER_BUILD_ARGS="${_DOCKER_BUILD_ARGS} --build-arg $arg"
       if [[ "$arg" == USE_LOCAL_MODEL=true ]]; then USE_LOCAL_ARG_FOUND="true"; fi
    else
       _DOCKER_FLAGS="${_DOCKER_FLAGS} $arg"
    fi
done

if [ "$USE_LOCAL_ARG_FOUND" = "true" ]; then
    echo "   Build argument USE_LOCAL_MODEL=true found. Ensure 'prepare_docker_files' was run."
    # Preparation should happen *before* calling this script now
    if [ ! -f entrypoint.sh ]; then
       echo "   ⚠️ WARNING: USE_LOCAL_MODEL=true but entrypoint.sh not found. 'prepare_docker_files' might be missing."
    fi
else
    echo "   Build argument USE_LOCAL_MODEL=true not found."
     # Check if entrypoint exists even if not using local model, as prepare step should create it
    if [ ! -f entrypoint.sh ]; then
       echo "   ⚠️ WARNING: entrypoint.sh not found. 'prepare_docker_files' might be missing."
    fi
fi


echo "🐳 Building Docker image..."
echo "   Docker Build Flags: ${_DOCKER_FLAGS}"
echo "   Docker Build Args: ${_DOCKER_BUILD_ARGS}"
echo "   Local Tags:         ${DOCKER_IMAGE_NAME}:${DOCKER_TAG_LATEST}, ${DOCKER_IMAGE_NAME}:${DOCKER_TAG_GIT}"
echo "   GHCR Tags:          ${GHCR_TAG_LATEST}, ${GHCR_TAG_COMMIT}"

# Execute the build command
docker build \
    ${_DOCKER_FLAGS} \
    ${_DOCKER_BUILD_ARGS} \
    -t "${DOCKER_IMAGE_NAME}:${DOCKER_TAG_LATEST}" \
    -t "${DOCKER_IMAGE_NAME}:${DOCKER_TAG_GIT}" \
    -t "${GHCR_TAG_LATEST}" \
    -t "${GHCR_TAG_COMMIT}" \
    . || { echo "❌ Docker build failed"; exit 1; }

# Add manual tag if provided via environment variable
if [ -n "$MANUAL_TAG" ]; then
    # Check if GHCR_IMAGE_BASE is set for manual tag
    : "${GHCR_IMAGE_BASE?Env Var GHCR_IMAGE_BASE is needed for MANUAL_TAG but not set}"
    _MANUAL_TAG_FULL="${GHCR_IMAGE_BASE}:${MANUAL_TAG}";
    echo "   Adding manual tag: ${_MANUAL_TAG_FULL}";
    docker tag "${DOCKER_IMAGE_NAME}:${DOCKER_TAG_LATEST}" "${_MANUAL_TAG_FULL}";
fi
echo "✅ Docker image built successfully."
