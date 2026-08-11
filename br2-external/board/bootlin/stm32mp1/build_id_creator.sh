#!/bin/sh
set -e

TARGET_DIR="$1"

GIT_COMMIT=$(git rev-parse --short HEAD)
BUILD_DATE=$(date +%Y-%m-%d)

{
    echo "commit: ${GIT_COMMIT}"
    echo "date: ${BUILD_DATE}"
} > "${TARGET_DIR}/etc/build-id"
