#!/usr/bin/env bash
# from here
# https://github.com/MozillaSecurity/orion/wiki/Build-ARM64-on-AMD64
USER=blacs30
NAME=samba-domain

for arch in armv7 amd64; do
    # docker build --no-cache -f Dockerfile.${arch} -t $USER/$NAME:${arch}-18.04 -t $USER/$NAME:${arch}-latest .
    docker buildx build -f Dockerfile.${arch} --push -t $USER/$NAME:${arch}-18.04 -t $USER/$NAME:${arch}-latest   .
done
