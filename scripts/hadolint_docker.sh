#!/bin/bash
set -e

echo "⚠️ hadolint command not found, attempting to run via Docker..."
# Simple command execution is fine here
# Note: This assumes Docker is working on the host where just is run
if [ -f ".hadolint.yaml" ]; then
  docker run --rm -i -v "$(pwd)/.hadolint.yaml:/.hadolint.yaml" hadolint/hadolint < Dockerfile
else
  docker run --rm -i hadolint/hadolint < Dockerfile
fi || { echo "❌ Dockerfile linting failed using Dockerized hadolint"; exit 1; }
