#!/bin/bash
set -e
echo "=== Building WebRTC Pure Internet Audio Calling App for Netlify Deployment ==="
cd webrtc_calling/frontend
npm install
npm run build
echo "=== Build Completed Successfully ==="
