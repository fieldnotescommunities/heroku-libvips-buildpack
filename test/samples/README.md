# Samples

One small file per format the build loads, converted to JPEG and PNG by `test/check.sh`. They are the
webapp's libvips fixtures (`spec/fixtures/files/vips/`, made by `make_fixtures.rb` there): a JPEG with EXIF
orientation, a PNG with alpha, a two-frame GIF, a WebP, and an HEVC HEIC (which exercises the run image's
libde265 plugin).
