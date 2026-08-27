#!/bin/bash
set -e
echo "=== Building WebRTC Pure Internet Audio Calling App inside gebtalk_flutter ==="
cd ../webrtc_calling/frontend 2>/dev/null || cd webrtc_calling/frontend
npm install
npm run build

mkdir -p ../../gebtalk_flutter/build/web 2>/dev/null || mkdir -p gebtalk_flutter/build/web
cp -r dist/* ../../gebtalk_flutter/build/web/ 2>/dev/null || cp -r dist/* gebtalk_flutter/build/web/

mkdir -p ../../dist 2>/dev/null || mkdir -p dist
cp -r dist/* ../../dist/ 2>/dev/null || cp -r dist/* dist/

echo "=== Build Complete ==="
