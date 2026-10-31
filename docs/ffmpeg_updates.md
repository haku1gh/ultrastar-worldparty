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
- DONE: Added the swresample DLL in the file check.
- DONE: Changed the function "CheckVersions" to check on only the major release
  version. A check of the major release is enough as everything below is ABI
  compatible.
- DONE: Fixed small memory leak in AVFormatCloseInput. AVIOContext was not
  freed.
- DONE: Remove creation of own TAVPackets.
- DONE: The decoder is now emptied at the end of the video.
- DONE: fAudioBuffer is being created with GetAlignedMem but never released.
  Now its not even allocating a buffer and is using the frame data directly.
  For silence a new buffer, fSilenceBuffer, is created.
- DONE: Fixed bug that the game would freeze at the end of certain songs (can
  be reproduced with AVI files and MPEG video streams).

Step 4: Upgrade to FFmpeg 7.1 Libraries
===============================================================================
- OPEN: Retrieve latest FFmpeg 7.x libraries and C-headers.

Open Topics for later
===============================================================================
Things that came up while improving the FFmpeg libraries.

- OPEN: There are >= 30 warnings in the code. Check each warning and correct
  if possible.
- OPEN: When BASS is deactivated and therefore FFmpeg for audio is used, then
  songs will not end. The remaining time counter will just continue with
  negative numbers. This issue might not be related to the FFmpeg updates! As
  a workaround: just press ESC at the end of the song.
