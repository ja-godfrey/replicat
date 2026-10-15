#!/bin/zsh
# render.sh - regenerate the README GIFs: demo/remind.gif and demo/email.gif.
# Needs Xcode Command Line Tools (swift) and ffmpeg (brew install ffmpeg).
set -euo pipefail
cd "${0:a:h}/.."
scenes=(remind email); (( $# )) && scenes=($@)
for s in $scenes; do
  tmp=demo/frames/$s
  rm -rf $tmp
  swift demo/render.swift $s $tmp
  ffmpeg -hide_banner -loglevel error -y -framerate 15 -i "$tmp/frame-%04d.png" \
    -filter_complex "scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    demo/$s.gif
  rm -rf $tmp
  print "demo/$s.gif  $(du -h demo/$s.gif | cut -f1)"
done
rmdir demo/frames 2>/dev/null || true
