#!/usr/bin/env bash
# Saves two session frames as screenshots 03 and 04, then cuts the itch.io trailer (itch/trailer.mp4, 1920x1080, 30 fps, under 30 s) from a session
# recorded by tools/itch_capture.gd under Movie Maker: three live clips (the title's goose shot,
# dawn in the mist, sunset in the rain) with the game's own sound, then the results screenshot
# and an end card over the Endless music loop, joined by 0.3 s cross-fades.
# Usage (repo root): tools/itch_trailer.sh <session movie> [output]
# Needs ffmpeg (libx264, aac) and ImageMagick (magick). Frame ranges are the session's frames
# (Movie Maker records one per game frame at --fixed-fps 30).
set -euo pipefail
cd "$(dirname "$0")/.."

SESSION="${1:?usage: tools/itch_trailer.sh <session movie> [output]}"
OUT="${2:-itch/trailer.mp4}"
SHOTS=itch/screenshots
MUSIC=huntfrenzy/audio/music/endless.mp3
HEADING_FONT=huntfrenzy/ui/fonts/LilitaOne-Regular.ttf
BODY_FONT=huntfrenzy/ui/fonts/Nunito-wght.ttf
WORK=build/itch
mkdir -p "$WORK"

# Session frames saved as page screenshots: the golden goose's x4 kill and a sunset hit's feathers.
GOLDEN_FRAME=581
FEATHERS_FRAME=600
# Live clips: first and last frame (inclusive) of each.
TITLE_CLIP=(30 159)
DAWN_CLIP=(215 349)
SUNSET_CLIP=(400 654)
FPS=30
RESULTS_TIME=2.5
END_TIME=3.0
FADE=0.3

for shot in "03_golden_combo:$GOLDEN_FRAME" "04_sunset_feathers:$FEATHERS_FRAME"; do
  ffmpeg -v error -y -i "$SESSION" -vf "select=eq(n\,${shot#*:})" -frames:v 1 "$SHOTS/${shot%%:*}.png"
done

# The end card: the title screen blurred and darkened under the name and the call to play
# (palette cream and gold, ink outline).
magick "$SHOTS/01_title.png" -blur 0x40 -fill '#1f1a2e' -colorize 65% \
  -gravity center -font "$HEADING_FONT" -pointsize 190 -stroke '#1f1a2e' -strokewidth 14 -fill '#fbedcd' \
  -annotate +0-150 'Hunt Frenzy' -stroke none -annotate +0-150 'Hunt Frenzy' \
  -font "$HEADING_FONT" -pointsize 84 -fill '#f2b630' -annotate +0+40 'Play free in your browser' \
  -font "$BODY_FONT" -pointsize 52 -fill '#fbedcd' -annotate +0+160 'Campaign  ·  Endless  ·  Time Attack' \
  "$WORK/end_card.png"

seconds() { echo "scale=4; $1 / $FPS" | bc; }
TITLE_LEN=$(seconds $((TITLE_CLIP[1] - TITLE_CLIP[0] + 1)))
DAWN_LEN=$(seconds $((DAWN_CLIP[1] - DAWN_CLIP[0] + 1)))
SUNSET_LEN=$(seconds $((SUNSET_CLIP[1] - SUNSET_CLIP[0] + 1)))
# Each cross-fade starts FADE before the end of everything joined so far.
O1=$(echo "$TITLE_LEN - $FADE" | bc)
O2=$(echo "$O1 + $DAWN_LEN - $FADE" | bc)
O3=$(echo "$O2 + $SUNSET_LEN - $FADE" | bc)
O4=$(echo "$O3 + $RESULTS_TIME - $FADE" | bc)
CLIPS_LEN=$(echo "$O3 + $FADE" | bc)
TOTAL=$(echo "$O4 + $END_TIME" | bc)
MUSIC_LEN=$(echo "$TOTAL - $CLIPS_LEN + $FADE" | bc)
MUSIC_FADE_OUT=$(echo "$MUSIC_LEN - 1.2" | bc)

clip() { # <label> <first> <last>
  echo "[0:v]trim=start_frame=$2:end_frame=$(($3 + 1)),setpts=PTS-STARTPTS,fps=$FPS,settb=1/$FPS,format=yuv420p[v$1];" \
    "[0:a]atrim=start=$(seconds "$2"):end=$(seconds $(($3 + 1))),asetpts=PTS-STARTPTS[a$1];"
}

FILTER="$(clip t "${TITLE_CLIP[@]}") $(clip d "${DAWN_CLIP[@]}") $(clip s "${SUNSET_CLIP[@]}")
[1:v]scale=3840:-1,zoompan=z='1+0.04*on/($RESULTS_TIME*$FPS)':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=$(echo "$RESULTS_TIME * $FPS" | bc | cut -d. -f1):s=1920x1080:fps=$FPS,settb=1/$FPS,format=yuv420p[vr];
[2:v]fps=$FPS,settb=1/$FPS,format=yuv420p[ve];
[vt][vd]xfade=transition=fade:duration=$FADE:offset=$O1[x1];
[x1][vs]xfade=transition=fade:duration=$FADE:offset=$O2[x2];
[x2][vr]xfade=transition=fade:duration=$FADE:offset=$O3[x3];
[x3][ve]xfade=transition=fade:duration=$FADE:offset=$O4,format=yuv420p[v];
[at][ad]acrossfade=d=$FADE[y1];
[y1][as]acrossfade=d=$FADE[y2];
[3:a]atrim=0:$MUSIC_LEN,asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,afade=t=in:d=0.4,afade=t=out:st=$MUSIC_FADE_OUT:d=1.2[am];
[y2]aformat=sample_rates=48000:channel_layouts=stereo[yc];
[yc][am]acrossfade=d=$FADE[a]"

ffmpeg -v error -y -i "$SESSION" \
  -loop 1 -t "$RESULTS_TIME" -i "$SHOTS/06_results.png" \
  -loop 1 -t "$END_TIME" -i "$WORK/end_card.png" \
  -i "$MUSIC" \
  -filter_complex "$FILTER" -map '[v]' -map '[a]' \
  -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p -r $FPS -c:a aac -b:a 160k -movflags +faststart \
  -t "$TOTAL" "$OUT"
echo "itch_trailer: OK $OUT ($TOTAL s, $(stat -f %z "$OUT" 2>/dev/null || stat -c %s "$OUT") bytes)"
