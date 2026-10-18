# Builds the trimmed libvips for one Heroku stack, in that stack's own build image, so the result links exactly
# the shared libraries the run image carries. Outputs land in /out: the tarball, its sha256, and the build's
# `vips --vips-config`. Driven by ../build.sh; the shape follows brandoncc/heroku-buildpack-vips (MIT).
#
#   docker buildx build --platform linux/amd64 --build-arg STACK_VERSION=26 --build-arg VIPS_VERSION=8.18.7 \
#     -f container/Dockerfile -t libvips-heroku-26:8.18.7 container

ARG STACK_VERSION=26
FROM heroku/heroku:${STACK_VERSION}-build

ARG STACK_VERSION
ARG VIPS_VERSION
USER root
ENV DEBIAN_FRONTEND=noninteractive

# Headers for what we link. The build image already has libjpeg-dev, libheif-dev, libexif-dev and zlib1g-dev;
# they are listed anyway so the build does not depend on the image keeping them. Nothing here adds a run-time
# dependency: every library is in the run image because the stack's own libvips package needs it.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    meson \
    ninja-build \
    pkg-config \
    libglib2.0-dev \
    libexpat1-dev \
    libjpeg-dev \
    libpng-dev \
    libwebp-dev \
    libheif-dev \
    libexif-dev \
    liblcms2-dev \
    libhwy-dev \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/src

# The upstream release tarball, verified against the sha256 published beside it. Python's tarfile unpacks and
# packs here rather than GNU tar: under Docker Desktop's Rosetta emulation on an Apple Silicon laptop, Ubuntu
# 26.04's tar fails every entry with "Function not implemented" (a syscall Rosetta lacks); Python uses plain
# file calls and works the same there and on an amd64 runner. bin/compile runs on a real dyno and uses tar.
RUN curl -fsSL -o "vips-${VIPS_VERSION}.tar.xz" \
      "https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz" \
  && curl -fsSL -o "vips-${VIPS_VERSION}.tar.xz.sha256sum" \
      "https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz.sha256sum" \
  && sha256sum --check "vips-${VIPS_VERSION}.tar.xz.sha256sum" \
  && python3 -c 'import sys, tarfile; tarfile.open(sys.argv[1]).extractall(filter="data")' "vips-${VIPS_VERSION}.tar.xz"

# The install prefix is the path the buildpack untars to on a dyno ($HOME/.heroku/vips with $HOME=/app), so
# nothing baked into the build points anywhere else.
ARG PREFIX=/app/.heroku/vips

# Only the loaders for the formats we process (JPEG, PNG, GIF, WebP, HEIF) and the savers for what we write
# (JPEG, PNG; WebP and HEIF saving come with their loaders). Everything optional is named explicitly, enabled
# or disabled: `auto` would pick up whatever the build image happens to have (it has ImageMagick's headers).
# Modules are off because ruby-vips loads libvips in-process and the stack's own build had HEIF trouble with
# them (brandoncc's note); deprecated API, C++ API, examples, docs and introspection are not needed.
RUN cd "vips-${VIPS_VERSION}" \
  && meson setup build \
    --prefix="${PREFIX}" \
    --libdir=lib \
    --buildtype=release \
    -Ddeprecated=false \
    -Dexamples=false \
    -Dcplusplus=false \
    -Ddocs=false \
    -Dcpp-docs=false \
    -Dmodules=disabled \
    -Dintrospection=disabled \
    -Dvapi=false \
    -Djpeg=enabled \
    -Dpng=enabled \
    -Dwebp=enabled \
    -Dheif=enabled \
    -Dheif-module=disabled \
    -Dexif=enabled \
    -Dlcms=enabled \
    -Dhighway=enabled \
    -Dzlib=enabled \
    -Dnsgif=true \
    -Dppm=false \
    -Danalyze=false \
    -Dradiance=false \
    -Dcgif=disabled \
    -Dspng=disabled \
    -Dtiff=disabled \
    -Dmagick=disabled \
    -Dmagick-module=disabled \
    -Dpdfium=disabled \
    -Dpoppler=disabled \
    -Dpoppler-module=disabled \
    -Drsvg=disabled \
    -Djpeg-xl=disabled \
    -Djpeg-xl-module=disabled \
    -Dopenjpeg=disabled \
    -Dopenexr=disabled \
    -Dopenslide=disabled \
    -Dopenslide-module=disabled \
    -Dcfitsio=disabled \
    -Dmatio=disabled \
    -Dnifti=disabled \
    -Draw=disabled \
    -Duhdr=disabled \
    -Dfftw=disabled \
    -Darchive=disabled \
    -Dpangocairo=disabled \
    -Dfontconfig=disabled \
    -Dorc=disabled \
    -Dimagequant=disabled \
    -Dquantizr=disabled \
  && meson compile -C build \
  && meson install -C build

ENV PATH="${PREFIX}/bin:${PATH}" \
    LD_LIBRARY_PATH="${PREFIX}/lib"

# Trim and package: no static libs, no python profiler script; strip the binaries. The headers and pkgconfig
# files are kept (small) for anything that wants to compile against the library during a build.
RUN cd "${PREFIX}" \
  && rm -f bin/vipsprofile lib/*.a lib/*.la \
  && strip --strip-unneeded lib/*.so* bin/* \
  && name="libvips-${VIPS_VERSION}-heroku-${STACK_VERSION}-$(dpkg --print-architecture)" \
  && mkdir -p /out \
  && python3 -c 'import sys, tarfile; t = tarfile.open(sys.argv[1], "w:gz"); [t.add(d) for d in sys.argv[2:]]; t.close()' "/out/${name}.tar.gz" bin include lib \
  && (cd /out && sha256sum "${name}.tar.gz" > "${name}.tar.gz.sha256") \
  && { echo "\$ vips --version"; vips --version; echo; echo "\$ vips --vips-config"; vips --vips-config; } > "/out/${name}.config.log" \
  && ls -l /out
