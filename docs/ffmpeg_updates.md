Update of UltraStar 21.02 from FFmpeg 4.x to FFmpeg 9.0
===============================================================================

A step-by-step approach will be done:
1. Modernize all FFmpeg API calls so that no deprecated calls are included
2. Upgrade to FFmpeg 5.1 Libraries
3. Fix encountered smaller issues
4. Upgrade to FFmpeg 7.1 Libraries
5. Upgrade to FFmpeg 9.x Libraries
6. Fix encountered smaller issues

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
  - Copied files from ffmpeg-4.0 over to ffmpeg-5.1
  - Add API definitions for channel layout
  - Removed deprecated parts
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
- DONE: Retrieve latest FFmpeg 7.x libraries and C-headers.
  - Downloaded windows build 7.1.15 from https://system233.github.io/ffmpeg-msvc-prebuilt/en/releases.html
  - Identify required and potential useful headers for UltraStar
- DONE: Create the new library folder ffmpeg-7.1
  - Copied files from ffmpeg-5.1 over to ffmpeg-7.1
  - Removed deprecated parts
  - Updated version fields
  - FFmpeg Records rebuild from the C structs
  - Reworked audio decoder's channel layout. Old functions are no longer
    available.
- DONE: Updated UVideo.pas where the debug_mv field became obsolete
- DONE: Updated UAudioDecoder_FFmpeg.pas; reworked audio decoder's channel
  layout. Old functions are no longer available.
- DONE: Updated config files (config-win.inc and configure-ac) to point to the
  new ffmpeg-7.1 folder
- DONE: Replaced FFmpeg DLLs in the game folder

Step 5: Upgrade to FFmpeg 9.0 Libraries
===============================================================================
- DONE: Retrieve latest FFmpeg 9.x libraries and C-headers.
  - Downloaded windows build 9.0.2 from https://system233.github.io/ffmpeg-msvc-prebuilt/en/releases.html
  - Identify required and potential useful headers for UltraStar
- DONE: Create the new library folder ffmpeg-9.0
  - Copied files from ffmpeg-7.1 over to ffmpeg-9.0
  - Updated version fields
  - FFmpeg Records rebuild from the C structs
- DONE: Pixelformat requires a new enum AlphaMode
- DONE: Updated config files (config-win.inc and configure-ac) to point to the
  new ffmpeg-9.1 folder
- DONE: Replaced FFmpeg DLLs in the game folder

Step 6: Fix encountered smaller issues
===============================================================================
- DONE: FFmpeg was just using 1 thread up to now. Changed the FFmpeg context
  setting to auto detect available CPU cores and use that value for number of
  threads.
- OPEN: Audio files with the FFmpeg decoder are probably not correctly released
  after the playback ended. Check for improvement.
- OPEN: Remove older FFmpeg libraries
- OPEN: Automatic thread detection is not correctly working on older hardware
  (e.g. 18year old PC). Either set a fixed thread amount, e.g. 4. Or find some
  other workaround.
- OPEN: Check for unused/obsolete defines. E.g. FF_API_DEBUG_MV could be one
  of it.
- OPEN: Check if all the API definitions are really needed and if not, maybe
  delete unused API's.
- OPEN: There are >= 30 warnings in the code. Check each warning and correct
  if possible.
