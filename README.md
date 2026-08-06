# FFMPEG video loop maker
Want to make short loops from videos with FOSS command line tools?
You've come to the right place!
# Installing
For now it's a `.zsh` file and you need `zsh`
- Easily installed with `brew` if on `linux`
- [Install on windows](https://github.com/zinox9/zsh-windows)
- Default on `MacOS`
```bash
wget https://github.com/PeterRobots/Vid2Loop/blob/main/vid2loop.zsh
sudo chmod +x vid2loop.zsh
```
# Running
Simply pass the file you want to turn into a loop into the script.
See `./vid2loop.zsh --help` for more information about commands
#### Defaults
- whole clip
- maintain pacing
- no interpolation
- mp4 output
```
./vid2loop.zsh -i /path/input_file.mp4 -o /path/output_file.mp4
```
### Capability
- Pick a start and stop time for a clip
- Speed up or slowdown clips
	- Constant ratio
	- First half of Sine wave peaking in the middle
	- First half of Cosine wave starting slow and speeding up at end
- Interpolate frames with blend frames or motion vector calculated frames
- Output as:
	- looped `.gif`
	- looped `.avif`
	- looped `.webp`
	- `.mp4` (most players enable looping)
For example a slow mo style clip with varying pacing and interpolation.
- `0.25` speed at the middle of the clip
- motion vector interpolation
- `.avif` output
# Exploration of settings
### Output types
- `.gif` is a classic
	- very large in file sizes
	- quality for size isn't amazing
	- widely compatible
- `.avif` a modern remake of the gif
	- much smaller file sizes
	- good quality through av1 encoding
	- compatibility is iffy
- `.webp` alternative browser compatible focused
	- smaller file sizes
	- decent quality
	- compatibility is very good with browsers
- `.mp4` basic widely compatible video file
	- much smaller file sizes
	 - good quality
	 - looping isn't baked in
	 - widely compatible
## SETPTS
https://ayosec.github.io/ffmpeg-filters-docs/8.0/Filters/Multimedia/setpts.html
Change the frame pacing of a video, higher is slower.
### Variables
`PTS = 1/($FPS*TB)`
`N`: The sequential index number of the input frame (starting at `0`).
`TB`: The timebase of the input stream.
`PI`: Mathematical constant π inside expression evaluations.
`T`: Presentation time of the frame in seconds
## minterpolate
https://ayosec.github.io/ffmpeg-filters-docs/8.0/Filters/Video/minterpolate.html
minterpolate makes new frames for desired framerate
### Variables
`mi_mode=mci:mc_mode=aobmc`: uses slow adv vector motion handling
`mi_mode=blend`: is fast and simple blending
`me_mode`: is the motion estimation, bilat is default, bidir is smoother
`vsbmc=1`: sets variable block sizes
As a comment, `minterpolate` is ok:
- blend is very fast and introduces ghosting artifacts
- mci is far clearer but introduces blocking artifacts

There are far better machine learned models these days, I recommend a look.
You can for example combine [my other script project](https://github.com/PeterRobots/Running-SPEED-video-interpolater) running the SPEED video interpolation model (2026).
- Run `vid2loop.sh` with no interpolation
	- You can still modify the frame pacing with setpts
- Use the output file from `vid2loop.sh` as the input into the SPEED model script.
### `.avif` ENCODERS
Encoding in `av1` and for `.avif` was an experience.
This review helped a lot: https://catskull.net/libaom-vs-svtav1-vs-rav1e-2025.html
- `libaom-av1` is reference
- `libsvtav1` is open source netflix SVT-AV1
- `librav1e` is a rust open source implementation
#####  For Apple M1 CPU encode
`libsvtav1 > librav1e > libaom-av1`
##### HW acceleration
You could use HW accelerated libraries like CUDA (nvidia) and videotoolbox (apple)
- I wanted to avoid platform dependencies so I didn't, but I do think they are decent.
# Option
 Can replace `ffmpeg` with a progress bar wrapper like `ffpb` from cargo or pip.
# VMAF ERRORS (IGNORE THEM)
If you like me run bazzite or some other immutable distro that includes ffmpeg but is missing things like vmaf, ignore the errors related to it.
- I tried to fix it by downloading the json `https://github.com/Netflix/vmaf/blob/master/model/vmaf_v0.6.1.json` from https://github.com/Netflix/vmaf
- I put it in userspace, I chose here: `/home/USERNAME/.local/share/ffmpeg/model`
- Add that path to `LD_LIBRARY_PATH` (in `.zshrc` if using `zsh`)
- Didn't work for me and wasn't needed in the end.
```
Bazzite ffmpeg doesn't have vmaf, so I had to download and put inside: .local/share/ffmpeg/model/vmaf_v0.6.1.json
I'm not entirely sure why this isn't simpler, but I have to input the starting file again after encoding.
Feed it into complex filter for vmaf.
if [[ ! -z $VMAF ]]; then
  SYSTEM_FLAGS=(-i "$INPUT" -filter_complex "[1:v][0:v]libvmaf=model='path=$VMAF'" -f null -)
fi
```
