#!/bin/bash
set -e

# Check required Environment Variables passed from justfile
: "${GITHUB_OWNER_REPO?Env Var GITHUB_OWNER_REPO not set}"
: "${GHCR_TAG_LATEST?Env Var GHCR_TAG_LATEST not set}"
: "${GHCR_TAG_COMMIT?Env Var GHCR_TAG_COMMIT not set}"
# MANUAL_TAG and GHCR_IMAGE_BASE are optional, checked below

echo "⏫ Pushing images to GHCR..."
echo "   Target Base: ghcr.io/$GITHUB_OWNER_REPO/..."

# Added more robust check for default repo value
if [[ "$GITHUB_OWNER_REPO" == "hoffmann/montaigne" || "$GITHUB_OWNER_REPO" == "YOUR_USERNAME/YOUR_REPO" ]]; then
    echo "⚠️ Trying to push to default/fallback repository ('$GITHUB_OWNER_REPO')."
    echo "   Ensure GITHUB_REPOSITORY env var is set correctly if running locally."
    # read -p "   Press Enter to continue push, or Ctrl+C to cancel..." # Optional interactive check
    # exit 1; # Optional: Uncomment to prevent pushes to fallback repo
fi

echo "   Pushing GHCR Tag: ${GHCR_TAG_LATEST}"
docker push "${GHCR_TAG_LATEST}" || { echo "❌ Push failed: ${GHCR_TAG_LATEST}"; exit 1; }

echo "   Pushing GHCR Tag: ${GHCR_TAG_COMMIT}"
docker push "${GHCR_TAG_COMMIT}" || { echo "❌ Push failed: ${GHCR_TAG_COMMIT}"; exit 1; }

if [ -n "$MANUAL_TAG" ]; then
    # Check if GHCR_IMAGE_BASE is set for manual tag
    : "${GHCR_IMAGE_BASE?Env Var GHCR_IMAGE_BASE is needed for MANUAL_TAG but not set}"
    _GHCR_TAG_MANUAL="${GHCR_IMAGE_BASE}:${MANUAL_TAG}"
    echo "   Pushing GHCR Manual Tag: ${_GHCR_TAG_MANUAL}"
    docker push "${_GHCR_TAG_MANUAL}" || { echo "❌ Push failed: ${_GHCR_TAG_MANUAL}"; exit 1; }
fi
echo "✅ Images pushed to GHCR."
