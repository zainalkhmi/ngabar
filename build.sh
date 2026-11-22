#!/bin/bash
set -e

echo "=== Installing Flutter SDK ==="
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter
fi

export PATH="$PATH:`pwd`/flutter/bin"

echo "=== Flutter Environment ==="
flutter --version
flutter config --no-analytics

# Ensure dummy ONNX model asset exists so flutter build web passes asset validation
mkdir -p assets/model
if [ ! -f "assets/model/zipformer_p_arabic_v3.int8.onnx" ]; then
  echo "Creating placeholder for ONNX model asset..."
  touch assets/model/zipformer_p_arabic_v3.int8.onnx
fi

echo "=== Building Flutter Web Release ==="
flutter build web --release --no-tree-shake-icons

echo "=== Build Completed Successfully ==="
