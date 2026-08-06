#!/usr/bin/env zsh
INPUT=""
OUTPUT=""
START=""
END=""
DURATION=""
SETPTS=""
VMAF=""
SYSTEM_FLAGS=""
RATE=1.0
MODE="none"
SETPTS_RATE=1.0
INTERP_FPS=1.0
INTERP="none"
DURATION_BOOL=false
TYPE="mp4"
# ARG INPUT
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)
      INPUT="$2"
      shift 2 # Past argument only (flag)
      ;;
    -o)
      OUTPUT="$2"
      shift 2
      ;;
    -ss|--start)
      START="$2"
      shift 2
      ;;
    -to|--end)
      END="$2"
      shift 2
      ;;
    -d|--duration)
      DURATION="$2"
      shift 2
      ;;
    -r|--rate)
      RATE="$2"
      shift 2
      ;;
    -m|--mode)
      MODE="$2"
      shift 2
      ;;
    --interp)
      INTERP="$2"
      shift 2
      ;;
    -t|--output-type)
      TYPE="$2"
      shift 2
      ;;
    --vmaf)
      VMAF="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "  -i   Set input"
      echo "  -o,  Set output"
      echo "  -ss, --start   Set start time (default: 0)"
      echo "  -to, --end          Set end time (default: none)"
      echo "  -d, --duration          Set end time (default: file length or end-start if set)"
      echo "  -r, --rate      Set framepacing rate (slowdown <1, speedup >1) (default: 1.0)"
      echo "  -m, --mode      Set framepacing mode: const, sin, cos, none (default: none)"
      echo "  --interp     Set interp method: mci, blend, none (default: none)"
      echo "  -t, --output-type      Set output type: avif, gif, mp4 (default: mp4)"
      echo "  --vmaf      Set vmaf.json path if not present in /usr/bin (default: none)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done
echo "input = $INPUT"
echo "output = $OUTPUT"


FPS=$(ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$INPUT")
FPS=$((FPS))
INTERP_FPS=$FPS
echo "fps = $FPS"

if [[ ! -z "$START" ]]; then
  SS="-ss $START"
  DURATION_BOOL=true
  echo $START
  # FFTRIM="trim=start=$START"
fi

if [[ ! -z "$END" ]]; then
  TO="-to $END"
  DURATION_BOOL=true
  echo $END
  # FFTRIM="$(FFTRIM):end=$END"
fi

if [[ -z "$DURATION" ]]; then
  if [[ $DURATION_BOOL ]]; then
    DURATION=$((END-START))
  else
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
  fi
fi

# SETPTS
  # Variables
  # PTS = 1/($FPS*TB)
  # N: The sequential index number of the input frame (starting at 0).
  # TB: The timebase of the input stream.
  # PI: Mathematical constant π inside expression evaluations.
  # T: Presentation time of the frame in seconds
if [[ ! -z "$RATE" ]]; then
  echo "Rate = $RATE"
  INVERTED_RATE=$((1.0 / RATE))
  # SETPTS_RATE="(N + $RATE * sin(N*2*PI/$FPS))"
  # Variable speed change peaking in the middle
  # SETPTS_RATE="(PTS-STARTPTS + $INVERTED_RATE * sin(PI*(T-$START)/$DURATION))"
  case "$MODE" in
    sin)
    SETPTS_RATE="(1.0 + ($INVERTED_RATE - 1.0) * sin(0.5*PI*T/$DURATION))"
    SETPTS="setpts='(PTS-STARTPTS)*$SETPTS_RATE'"
    ;;
    const)
    SETPTS_RATE="$INVERTED_RATE"
    SETPTS="setpts='(PTS-STARTPTS)*$SETPTS_RATE'"
    ;;
    cos)
    SETPTS_RATE="(1.0 + ($INVERTED_RATE - 1.0) * cos(0.5*PI*T/$DURATION))"
    SETPTS="setpts='(PTS-STARTPTS)*$SETPTS_RATE'"
    ;;
    none)
    SETPTS=""
    ;;
    *)
    echo "Unknown rate change mode: $MODE"
    exit 2
    ;;
  esac
  echo $SETPTS_RATE
  # INTERP_FPS="(1/((N + $RATE * sin(N*2*PI/$FPS)) * TB))"
  INTERP_FPS=$((INVERTED_RATE * FPS))
  echo $INTERP_FPS
fi

# MINTERPOLATE
# https://ayosec.github.io/ffmpeg-filters-docs/8.0/Filters/Video/minterpolate.html
# minterpolate makes new frames for desired framerate
# mi_mode=mci:mc_mode=aobmc uses slow adv vector motion handling
# mi_mode=blend is fast and simple blending
# me_mode is the motion estimation, bilat is default, bidir is smoother
# vsbmc=1 sets variable block sizes
case "$INTERP" in
  "mci")
  MINTERPOLATE="minterpolate=fps=$FPS:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
  ;;
  "blend")
  MINTERPOLATE="minterpolate=fps=$FPS:mi_mode=blend"
  ;;
  "none")
  MINTERPOLATE=""
  ;;
  *)
  echo "Unknown interpolation type: $INTERP"
  exit 3
  ;;
esac

# FILTER
if [[ $TYPE == "gif" ]]; then
  arr=("$SETPTS" "$MINTERPOLATE" "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse")
elif [[ $TYPE == "mp4" ]]; then
  arr=("$SETPTS" "$MINTERPOLATE")
else
  arr=("$SETPTS" "$MINTERPOLATE")
fi

echo "SETPTS= $SETPTS"
echo "MINTERPOLATE= $MINTERPOLATE"
echo "arr= $arr"
# for s in "${arr[@]}"; do
#   [[ -n "$s" ]] && filtered+=($S)
# done
FILTER=$(IFS=","; echo ""${arr:#}"")
if [[ ! -z "$FILTER" ]]; then
  FILTER=(-filter:v $FILTER)
fi
echo "FILTERS= $FILTER"
# SYSTEM FLAGS

# case "$OSTYPE" in
#   solaris*)
#   echo "Solaris"
#   SYSTEM_FLAGS=""
#   ;;
#   darwin*)
#   echo "macOS"
#   SYSTEM_FLAGS=""
#   ;;
#   linux*)
#   echo "Linux"
#   SYSTEM_FLAGS="libvmaf=model='$VMAF'"
#   ;;
#   bsd*)
#   echo "BSD"
#   SYSTEM_FLAGS=""
#   ;;
#   msys*)
#   echo "Windows (Git Bash)"
#   SYSTEM_FLAGS=""
#   ;;
#   cygwin*)
#   echo "Windows (Cygwin)"
#   SYSTEM_FLAGS=""
#   ;;
#   *)
#   echo "Unknown: $OSTYPE"
#   ;;
# esac

# VMAF - IGNORE #
# Bazzite ffmpeg doesn't have vmaf, so I had to download and put inside: .local/share/ffmpeg/model/vmaf_v0.6.1.json
# I'm not entirely sure why this isn't simpler, but I have to input the starting file again after encoding.
# Feed it into complex filter for vmaf.
# if [[ ! -z $VMAF ]]; then
#   SYSTEM_FLAGS=(-i "$INPUT" -filter_complex "[1:v][0:v]libvmaf=model='path=$VMAF'" -f null -)
# fi

# ENCODERS #
# libaom-av1 is reference
# libsvtav1 is open source netflix SVT-AV1
# librav1e is a rust open source implementation
# For Apple M1 CPU encode
# libsvtav1 > librav1e > libaom-av1

case "$TYPE" in
  "avif")
  ffmpeg $=SS $=TO -i "$INPUT" \
    $FILTER \
    -c:v libsvtav1 -crf 20 -preset 4 -svtav1-params tune=0 \
    -pix_fmt yuv420p10le \
    -loop 0 \
    "$OUTPUT"
  ;;
  "gif")
  ffmpeg $=SS $=TO -i "$INPUT" \
    $FILTER \
    -loop 0 \
    "$OUTPUT"
  ;;
  "webp")
  ffmpeg $=SS $=TO -i "$INPUT" \
    $FILTER \
    -loop 0 \
    "$OUTPUT"
  ;;
  "mp4")
  ffmpeg $=SS $=TO -i "$INPUT" \
    $FILTER \
    -c:v libx265 -tag:v hvc1 -crf 20 -preset medium $SYSTEM_FLAGS \
    -pix_fmt yuv420p10le \
    "$OUTPUT"
  ;;
  *)
  echo "Unknown output type: $TYPE"
  exit 4
  ;;
esac
