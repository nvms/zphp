#!/bin/bash
set -euo pipefail

IMAGE="zphp-php84"

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
    echo "building $IMAGE..."
    docker build -t "$IMAGE" "$(dirname "$0")" > /dev/null
fi

docker run --rm -v "$(cd "$(dirname "$0")" && pwd):/app" -w /app "$IMAGE" "$@"
