# frozen_string_literal: true

# check.rb <VIPS_VERSION> <LIBHEIF_VERSION> <SAMPLES_DIR>
#
# Run inside the stack's run image with the tarball installed and ruby-vips (container/Dockerfile.test): what the
# app's process does with this build. ruby-vips must load this libvips and this libheif rather than the stack
# packages', and every sample must load and thumbnail under the blocking the app applies before any operation:
# every loader blocked except ours, every saver except ours, and libvips's own "untrusted" operations (which is
# how libvips 8.18.6+ built against an old libheif made every HEIC fail on a dyno while `vips copy` worked).
#
# The blocking mirrors VipsRunner.configure! in the fieldnotes webapp (lib/vips_runner.rb); keep them the same.

require "ffi"
require "tmpdir"
require "vips"

vips_version, libheif_version, samples = ARGV
abort "usage: check.rb VIPS_VERSION LIBHEIF_VERSION SAMPLES_DIR" unless samples

def fail(message)
  abort "CHECK FAILED: #{message}"
end

module Heif
  extend FFI::Library
  ffi_lib "heif"
  attach_function :heif_get_version, [], :string
end

puts "==> versions seen by ruby-vips"
puts "libvips #{Vips.version_string}, libheif #{Heif.heif_get_version}"
fail "ruby-vips loaded libvips #{Vips.version_string}, expected #{vips_version}" unless Vips.version_string == vips_version
fail "libheif is #{Heif.heif_get_version}, expected #{libheif_version}" unless Heif.heif_get_version == libheif_version

puts "==> the app's blocking"
LOADERS = %w[VipsForeignLoadJpeg VipsForeignLoadPng VipsForeignLoadNsgif VipsForeignLoadWebp VipsForeignLoadHeif].freeze
SAVERS = %w[VipsForeignSaveJpeg VipsForeignSavePng VipsForeignSaveSpng].freeze
Vips.block("VipsForeignLoad", true)
LOADERS.each { |name| Vips.block(name, false) }
Vips.block("VipsForeignSave", true)
SAVERS.each { |name| Vips.block(name, false) }
Vips.block_untrusted(true)

puts "==> every sample loads and thumbnails under it"
out = Dir.mktmpdir("check")
files = Dir.glob(File.join(samples, "*.{jpg,jpeg,png,gif,webp,heic}"), File::FNM_CASEFOLD).sort
fail "no samples in #{samples}" if files.empty?
files.each do |path|
  image = Vips::Image.new_from_file(path)
  loader = image.get("vips-loader")
  # one pipeline per output, as the app does: a thumbnail reads its source in one sequential pass, so writing the same
  # one twice fails on PNG ("out of order read")
  jpeg = Vips::Image.thumbnail(path, 32)
  jpeg.write_to_file(File.join(out, "#{File.basename(path)}.jpg"), Q: 85, keep: :none, background: [255, 255, 255])
  Vips::Image.thumbnail(path, 32).write_to_file(File.join(out, "#{File.basename(path)}.png"), keep: :none)
  puts "#{File.basename(path)}: #{image.width}x#{image.height} via #{loader}, thumbnail #{jpeg.width}x#{jpeg.height}"
  # libheif probes a tiny HEIC with seeks past its end, which libvips notes in its error buffer without failing; clear
  # them so a later failure's message is its own
  Vips.vips_error_clear
rescue Vips::Error => e
  fail "#{File.basename(path)} under the app's blocking: #{e.message.strip}"
end
fail "no HEIC sample was exercised" unless files.any? { |path| path.downcase.end_with?(".heic") }

puts "==> OK"
