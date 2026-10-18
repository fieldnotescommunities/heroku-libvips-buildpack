# Changelog

## Unreleased

- Build libheif too (1.23.6, HEVC decoding through the image's libde265, no encoders, no AVIF, no uncompressed
  codec, no plugins) and link libvips against it. libvips 8.18.6+ tags `heifload` untrusted when built against
  a libheif older than 1.23.2, which the heroku-26 image's 1.21.2 is, and the app blocks untrusted operations:
  every HEIC failed on a dyno. Tarballs and releases now carry both versions (`libvips-8.18.7-heif1.23.6`).
- The run-image check repeats the loading through ruby-vips under the app's blocking (`test/check.rb`), asserts
  libvips links our libheif, and that `heifload` carries no `untrusted` flag.
- First build: libvips 8.18.7 for heroku-26, loaders JPEG, PNG, GIF, WebP, HEIF; savers JPEG, PNG, WebP, HEIF.
