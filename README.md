# heroku-libvips-buildpack

A Heroku buildpack that installs our own trimmed, current build of [libvips](https://github.com/libvips/libvips),
with its own [libheif](https://github.com/strukturag/libheif), on heroku-26, ahead of the stack image's own
`libvips42t64` and `libheif1` packages.

## Why

The stack image ships libvips from Ubuntu's *universe* pocket, which Ubuntu patches only through Ubuntu Pro, so
upstream fixes never reach a dyno (heroku-26 has 8.18.0 while upstream is at 8.18.7 with security fixes). This
buildpack makes the libvips version ours to move: a fix is a version bump here.

The build is trimmed to what we process. Loaders: JPEG, PNG, GIF, WebP, HEIF. Savers: JPEG, PNG (WebP and HEIF
saving come with their loaders). No TIFF, PDF, SVG, ImageMagick fallback, JPEG XL, JPEG 2000, OpenEXR,
OpenSlide, FITS, Matlab, NIfTI, PPM, Radiance, Analyze, libraw or Ultra HDR, no dynamic modules, no C++ or
deprecated API. Most libvips advisories are in those loaders; a loader that is not compiled in cannot be
reached by an upload, whatever a file's content says it is.

libheif is built here too, for two reasons. libvips 8.18.6 and later tag `heifload` as *untrusted* when built
against a libheif older than 1.23.2, and the app blocks untrusted operations (`Vips.block_untrusted`), so with
the image's libheif 1.21.2 every HEIC upload failed on a dyno. And libheif is the one library we decode untrusted
phone uploads with whose upstream fixes security issues faster than Ubuntu backports them (one to two months
behind, with 26 CVEs in 2026). The build is HEIC decoding only: libde265 linked in (the image's package, not a
plugin), no encoders (we never write HEIF), no AVIF or other decoders, no uncompressed-image codec, no plugin
loading.

## What it does

`bin/compile` downloads `libvips-<vips>-heif<libheif>-<stack>-amd64.tar.gz` from this repo's release
`libvips-<vips>-heif<libheif>`, verifies it against the sha256 pinned in `bin/compile`, untars it into
`/app/.heroku/vips`, and writes `.profile.d/000_vips.sh`, which prepends `/app/.heroku/vips/lib` to
`LD_LIBRARY_PATH` (and `bin` to `PATH`). `LD_LIBRARY_PATH` is searched before the system directories, so
`ruby-vips`'s `dlopen("libvips.so.42")` finds this build and not the stack package's, and this libvips finds this
libheif; both stack packages stay in the image unused. `vips`, `vipsheader` and `vipsthumbnail` are on the `PATH`
of every dyno.

The libraries link the run image's own shared libraries (libjpeg-turbo, libpng, libwebp, libde265, glib, expat,
libexif, lcms2, highway): every one of them is in the image because the stack's libvips and libheif packages need
it, so nothing else is carried.

## Using it

```
heroku buildpacks:add -i 2 "https://github.com/fieldnotescommunities/heroku-libvips-buildpack.git#<commit>" -a APP
```

Pin to a commit: the commit fixes the versions and the sha256 of what is installed. Deploy a commit the app has
not built (a buildpack change only takes effect at a build). The build log shows
`-----> Installing libvips 8.18.7 with libheif 1.23.6 for heroku-26 (amd64)` and `Installed vips-8.18.7`.

## Building a version

The build runs in Docker, in the stack's build image (`heroku/heroku:26-build`), and is then checked in the
stack's run image (`heroku/heroku:26`): `ldd` finds every library and shows libvips linking our libheif, `vips -l`
lists exactly the reviewed loaders and savers (`test/expected_operations.txt`) with `heifload` not tagged
untrusted, each sample in `test/samples/` converts to JPEG and PNG, and `ruby-vips` loads this libvips and this
libheif and loads every sample again under the blocking the app applies (`test/check.rb`: every loader and saver
blocked except ours, plus libvips's untrusted operations). The same script runs on a laptop (Docker Desktop must
be running; on Apple Silicon it builds the amd64 image under Rosetta, which is why the Dockerfiles unpack with
Python rather than GNU tar) and in GitHub Actions.

```
VIPS_VERSION=8.18.7 LIBHEIF_VERSION=1.23.6 ./build.sh   # build/ gets the tarball, its .sha256 and the config log
```

Every pull request runs the same build and check for the versions `bin/compile` pins. To publish, run the
**Build libvips** workflow by hand (Actions, "Run workflow", both versions; it appears there once the workflow
file is on `main`). That run also puts the tarball, `.sha256` and `.config.log` on the release
`libvips-<vips>-heif<libheif>`.

To move to a new version of either library:

1. For a new libheif, hash its release tarball (`libheif-<version>.tar.gz` from
   https://github.com/strukturag/libheif/releases; libheif publishes no checksum) and add the line to
   `container/checksums.txt`. libvips's checksum is published beside its tarball and checked directly.
2. Run the workflow for the versions.
3. Put the versions and the sha256 from the release's `.sha256` asset into `bin/compile`'s `case` for the stack.
4. If `test/check.sh` reported a change in the operation list, review it and update `test/expected_operations.txt`.
5. Commit, note it in `CHANGELOG.md`, and move the apps' pin to the new commit (in the webapp,
   `thor media_smoke_test:buildpack_updates --record --buildpack vips`, then `heroku buildpacks:set`).

A rebuild of the same two versions keeps the tarball's name; the sha256 pin is what makes that visible.

## Layout

- `bin/detect`, `bin/compile`, `bin/release`: the buildpack.
- `container/Dockerfile`: the build, with libheif's cmake options and libvips's meson options;
  `container/checksums.txt` pins the libheif source tarballs.
- `container/Dockerfile.test`: the check in the run image.
- `test/check.sh`, `test/check.rb`, `test/expected_operations.txt`, `test/samples/`: what the check asserts.
- `build.sh`: runs both for each stack into `build/` (gitignored).
- `.github/workflows/build.yml`: `build.sh` plus the release upload.

## Credits

The Docker-based build and run-image check follow
[brandoncc/heroku-buildpack-vips](https://github.com/brandoncc/heroku-buildpack-vips) (MIT); the download of a
release asset at build time follows
[hardpixel/heroku-buildpack-vips](https://github.com/hardpixel/heroku-buildpack-vips) (MIT). Neither supports
heroku-26 or trims the build, hence this one.

## Licence

MIT, see `LICENSE`.
