#!/usr/bin/env bash
# check.sh <VIPS_VERSION> <SAMPLES_DIR> <EXPECTED_OPERATIONS_FILE>
#
# Run inside the stack's run image with the tarball installed (container/Dockerfile.test). Fails on the first
# thing a dyno would get wrong: a library the run image lacks, libvips linking the image's libheif rather than
# ours, a loader or saver that should not be there (or one that should), a loader tagged untrusted, a format we
# load that does not convert. check.rb then repeats the loading through ruby-vips under the app's blocking.

set -eu -o pipefail

version="$1"
samples="$2"
expected="$3"
prefix="/app/.heroku/vips"

fail() {
  echo "CHECK FAILED: $*" >&2
  exit 1
}

echo "==> version"
vips --version
[[ "$(vips --version)" == "vips-${version}"* ]] || fail "vips --version is not ${version}"

echo "==> shared libraries (nothing may be 'not found' in the run image; libheif must be ours)"
for file in "${prefix}/lib/libvips.so.42" "${prefix}/lib/libheif.so.1" "${prefix}/bin/vips" "${prefix}/bin/vipsheader" "${prefix}/bin/vipsthumbnail"; do
  ldd "${file}" | grep -q "not found" && { ldd "${file}"; fail "${file} has unresolved libraries"; }
done
ldd "${prefix}/lib/libvips.so.42" | sort
ldd "${prefix}/lib/libvips.so.42" | grep -q "libheif.so.1 => ${prefix}/lib/" || fail "libvips does not link the libheif in ${prefix}/lib"
ldd "${prefix}/lib/libheif.so.1" | grep -q "libde265.so" || fail "libheif does not link libde265 (HEVC decoding)"

echo "==> loaders and savers"
operations="$(mktemp)"
vips -l | grep -E 'VipsForeign(Load|Save)' | sed -n 's/.*(\([a-z0-9_]*\)).*/\1/p' | sort -u > "${operations}"
cat "${operations}"

# libvips 8.18.6+ tags heifload "untrusted" when built against a libheif older than 1.23.2, and the app blocks
# untrusted operations: the flag would make every HEIC fail on a dyno (test/check.rb proves the loading itself)
vips -l heifload
vips -l heifload | grep -q "untrusted" && fail "heifload is tagged untrusted (libvips was built against too old a libheif)"

for must in jpegload pngload gifload webpload heifload jpegsave pngsave; do
  grep -qx "${must}" "${operations}" || fail "${must} is missing"
done
for must_not in tiffload magickload pdfload svgload openslideload fitsload matload niftiload openexrload jp2kload jxlload \
                ppmload radload analyzeload uhdrload gifsave tiffsave magicksave ppmsave radsave jxlsave jp2ksave uhdrsave; do
  grep -qx "${must_not}" "${operations}" && fail "${must_not} is present but should not be built"
done

# The committed list is the exact set reviewed for the last build; a difference is a change to review (an
# upstream addition, an option that stopped taking effect). A list with no entries yet (first build) only
# prints the set above, to be copied into the file.
if grep -vq '^#' "${expected}"; then
  if ! diff <(grep -v '^#' "${expected}" | sort -u) "${operations}"; then
    fail "the loaders and savers differ from ${expected##*/} (< expected, > built); review, then update the file"
  fi
  echo "matches ${expected##*/}"
else
  echo "NOTE: ${expected##*/} has no entries yet; copy the list above into it once reviewed"
fi

echo "==> conversions"
out="$(mktemp -d)"
shopt -s nullglob nocaseglob
count=0
for sample in "${samples}"/*.{jpg,jpeg,png,gif,webp,heic}; do
  name="$(basename "${sample}")"
  vipsheader "${sample}"
  vips copy "${sample}" "${out}/${name}.jpg[Q=85,strip]" || fail "${name} -> JPEG"
  vips copy "${sample}" "${out}/${name}.png[strip]" || fail "${name} -> PNG"
  [[ -s "${out}/${name}.jpg" && -s "${out}/${name}.png" ]] || fail "${name} produced an empty output"
  count=$((count + 1))
done
[[ "${count}" -gt 0 ]] || fail "no samples in ${samples}"
echo "converted ${count} samples to JPEG and PNG"

echo "==> OK"
