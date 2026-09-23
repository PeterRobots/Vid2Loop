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
TYPE="keep"
LOG="fatal"
FORCE=false

# ARG INPUT
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)
      INPUT="$2"
      shift 2
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
    -c|--container)
      TYPE="$2"
      shift 2
      ;;
    --vmaf)
      VMAF="$2"
      shift 2
      ;;
    -v|--log-level)
      LOG="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=true
      shift 1
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
      echo "  -c, --container      Set output container type: avif, gif, mp4, webp (default: keep)"
      echo "  --vmaf      Set vmaf.json path if not present in /usr/bin (default: none)"
      echo "  -v, --log-level      set the log level: quiet, panic, fatal, error, warning, info, verbose, debug, trace  (default: fatal)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "input = $INPUT"

if [[ -z "$OUTPUT" ]]; then
  F_BASE=$(basename $INPUT)
  F_NAME="${F_BASE%.*}"
  F_CONTAINER="${F_BASE:e}"
  F_DIR="${INPUT:h}"
  OUTPUT="$F_DIR/${F_NAME}_CLIP.$F_CONTAINER"
fi

echo "output = $OUTPUT"


FPS=$(ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$INPUT")
FPS=$((FPS))
INTERP_FPS=$FPS
## LOG
LOG=(-hide_banner -y -loglevel "$LOG" -stats)
echo $LOG

## CLIP
CLIP=()
if [[ ! -z "$START" ]]; then
  CLIP+=(-ss $START)
  DURATION_BOOL=true
fi

if [[ ! -z "$END" ]]; then
  CLIP+=(-to $END)
  DURATION_BOOL=true
fi

## DURATION
if [[ -z "$DURATION" ]]; then
  if $DURATION_BOOL; then
    DURATION=$((END-START))
  else
    echo "Getting duration from ffprobe..."
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
  fi
else
  START=0
  END=$((START+DURATION))
  CLIP+=(-ss $START -to $END)
fi
# SETPTS
  # Variables
  # PTS = 1/($FPS*TB)
  # N: The sequential index number of the input frame (starting at 0).
  # TB: The timebase of the input stream.
  # PI: Mathematical constant π inside expression evaluations.
  # T: Presentation time of the frame in seconds
if [[ ! -z "$RATE" ]]; then
  INVERTED_RATE=$(( 1.0 / RATE ))
  if [[ ! -z $SS ]]; then
    PTS="(PTS-STARTPTS)"
  else
    PTS="PTS"
  fi
  case "$MODE" in
    sin) # Variable speed slowest in the middle
    SETPTS_RATE="(1.0 + ($INVERTED_RATE - 1.0) * sin(0.5*PI*T/$DURATION))"
    SETPTS="setpts='$PTS*$SETPTS_RATE'"
    ;;
    const)
    SETPTS_RATE="$INVERTED_RATE"
    SETPTS="setpts='$PTS*$SETPTS_RATE'"
    ;;
    cos) # Variable speed slowest at the start
    SETPTS_RATE="(1.0 + ($INVERTED_RATE - 1.0) * cos(0.5*PI*T/$DURATION))"
    SETPTS="setpts='$PTS*$SETPTS_RATE'"
    ;;
    none)
    SETPTS=""
    ;;
    *)
    echo "Unknown rate change mode: $MODE"
    exit 2
    ;;
  esac

  INTERP_FPS=$((INVERTED_RATE * FPS))
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
  arr=($SETPTS $MINTERPOLATE "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse")
else
  arr=($SETPTS $MINTERPOLATE)
fi

FILTER="${(j[,])arr:#}"
if [[ ! -z "$FILTER" ]]; then
  FILTER=(-filter:v $FILTER)
fi

# ENCODERS #
# libaom-av1 is reference
# libsvtav1 is open source netflix SVT-AV1
# librav1e is a rust open source implementation
# For Apple M1 CPU encode
# libsvtav1 > librav1e > libaom-av1

case "$TYPE" in
  "avif")
    ENCODE=(-c:v libsvtav1 -crf 20 -preset 4 -svtav1-params tune=0)
    LOOP=(-loop 0)
  ;;
  "gif")
    ENCODE=()
    LOOP=(-loop 0)
  ;;
  "webp")
    ENCODE=()
    LOOP=(-loop 0)
  ;;
  "mp4")
    ENCODE=(-c:v libx265 -tag:v hvc1 -crf 18 -preset medium)
    LOOP=()
  ;;
  "keep")
    ENCODE=(-c copy)
    LOOP=()
  ;;
  *)
  echo "Unknown output type: $TYPE"
  exit 4
  ;;
esac

if [[ ! -e $OUTPUT ]] || $FORCE; then
  FFMPEG_ARGS=(${LOG})
  FFMPEG_ARGS+=(${CLIP})
  FFMPEG_ARGS+=(-i "$INPUT")
  FFMPEG_ARGS+=(${FILTER})
  FFMPEG_ARGS+=(${ENCODE})
  FFMPEG_ARGS+=(${LOOP})
  FFMPEG_ARGS+=("$OUTPUT")

  echo "ffmpeg "$FFMPEG_ARGS

  ffmpeg $FFMPEG_ARGS | grep -v 'vmaf'
else
  echo "Output: $OUTPUT already exists and force = false"
fi
