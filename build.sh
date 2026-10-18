#!/usr/bin/env bash
# Builds and checks libvips (with its libheif) for each stack, into build/. The same script runs on a laptop
# (Docker Desktop) and in the GitHub Actions workflow, which then publishes build/ as release assets.
#
#   VIPS_VERSION=8.18.7 LIBHEIF_VERSION=1.23.6 ./build.sh            # heroku-26
#   VIPS_VERSION=8.18.7 LIBHEIF_VERSION=1.23.6 STACK_VERSIONS="26 28" ./build.sh

set -eu -o pipefail

: "${VIPS_VERSION:?set VIPS_VERSION, e.g. VIPS_VERSION=8.18.7 LIBHEIF_VERSION=1.23.6 ./build.sh}"
: "${LIBHEIF_VERSION:?set LIBHEIF_VERSION, e.g. VIPS_VERSION=8.18.7 LIBHEIF_VERSION=1.23.6 ./build.sh}"
STACK_VERSIONS="${STACK_VERSIONS:-26}"

cd "$(dirname "$0")"
mkdir -p build

for stack in ${STACK_VERSIONS}; do
  name="libvips-${VIPS_VERSION}-heif${LIBHEIF_VERSION}-heroku-${stack}-amd64"
  tag="${VIPS_VERSION}-heif${LIBHEIF_VERSION}"
  image="libvips-heroku-${stack}:${tag}"

  echo "==> building ${name}"
  docker buildx build --platform linux/amd64 --load \
    --build-arg "STACK_VERSION=${stack}" --build-arg "VIPS_VERSION=${VIPS_VERSION}" --build-arg "LIBHEIF_VERSION=${LIBHEIF_VERSION}" \
    -t "${image}" -f container/Dockerfile container

  docker run --rm --platform linux/amd64 -v "${PWD}/build:/build" "${image}" sh -c 'cp /out/* /build/'

  echo "==> checking ${name} in the heroku-${stack} run image"
  docker buildx build --platform linux/amd64 --load \
    --build-arg "STACK_VERSION=${stack}" --build-arg "VIPS_VERSION=${VIPS_VERSION}" --build-arg "LIBHEIF_VERSION=${LIBHEIF_VERSION}" \
    --build-arg "TARBALL=build/${name}.tar.gz" \
    -t "libvips-heroku-${stack}-test:${tag}" -f container/Dockerfile.test .

  echo "==> ${name} built and checked"
done

echo
ls -l build
cat build/*.sha256
