# Builds the trimmed libvips, with its own libheif, for one Heroku stack, in that stack's own build image, so the
# result links exactly the shared libraries the run image carries. Outputs land in /out: the tarball, its sha256,
# and the build's configuration log. Driven by ../build.sh; the shape follows brandoncc/heroku-buildpack-vips (MIT).
#
#   docker buildx build --platform linux/amd64 --build-arg STACK_VERSION=26 --build-arg VIPS_VERSION=8.18.7 \
#     --build-arg LIBHEIF_VERSION=1.23.6 -f container/Dockerfile -t libvips-heroku-26:8.18.7-heif1.23.6 container

ARG STACK_VERSION=26
FROM heroku/heroku:${STACK_VERSION}-build

ARG STACK_VERSION
ARG VIPS_VERSION
ARG LIBHEIF_VERSION
USER root
ENV DEBIAN_FRONTEND=noninteractive

# Headers for what we link. The build image already has cmake, libjpeg-dev, libexif-dev and zlib1g-dev; they are
# listed anyway so the build does not depend on the image keeping them. libde265-dev is for our libheif (the run
# image has libde265-0 for the stack's own libheif plugin). The image's libheif-dev is removed so libvips can only
# find ours. Nothing here adds a run-time dependency: every library is in the run image because the stack's own
# libvips package needs it.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    cmake \
    meson \
    ninja-build \
    pkg-config \
    libglib2.0-dev \
    libexpat1-dev \
    libjpeg-dev \
    libpng-dev \
    libwebp-dev \
    libde265-dev \
    libexif-dev \
    liblcms2-dev \
    libhwy-dev \
    zlib1g-dev \
  && apt-get remove -y libheif-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/src
COPY checksums.txt .

# The upstream release tarballs, verified: libvips against the sha256 published beside it, libheif against
# checksums.txt (it publishes none). Python's tarfile unpacks and packs here rather than GNU tar: under Docker
# Desktop's Rosetta emulation on an Apple Silicon laptop, Ubuntu 26.04's tar fails every entry with "Function not
# implemented" (a syscall Rosetta lacks); Python uses plain file calls and works the same there and on an amd64
# runner. bin/compile runs on a real dyno and uses tar.
RUN curl -fsSL -o "vips-${VIPS_VERSION}.tar.xz" \
      "https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz" \
  && curl -fsSL -o "vips-${VIPS_VERSION}.tar.xz.sha256sum" \
      "https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz.sha256sum" \
  && sha256sum --check "vips-${VIPS_VERSION}.tar.xz.sha256sum" \
  && curl -fsSL -o "libheif-${LIBHEIF_VERSION}.tar.gz" \
      "https://github.com/strukturag/libheif/releases/download/v${LIBHEIF_VERSION}/libheif-${LIBHEIF_VERSION}.tar.gz" \
  && sha256sum --check --ignore-missing checksums.txt \
  && python3 -c 'import sys, tarfile; [tarfile.open(f).extractall(filter="data") for f in sys.argv[1:]]' \
      "vips-${VIPS_VERSION}.tar.xz" "libheif-${LIBHEIF_VERSION}.tar.gz"

# The install prefix is the path the buildpack untars to on a dyno ($HOME/.heroku/vips with $HOME=/app), so
# nothing baked into the build points anywhere else.
ARG PREFIX=/app/.heroku/vips

# libheif is ours rather than the image's because libvips (8.18.6 and later) tags heifload UNTRUSTED when built
# against a libheif older than 1.23.2, and the app blocks untrusted operations; and because libheif's upstream
# security releases reach a dyno months before Ubuntu's backports do. Only what HEIC decoding needs: libde265
# linked in (not loaded as a plugin), no encoders (we never write HEIF), no AVIF or other decoders, no
# uncompressed-image codec (a critical fix of September 2026 was there), no examples, tools or plugin loading.
RUN cd "libheif-${LIBHEIF_VERSION}" \
  && cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=ON \
    -DENABLE_PLUGIN_LOADING=OFF \
    -DWITH_LIBDE265=ON \
    -DWITH_LIBDE265_PLUGIN=OFF \
    -DWITH_X265=OFF \
    -DWITH_X264=OFF \
    -DWITH_OpenH264_DECODER=OFF \
    -DWITH_KVAZAAR=OFF \
    -DWITH_UVG266=OFF \
    -DWITH_VVDEC=OFF \
    -DWITH_VVENC=OFF \
    -DWITH_AOM_DECODER=OFF \
    -DWITH_AOM_ENCODER=OFF \
    -DWITH_DAV1D=OFF \
    -DWITH_SvtEnc=OFF \
    -DWITH_RAV1E=OFF \
    -DWITH_JPEG_DECODER=OFF \
    -DWITH_JPEG_ENCODER=OFF \
    -DWITH_OpenJPEG_DECODER=OFF \
    -DWITH_OpenJPEG_ENCODER=OFF \
    -DWITH_OPENJPH_ENCODER=OFF \
    -DWITH_FFMPEG_DECODER=OFF \
    -DWITH_UNCOMPRESSED_CODEC=OFF \
    -DWITH_WEBCODECS=OFF \
    -DWITH_LIBSHARPYUV=OFF \
    -DWITH_HEADER_COMPRESSION=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_GDK_PIXBUF=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_DOCUMENTATION=OFF \
  && cmake --build build --parallel \
  && cmake --install build

# libvips finds our libheif through its pkgconfig file in the prefix, ahead of the image's libheif-dev (which the
# build image carries for its own packages).
ENV PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

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

# Trim and package: no static libs, no python profiler script, no cmake package files; strip the binaries. The
# headers and pkgconfig files are kept (small) for anything that wants to compile against the libraries during a
# build. The config log records both versions, libheif's from its pkgconfig file (the library itself says it
# through heif_get_version(), which the check reads).
RUN cd "${PREFIX}" \
  && rm -rf bin/vipsprofile lib/*.a lib/*.la lib/cmake \
  && strip --strip-unneeded lib/*.so* bin/* \
  && name="libvips-${VIPS_VERSION}-heif${LIBHEIF_VERSION}-heroku-${STACK_VERSION}-$(dpkg --print-architecture)" \
  && mkdir -p /out \
  && python3 -c 'import sys, tarfile; t = tarfile.open(sys.argv[1], "w:gz"); [t.add(d) for d in sys.argv[2:]]; t.close()' "/out/${name}.tar.gz" bin include lib \
  && (cd /out && sha256sum "${name}.tar.gz" > "${name}.tar.gz.sha256") \
  && { echo "\$ vips --version"; vips --version; echo; echo "\$ pkg-config --modversion libheif"; pkg-config --modversion libheif; echo; \
       echo "\$ vips --vips-config"; vips --vips-config; } > "/out/${name}.config.log" \
  && ls -l /out
