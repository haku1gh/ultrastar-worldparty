

{* Libraries *}

{$IF Defined(IncludeConstants)}
  lua_lib_name = '';
  LUA_VERSION_INT     = 5002004;
  LUA_VERSION_RELEASE = '4';
  LUA_VERSION_MINOR   = '2';
  LUA_VERSION_MAJOR   = '5';
  LUA_VERSION         = '5.2.4';
{$IFEND}

{$MACRO ON}
{$IFNDEF FFMPEG_DIR}
  {$DEFINE FFMPEG_DIR := 'ffmpeg-9.0'}
{$ENDIF}
{$IF Defined(IncludeConstants)}
  FFMPEG_VERSION_INT = 9000002;

av__codec = 'libavcodec';
LIBAVCODEC_VERSION_MAJOR = 63;
LIBAVCODEC_VERSION_MINOR = 1;
LIBAVCODEC_VERSION_RELEASE = 100;

av__format = 'libavformat';
LIBAVFORMAT_VERSION_MAJOR = 63;
LIBAVFORMAT_VERSION_MINOR = 1;
LIBAVFORMAT_VERSION_RELEASE = 100;

av__util = 'libavutil';
LIBAVUTIL_VERSION_MAJOR = 61;
LIBAVUTIL_VERSION_MINOR = 1;
LIBAVUTIL_VERSION_RELEASE = 100;
{$IFEND}

{$IF Defined(IncludeConstants)}
  sw__scale = 'libswscale';
  LIBSWSCALE_VERSION_MAJOR   = 10;
  LIBSWSCALE_VERSION_MINOR   = 1;
  LIBSWSCALE_VERSION_RELEASE = 100;

  sw__resample = 'libswresample';
  LIBSWRESAMPLE_VERSION_MAJOR   = 7;
  LIBSWRESAMPLE_VERSION_MINOR   = 1;
  LIBSWRESAMPLE_VERSION_RELEASE = 100;
{$IFEND}

{$UNDEF HaveProjectM}
{$IF Defined(HaveProjectM) and Defined(IncludeConstants)}
  ProjectM_DataDir = '';
  PROJECTM_VERSION_MAJOR   = 0;
  PROJECTM_VERSION_MINOR   = 0;
  PROJECTM_VERSION_RELEASE = 0;
{$IFEND}

{$DEFINE HaveLibPcre}
{$IF Defined(HaveLibPcre) and Defined(IncludeConstants)}
  LIBPCRE_LIBNAME  = '';
  LIBPCRE_LIBDIR   = '/usr/local/Cellar/pcre/8.38/lib';
{$IFEND}
