Goal is to update UltraStar from FFmpeg 4.x to FFmpeg 9.0

A step-by-step approach will be done:
1. Modernize all FFmpeg API calls so that no deprecated calls are included
2. Upgrade to FFmpeg 5.1 Libraries
3. Fix encountered smaller issues
4. Upgrade to FFmpeg 7.1 Libraries
5. Upgrade to FFmpeg 9.x Libraries
6. Fix encountered smaller issues
6. Remove obsolete FFmpeg library definitions
7. Optional, removal of older FFmpeg libraries

Step 1: Modernize all FFmpeg API calls
===============================================================================
- DONE: Remove dead code for FFmpeg versions below 4.x
- DONE: Update API calls for Video and Image
  - Added API definitions for av_image_* calls
  - SynchronizeTime uses frame duration instead of codec time base
  - avpicture_* is replaced by av_image_*
  - Several other changes in the stream, packet and frames
- DONE: Update API calls for Audio
  - Modified the open and close channel_layouts
  - Made flush of buffers easier

Step 2: Upgrade to FFmpeg 5.1 Libraries
===============================================================================
- DONE: Retrieve latest FFmpeg 5.x libraries and C-headers.
  - Downloaded windows build 5.1.10 from https://system233.github.io/ffmpeg-msvc-prebuilt/en/releases.html
  - Identify required and potential useful headers for UltraStar
- DONE: Create the new library folder ffmpeg-5.1
  - Copy files from ffmpeg-4.0 over to ffmpeg-5.1
  - Add API definitions for channel layout
  - Remove deprecated parts
  - Updated version fields
  - Records TAVCodecContext, TAVPacket, TAVCodecParameters, TAVCodec, TAVStream,
    TAVFormatContext, TAVIOContext and TAVFrame rebuild from the C structs
- DONE: Updated UAudioDecoder_FFmpeg.pas where 2 changes became unnecessary
- DONE: Updated config files (config-win.inc and configure-ac) to point to the
    new ffmpeg-5.1 folder
- DONE: Replaced FFmpeg DLLs in the game folder

Step 3: Fix encountered smaller issues
===============================================================================
- DONE: Function avio_context_free in avio.pas had a wrong parameter
  declared. This was checked with the original header files and indeed a double
  pointer is required instead of a single pointer. This function hasn't been
  used so far.


Open Topics for later
===============================================================================
Things that came up while improving the FFmpeg libraries.

- OPEN: There are >= 30 warnings in the code. Check each warning and correct
  if possible.
- OPEN: There is a function called "CheckVersions" which compares the header
  and DLL version down to the release number. This prevents even small updates
  within the same major release. Which is unnecessary. A check of the major
  release is enough as everything below is ABI compatible. Furthermore a check
  for the swresample DLL is missing.
- OPEN: Check AVFormatCloseInput. Comment is maybe wrong. AVIOContext are not
  freeing avformat_close_input. There could be a small memory leak.
- OPEN: Handle TAVPacket differently in the future. This struct will need
  additional field in newer version. E.g. time_base is added in FFmpeg 5.
  Could lead to crashes.
- OPEN: The decoder is not emptied at the end of the video. It seens to not
  cause an issue, but there should be some frames lost. Check if this is ok.
- OPEN: fAudioBuffer is being created with GetAlignedMem but never release.
  Plus the pointer to DecodeFrame is rewired to frame.data[0]. This is a small
  memory leak.
