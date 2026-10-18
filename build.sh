#!/usr/bin/env bash
# Builds and checks libvips for each stack, into build/. The same script runs on a laptop (Docker Desktop) and
# in the GitHub Actions workflow, which then publishes build/ as release assets.
#
#   VIPS_VERSION=8.18.7 ./build.sh            # heroku-26
#   VIPS_VERSION=8.18.7 STACK_VERSIONS="26 28" ./build.sh

set -eu -o pipefail

: "${VIPS_VERSION:?set VIPS_VERSION, e.g. VIPS_VERSION=8.18.7 ./build.sh}"
STACK_VERSIONS="${STACK_VERSIONS:-26}"

cd "$(dirname "$0")"
mkdir -p build

for stack in ${STACK_VERSIONS}; do
  name="libvips-${VIPS_VERSION}-heroku-${stack}-amd64"
  image="libvips-heroku-${stack}:${VIPS_VERSION}"

  echo "==> building ${name}"
  docker buildx build --platform linux/amd64 --load \
    --build-arg "STACK_VERSION=${stack}" --build-arg "VIPS_VERSION=${VIPS_VERSION}" \
    -t "${image}" -f container/Dockerfile container

  docker run --rm --platform linux/amd64 -v "${PWD}/build:/build" "${image}" sh -c 'cp /out/* /build/'

  echo "==> checking ${name} in the heroku-${stack} run image"
  docker buildx build --platform linux/amd64 --load \
    --build-arg "STACK_VERSION=${stack}" --build-arg "VIPS_VERSION=${VIPS_VERSION}" \
    --build-arg "TARBALL=build/${name}.tar.gz" \
    -t "libvips-heroku-${stack}-test:${VIPS_VERSION}" -f container/Dockerfile.test .

  echo "==> ${name} built and checked"
done

echo
ls -l build
cat build/*.sha256
