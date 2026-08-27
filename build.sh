#!/bin/bash
set -e
echo "=== Building WebRTC Pure Internet Audio Calling App for Netlify Deployment ==="
cd webrtc_calling/frontend
npm install
npm run build
cd ../..

echo "=== Syncing built dist to all target publish directories ==="
mkdir -p dist
cp -r webrtc_calling/frontend/dist/* dist/

mkdir -p gebtalk_flutter/build/web
cp -r webrtc_calling/frontend/dist/* gebtalk_flutter/build/web/

mkdir -p public
cp -r webrtc_calling/frontend/dist/* public/

echo "=== Build & Sync Completed Successfully ==="
