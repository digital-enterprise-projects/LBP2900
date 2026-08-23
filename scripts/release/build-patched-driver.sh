#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_URL="https://github.com/mounaiban/captdriver.git"
UPSTREAM_COMMIT="62719249ac34633338be54bc74beddd0e7003d38"
PACKAGE_VERSION="0.1.4.1-direct-device.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${1:-$REPO_DIR/dist}"
PACKAGE_NAME="captdriver-$PACKAGE_VERSION"
ARCHIVE_PATH="$OUTPUT_DIR/$PACKAGE_NAME.tar.gz"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
WORK_DIR="$(mktemp -d /tmp/lbp2900-release.XXXXXX)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
git clone --quiet "$UPSTREAM_URL" "$WORK_DIR/source"
git -C "$WORK_DIR/source" checkout --quiet "$UPSTREAM_COMMIT"

actual_commit="$(git -C "$WORK_DIR/source" rev-parse HEAD)"
if [[ "$actual_commit" != "$UPSTREAM_COMMIT" ]]; then
  echo "Upstream commit mismatch: $actual_commit" >&2
  exit 1
fi

git -C "$WORK_DIR/source" apply "$REPO_DIR/captdriver-patch/direct-device-mode.patch"
cp "$REPO_DIR/captdriver-patch/direct-device-mode.patch" \
  "$WORK_DIR/source/DIRECT_DEVICE_PATCH.patch"
cp "$REPO_DIR/release/PATCH_INFO.md" "$WORK_DIR/source/PATCH_INFO.md"

git -C "$WORK_DIR/source" add src/capt-command.c DIRECT_DEVICE_PATCH.patch PATCH_INFO.md
SOURCE_DATE_EPOCH="$(git -C "$WORK_DIR/source" show -s --format=%ct "$UPSTREAM_COMMIT")"
GIT_AUTHOR_NAME="LBP2900 Release Builder" \
GIT_AUTHOR_EMAIL="noreply@example.invalid" \
GIT_AUTHOR_DATE="@$SOURCE_DATE_EPOCH" \
GIT_COMMITTER_NAME="LBP2900 Release Builder" \
GIT_COMMITTER_EMAIL="noreply@example.invalid" \
GIT_COMMITTER_DATE="@$SOURCE_DATE_EPOCH" \
  git -C "$WORK_DIR/source" commit --quiet \
  -m "Apply LBP2900 direct-device patch"

git -C "$WORK_DIR/source" archive --format=tar --prefix="$PACKAGE_NAME/" HEAD | \
  gzip -n > "$ARCHIVE_PATH"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUTPUT_DIR" && sha256sum "$(basename "$ARCHIVE_PATH")") > "$CHECKSUM_PATH"
else
  (cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ARCHIVE_PATH")") > "$CHECKSUM_PATH"
fi

printf 'Created:\n  %s\n  %s\n' "$ARCHIVE_PATH" "$CHECKSUM_PATH"
