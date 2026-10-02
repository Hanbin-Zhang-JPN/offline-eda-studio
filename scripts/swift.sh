#!/bin/bash
set -euo pipefail
# CLT preview SDK 27 includes State macros without their plugin; use installed stable SDK.
if [[ -n "${EDA_SDK:-}" ]]; then
  exec swift "$@" --sdk "$EDA_SDK"
fi
sdk=$(xcrun --show-sdk-path)
if [[ "$sdk" == *MacOSX27* || "$(readlink "$sdk" 2>/dev/null || true)" == *MacOSX27* ]]; then
  if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    exec swift "$@" --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  fi
fi
exec swift "$@"
