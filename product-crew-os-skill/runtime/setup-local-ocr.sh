#!/usr/bin/env bash

set -euo pipefail

target="${PCO_OCR_ENV_DIR:-$HOME/.local/share/product-crew-os/ocr-env}"
uv_bin="${UV_BIN:-uv}"

"$uv_bin" venv "$target"
"$uv_bin" pip install --python "$target/bin/python" paddlepaddle paddleocr
"$target/bin/python" -c 'import paddle, paddleocr; print("Paddle=" + paddle.__version__); print("PaddleOCR=" + paddleocr.__version__)'

echo "Local OCR runtime installed at: $target"
echo "Product Crew OS discovers this path automatically. Set PCO_OCR_PYTHON only to override it."
