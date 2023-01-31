#!/usr/bin/env bash
set -euo pipefail

# Trick originally stolen from
# https://github.com/numtide/nixpkgs-unfree/blob/main/ci.sh
#
# We loosely adapted this trick to first check if the closure is
# already present in the binary cache through nix-eval-job's
# --check-cache-status.

args=(
  "$@"
  --gc-roots-dir gc-root
  --max-memory-size "12000"
  --show-trace
  --workers 4
  --check-cache-status
  ./ci/ci.nix
)

log() {
    echo "$*"
}

error=0

for job in $(nix-eval-jobs "${args[@]}" | jq -r 'select(.isCached == false) | @base64'); do
  job=$(echo "$job" | base64 -d)
  attr=$(echo "$job" | jq -r .attr)
  echo "### $attr"
  error=$(echo "$job" | jq -r .error)
  if [[ $error != null ]]; then
    log "### ❌ $attr"
    log
    log "<details><summary>Eval error:</summary><pre>"
    log "$error"
    log "</pre></details>"
    error=1
  else
    drvPath=$(echo "$job" | jq -r .drvPath)
    if ! nix-store --realize "$drvPath" 2>&1 | tee build-log.txt; then
      log "### ❌ $attr"
      log
      log "<details><summary>Build error:</summary>last 50 lines:<pre>"
      log "$(tail -n 50 build-log.txt)"
      log "</pre></details>"
      error=1
    else
      log "### ✅ $attr"
    fi
    log
  fi
done

exit "$error"
