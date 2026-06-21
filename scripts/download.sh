#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="$(mktemp)"

echo "===> Start download"

download_ok=0

if make download -j"$(nproc)" 2>&1 | tee "$LOG_FILE"; then
	if grep -E "ERROR:|Hash mismatch|failed to build" "$LOG_FILE" >/dev/null; then
		echo "Download error detected"
	else
		download_ok=1
	fi
fi

if [ "$download_ok" -ne 1 ]; then
	echo "First download failed, retrying..."

	if make download -j1 V=s 2>&1 | tee "$LOG_FILE"; then
		if grep -E "ERROR:|Hash mismatch|failed to build" "$LOG_FILE" >/dev/null; then
			echo "Retry still failed"
		else
			download_ok=1
		fi
	fi
fi

if [ "$download_ok" -ne 1 ]; then
	echo "Download failed!"
	exit 1
fi

echo "===> Check broken files"

mapfile -t failed_files < <(find dl -type f -size -1024c 2>/dev/null || true)

if [ "${#failed_files[@]}" -gt 0 ]; then
	echo "Broken files detected:"
	printf '%s\n' "${failed_files[@]}"

	ls -l "${failed_files[@]}"
	rm -f "${failed_files[@]}"

	exit 1
fi

echo "Download success"
