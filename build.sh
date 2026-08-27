#!/bin/bash
set -e
echo "=== Deploying GebTalk Flutter Mobile Web App ==="
if command -v flutter &> /dev/null; then
  cd gebtalk_flutter
  flutter build web --release
  cp web/_redirects build/web/_redirects || true
fi
echo "=== GebTalk Ready ==="
