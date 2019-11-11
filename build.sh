#!/usr/bin/env bash
# from here
# https://github.com/MozillaSecurity/orion/wiki/Build-ARM64-on-AMD64
USER=blacs30
NAME=samba-domain

for arch in amd64 arm64v8; do
    docker build --no-cache -f Dockerfile.${arch} -t $USER/$NAME:${arch}-18.04 -t $USER/$NAME:${arch}-latest .
    docker push $USER/$NAME:${arch}-latest
    docker push $USER/$NAME:${arch}-18.04
done
