#!/usr/bin/env bash
set -euo pipefail
LIST_FILE="/home/libpet-aps/hmi_test/.cache/autoware_startup_prewarm.files"
LOG_FILE="/home/libpet-aps/hmi_test/.log/autoware_startup_prewarm.log"
mkdir -p "$(dirname "$LOG_FILE")"
start_ms=$(date +%s%3N)
count=0
bytes=0
if [[ -r "$LIST_FILE" ]]; then
  while IFS= read -r file; do
    [[ -r "$file" && -f "$file" ]] || continue
    size=$(stat -Lc '%s' "$file" 2>/dev/null || echo 0)
    bytes=$((bytes + size))
    count=$((count + 1))
    cat "$file" >/dev/null 2>/dev/null || true
  done < "$LIST_FILE"
fi
end_ms=$(date +%s%3N)
printf '[%s] prewarmed files=%d bytes=%d elapsed_ms=%d\n' "$(date --iso-8601=seconds)" "$count" "$bytes" "$((end_ms - start_ms))" >> "$LOG_FILE"
