#!/usr/bin/env bash
set -euo pipefail

nix-build-uncached ./ci/ci.nix
