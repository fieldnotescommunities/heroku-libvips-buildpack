#!/usr/bin/env bash
# check.sh <VIPS_VERSION> <SAMPLES_DIR> <EXPECTED_OPERATIONS_FILE>
#
# Run inside the stack's run image with the tarball installed (container/Dockerfile.test). Fails on the first
# thing a dyno would get wrong: a library the run image lacks, a loader or saver that should not be there (or
# one that should), a format we load that does not convert.

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

echo "==> shared libraries (nothing may be 'not found' in the run image)"
for file in "${prefix}/lib/libvips.so.42" "${prefix}/bin/vips" "${prefix}/bin/vipsheader" "${prefix}/bin/vipsthumbnail"; do
  ldd "${file}" | grep -q "not found" && { ldd "${file}"; fail "${file} has unresolved libraries"; }
done
ldd "${prefix}/lib/libvips.so.42" | sort

echo "==> loaders and savers"
operations="$(mktemp)"
vips -l | grep -E 'VipsForeign(Load|Save)' | sed -n 's/.*(\([a-z0-9_]*\)).*/\1/p' | sort -u > "${operations}"
cat "${operations}"

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
