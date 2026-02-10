#!/bin/bash
exec brave-browser \
  --enable-gpu-rasterization \
  --enable-zero-copy \
  --disk-cache-size=1073741824 \
  --enable-features=VaapiVideoDecoder \
  --disable-features=UseChromeOSDirectVideoDecoder \
  "$@"
