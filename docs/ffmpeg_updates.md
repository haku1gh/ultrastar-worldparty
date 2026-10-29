Goal is to update UltraStar from FFmpeg 4.x to FFmpeg 9.0

A step-by-step approach will be done:
1. Modernize all FFmpeg API calls so that no deprecated calls are included
2. Replace FFmpeg 4.x libraries with FFmpeg 5.x Libraries
3. Remove obsolete FFmpeg library definitions
4. Modernize all FFmpeg API calls so that no deprecated calls are included
5. Replace FFmpeg 5.x libraries with FFmpeg 7.x Libraries
6. Remove obsolete FFmpeg library definitions
7. Modernize all FFmpeg API calls so that no deprecated calls are included
8. Replace FFmpeg 7.x libraries with FFmpeg 9.x Libraries
9. Remove obsolete FFmpeg library definitions

Step 1:
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

Step 2:
===============================================================================
- OPEN: Retrieve latest FFmpeg 5.x libraries and C-headers.

Open Topics for later
===============================================================================
Things that came up while improving the FFmpeg libs.

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
- OPEN: Function avio_context_free in avio.pas has probably a wrong parameter
  declared. Check with the original header files. It could be that a double
  pointer is required and not just a single pointer.
- OPEN: fAudioBuffer is being created with GetAlignedMem but never release.
  Plus the pointer to DecodeFrame is rewired to frame.data[0]. This is a small
  memory leak.
