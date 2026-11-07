{*
    UltraStar WorldParty - Karaoke Game

	UltraStar WorldParty is the legal property of its developers,
	whose names	are too numerous to list here. Please refer to the
	COPYRIGHT file distributed with this source distribution.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. Check "LICENSE" file. If not, see
	<http://www.gnu.org/licenses/>.
 *}
unit UVideo;

{*
 * based on 'An ffmpeg and SDL Tutorial' (http://www.dranger.com/ffmpeg/)
 *}

// uncomment if you want to see the debug stuff
{.$define DebugDisplay}
{.$define DebugFrames}
{.$define VideoBenchmark}
{.$define Info}

// uncomment to draw with the old immediate mode code (glBegin/glEnd) instead
// of the vertex buffer path. Useful for A/B performance comparisons.
{.$define VideoLegacyDraw}

// uncomment to draw from the vertex buffer with the fixed function pipeline
// instead of the shader. Useful for A/B performance comparisons.
{.$define VideoNoShader}

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

implementation

uses
  SysUtils,
  Math,
  ctypes,
  sdl2,
  avcodec,
  avformat,
  avutil,
  avio,
  rational,
  swscale,
  dglOpenGL,
  StrUtils,
  UMediaCore_FFmpeg,
  UCommon,
  UConfig,
  ULog,
  UMusic,
  UGraphicClasses,
  UGraphic,
  UPath;

{$IF DEFINED(cpuarm) or DEFINED(cpuaarch64)}
  // swscale has asm routines for RGBA on ARM, but none for RGB/BGR
  {$DEFINE PIXEL_FMT_32BITS}
{$IFEND}

const
{$IFDEF PIXEL_FMT_32BITS}
  PIXEL_FMT_OPENGL = GL_RGBA;
  PIXEL_FMT_FFMPEG = AV_PIX_FMT_RGBA;
  PIXEL_FMT_SIZE   = 4;
{$ELSE}
  PIXEL_FMT_OPENGL = GL_RGB;
  PIXEL_FMT_FFMPEG = AV_PIX_FMT_RGB24;
  PIXEL_FMT_SIZE   = 3;
{$ENDIF}

  BUFFER_ALIGN = 32;
  ReflectionH = 0.5; //reflection height (50%)

  // vertex buffer: interleaved x, y, z, r, g, b, a, u, v
  VERTEX_BYTES = 9 * SizeOf(GLfloat);
  VBO_SIZE = 4096 * VERTEX_BYTES;
  // video quad + up to 4 border quads
  MAX_VERTICES = 5 * 4;

type
  TVideoVertex = packed record
    X, Y, Z: GLfloat;
    R, G, B, A: GLfloat;
    U, V: GLfloat;
  end;

type
  IVideo_FFmpeg = interface (IVideo)
  ['{E640E130-C8C0-4399-AF02-67A3569313AB}']
    function Open(const FileName: IPath): boolean;
  end;

  TVideo_FFmpeg = class( TInterfacedObject, IVideo_FFmpeg )
  private
    fOpened: boolean;     //**< stream successfully opened
    fPaused: boolean;     //**< stream paused
    fEOF: boolean;        //**< end-of-file state
    fDraining: boolean;   //**< end of file reached, decoder is flushed and delivers its remaining frames

    fLoop: boolean;       //**< looping enabled

    fStream:        PAVStream;
    fStreamIndex :  integer;
    fFormatContext: PAVFormatContext;
    fCodecContext:  PAVCodecContext;
    fCodec:         PAVCodec;

    fAVFrame:     PAVFrame;
    fAVFrameRGB:  PAVFrame;

    fFrameBuffer: Pcuint8;  //**< stores a FFmpeg video frame
    fFrameTex:    GLuint; //**< OpenGL texture for FrameBuffer
    fFrameTexValid: boolean; //**< if true, fFrameTex contains the current frame
    fTexWidth, fTexHeight: cardinal;
    fScaledWidth, fScaledHeight: cardinal; //**< size of the converted frame (<= texture size)

    fSwScaleContext: PSwsContext;

    fScreen:          integer; //actual screen to draw on

    fPosX:    double;
    fPosY:    double;
    fPosZ:    double;
    fWidth:   double;
    fHeight:  double;

    fFrameRange:        TRectCoords;

    fAlpha:             double;
    fReflectionSpacing: double;


    fAspect: real;        //**< width/height ratio
    fAspectCorrection: TAspectCorrection;

    fFrameDuration: extended; //**< duration of a video frame in seconds (= 1/fps)
    fFrameTime: extended; //**< video time position (absolute)
    fNextFrameTime: extended; //**< video time position of the next frame (absolute)
    fLoopTime: extended;  //**< start time of the current loop
    fPreferDTS: boolean;

    // vertex buffer drawing
    fUseVBO:    boolean;
    fVBO:       GLuint;
    fVBOCursor: integer; //**< write position in the vertex buffer (bytes)
    fVBOBase:   integer; //**< offset of the vertices that were uploaded last (bytes)
    fVerts:     array[0..MAX_VERTICES-1] of TVideoVertex;
    fVertCount: integer;

    // shader used for drawing from the vertex buffer
    fUseShader: boolean;
    fProg:      GLuint;
    fLocUseTex: GLint;

    procedure Reset();
    function DecodeFrame(): boolean;
    procedure SynchronizeTime(Frame: PAVFrame; pts: double);

    procedure GetVideoRect(var ScreenRect, TexRect: TRectCoords);
    procedure DrawBorders(ScreenRect: TRectCoords);
    procedure DrawBordersReflected(ScreenRect: TRectCoords; AlphaUpper, AlphaLower: double);

    procedure InitVertexBuffer();
    procedure InitShader();
    procedure AddVertex(aX, aY, aZ, aR, aG, aB, aA, aU, aV: single);
    procedure AddBorderQuad(Left, Right, Upper, Lower, AlphaUpper, AlphaLower: single);
    procedure AddBorders(ScreenRect: TRectCoords);
    procedure AddBordersReflected(ScreenRect: TRectCoords; AlphaUpper, AlphaLower: double);
    procedure UploadVertices();
    procedure DrawVertices(First, Count: integer; Textured: boolean);
    procedure EndVertexDraw();

    procedure ShowDebugInfo();

  public
    constructor Create;
    destructor Destroy; override;

    function Open(const FileName: IPath): boolean;
    procedure Close;

    procedure Play;
    procedure Pause;
    procedure Stop;

    procedure SetLoop(Enable: boolean);
    function GetLoop(): boolean;

    procedure SetPosition(Time: real);
    function GetPosition: real;

    procedure SetScreen(Screen: integer);
    function GetScreen(): integer;

    procedure SetScreenPosition(X, Y, Z: double);
    procedure GetScreenPosition(var X, Y, Z: double);

    procedure SetWidth(Width: double);
    function GetWidth(): double;

    procedure SetHeight(Height: double);
    function GetHeight(): double;

    {**
     * Sub-image of the video frame to draw.
     * This can be used for zooming or similar purposes.
     *}
     procedure SetFrameRange(Range: TRectCoords);
     function GetFrameRange(): TRectCoords;

     function GetFrameAspect(): real;

     procedure SetAspectCorrection(AspectCorrection: TAspectCorrection);
     function GetAspectCorrection(): TAspectCorrection;

     procedure SetAlpha(Alpha: double);
     function GetAlpha(): double;

     procedure SetReflectionSpacing(Spacing: double);
     function GetReflectionSpacing(): double;

     procedure GetFrame(Time: Extended);
     procedure Draw();
     procedure DrawReflection();
  end;

  TVideoPlayback_FFmpeg = class( TInterfacedObject, IVideoPlayback )
  private
    fInitialized: boolean;

  public
    function GetName: String;

    function Init(): boolean;
    function Finalize: boolean;

    function Open(const FileName : IPath): IVideo;
  end;

var
  FFmpegCore: TMediaCore_FFmpeg;
  SupportsNPOT: Boolean;


{*------------------------------------------------------------------------------
 * TVideoPlayback_ffmpeg
 *------------------------------------------------------------------------------}

function  TVideoPlayback_FFmpeg.GetName: String;
begin
  result := 'FFmpeg_Video';
end;

function TVideoPlayback_FFmpeg.Init(): boolean;
begin
  Result := true;

  if (fInitialized) then
    Exit;
  fInitialized := true;

  FFmpegCore := TMediaCore_FFmpeg.GetInstance();
end;

function TVideoPlayback_FFmpeg.Finalize(): boolean;
begin
  Result := true;
end;

function TVideoPlayback_FFmpeg.Open(const FileName : IPath): IVideo;
var
  Video: IVideo_FFmpeg;
begin
  Video := TVideo_FFmpeg.Create;
  if Video.Open(FileName) then
    Result := Video
  else
    Result := nil;
end;


{* TVideo_FFmpeg *}

constructor TVideo_FFmpeg.Create;
begin
  glGenTextures(1, PGLuint(@fFrameTex));
  SupportsNPOT := (AnsiContainsStr(glGetString(GL_EXTENSIONS),'texture_non_power_of_two')) and not (AnsiContainsStr(glGetString(GL_EXTENSIONS), 'Radeon X16'));

  InitVertexBuffer();
  InitShader();
  Reset();
end;

destructor TVideo_FFmpeg.Destroy;
begin
  Close();
  glDeleteTextures(1, PGLuint(@fFrameTex));
  if (fProg <> 0) then
    glDeleteProgram(fProg);
  if (fVBO <> 0) then
    glDeleteBuffers(1, @fVBO);
end;

function TVideo_FFmpeg.Open(const FileName : IPath): boolean;
var
  errnum: Integer;
  AudioStreamIndex: integer;
  r_frame_rate: cdouble;
  MaxTexSize: GLint;

  // halves the larger dimension of the texture (and of the converted frame)
  function ReduceSize: boolean;
  var
    tex, scale: ^cardinal;
  begin
    Result := false;
    if fTexWidth >= fAspect * fTexHeight then
    begin
      tex := @fTexWidth;
      scale := @fScaledWidth;
    end
    else
    begin
      tex := @fTexHeight;
      scale := @fScaledHeight;
    end;
    if tex^ > 64 then
    begin
      tex^ := 1 shl BsrDWord(tex^ - 1);
      scale^ := tex^;
      Result := true;
    end;
  end;

begin
  Result := false;
  Reset();

  // use custom 'ufile' protocol for UTF-8 support
  errnum := FFmpegCore.AVFormatOpenInput(@fFormatContext, PAnsiChar(UTF8ToAnsi(FileName.ToUTF8)));//'ufile:'+FileName.ToUTF8));
  if (errnum <> 0) then
  begin
    Log.LogError('Failed to open file "'+ FileName.ToNative +'" ('+FFmpegCore.GetErrorString(errnum)+'::'+IntToStr(errnum)+')');
    Exit;
  end;

  // update video info
  errnum := avformat_find_stream_info(fFormatContext, nil);
  if (errnum < 0) then
  begin
    Log.LogError('No stream info found', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;
  Log.LogInfo('VideoStreamIndex : ' + inttostr(fStreamIndex), 'TVideoPlayback_ffmpeg.Open');

  // find video stream
  FFmpegCore.FindStreamIDs(fFormatContext, fStreamIndex, AudioStreamIndex);
  if (fStreamIndex < 0) then
  begin
    Log.LogError('No video stream found', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  fStream := PPAVStream(PtrUInt(fFormatContext^.streams) + fStreamIndex * Sizeof(pointer))^;
  fPreferDTS := false;
  // workaround for FFmpeg bug #6560
  if (LeftStr(fFormatContext^.iformat^.name, 4) = 'mov,') or (fFormatContext^.iformat^.name = 'mov') then
    fPreferDTS := true;

  // AVStream.codec was removed in FFmpeg 5.0. Instead we create (and own) a
  // codec context and initialize it with the stream's codec parameters.
  fCodec := avcodec_find_decoder(fStream^.codecpar^.codec_id);
  if (fCodec = nil) then
  begin
    Log.LogError('No matching codec found', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  fCodecContext := avcodec_alloc_context3(fCodec);
  if (fCodecContext = nil) then
  begin
    Log.LogError('Failed to allocate codec context', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  errnum := avcodec_parameters_to_context(fCodecContext, fStream^.codecpar);
  if (errnum < 0) then
  begin
    Log.LogError('Failed to copy codec parameters: ' + FFmpegCore.GetErrorString(errnum), 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  // set debug options
  fCodecContext^.debug := 0;

  // enable automatic thread detection
  fCodecContext^.thread_count := 0;

  // detect bug-workarounds automatically
  fCodecContext^.workaround_bugs := FF_BUG_AUTODETECT;
  // error resilience strategy (careful/compliant/agressive/very_aggressive)
  //fCodecContext^.error_resilience := FF_ER_CAREFUL; //FF_ER_COMPLIANT;
  // allow non spec compliant speedup tricks.

  //fCodecContext^.flags2 := CODEC_FLAG2_FAST;

  // Note: avcodec_open() and avcodec_close() are not thread-safe and will
  // fail if called concurrently by different threads.
  FFmpegCore.LockAVCodec();
  try
    errnum := avcodec_open2(fCodecContext, fCodec, nil);
  finally
    FFmpegCore.UnlockAVCodec();
  end;
  if (errnum < 0) then
  begin
    Log.LogError('No matching codec found', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  {$ifdef DebugDisplay}
  DebugWriteln('Found a matching Codec: '+ fCodecContext^.Codec.Name + sLineBreak +
    sLineBreak +
    '  Width = '+inttostr(fCodecContext^.width) +
    ', Height='+inttostr(fCodecContext^.height) + sLineBreak +
    '  Aspect    : '+inttostr(fCodecContext^.sample_aspect_ratio.num) + '/' +
                     inttostr(fCodecContext^.sample_aspect_ratio.den) + sLineBreak +
    '  Framerate : '+inttostr(fStream^.r_frame_rate.num) + '/' +
                     inttostr(fStream^.r_frame_rate.den));
  {$endif}

  // allocate space for decoded frame and rgb frame
  fAVFrame := av_frame_alloc();
  fAVFrameRGB := av_frame_alloc();

  if ((fAVFrame = nil) or (fAVFrameRGB = nil)) then
  begin
    Log.LogError('Failed to allocate buffers', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  // calculate some information for video display
  fAspect := av_q2d(fCodecContext^.sample_aspect_ratio);
  if (fAspect = 0) then
    fAspect := fCodecContext^.width /
               fCodecContext^.height
  else
    fAspect := fAspect * fCodecContext^.width /
                         fCodecContext^.height;

  r_frame_rate := av_q2d(fStream^.r_frame_rate);

  fFrameDuration := 1/r_frame_rate;

  // hack to get reasonable framerate (for divx and others)
  if (fFrameDuration < 0.02) then // 0.02 <-> 50 fps
  begin
    fFrameDuration := r_frame_rate;
    while (fFrameDuration > 50) do
      fFrameDuration := fFrameDuration/10;
    fFrameDuration := 1/fFrameDuration;
  end;

  Log.LogInfo('Framerate: '+inttostr(floor(1/fFrameDuration))+'fps', 'TVideoPlayback_ffmpeg.Open');

  // size of the texture and of the converted frame. Videos that are larger than
  // the maximum texture size are scaled down by swscale (see ReduceSize).
  fTexWidth     := fCodecContext^.width;
  fTexHeight    := fCodecContext^.height;
  fScaledWidth  := fCodecContext^.width;
  fScaledHeight := fCodecContext^.height;
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, @MaxTexSize);
  while (Max(fTexWidth, fTexHeight) > MaxTexSize) do
  begin
    if not ReduceSize() then
    begin
      Log.LogError('Failed to create video texture', 'TVideoPlayback_ffmpeg.Open');
      Close();
      Exit;
    end;
  end;

  if (SupportsNPOT = false) then
  begin
    fTexWidth   := Round(Power(2, Ceil(Log2(fTexWidth))));
    fTexHeight  := Round(Power(2, Ceil(Log2(fTexHeight))));
  end;

  fFrameBuffer := av_malloc(av_image_get_buffer_size(PIXEL_FMT_FFMPEG,
      (fScaledWidth + BUFFER_ALIGN - 1) and -BUFFER_ALIGN, fScaledHeight, 1));
  if (fFrameBuffer = nil) then
  begin
    Log.LogError('Failed to allocate buffers', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  errnum := av_image_fill_arrays(@fAVFrameRGB^.data[0], @fAVFrameRGB^.linesize[0],
      fFrameBuffer, PIXEL_FMT_FFMPEG,
      (fScaledWidth + BUFFER_ALIGN - 1) and -BUFFER_ALIGN, fScaledHeight, 1);
  if (errnum < 0) then
  begin
    Log.LogError('av_image_fill_arrays failed: ' + FFmpegCore.GetErrorString(errnum), 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  // if available get a SWScale-context -> faster than the deprecated img_convert().
  // SWScale has accelerated support for PIX_FMT_RGB32/PIX_FMT_BGR24/PIX_FMT_BGR565/PIX_FMT_BGR555.
  // Note: PIX_FMT_RGB32 is a BGR- and not an RGB-format (maybe a bug)!!!
  // The BGR565-formats (GL_UNSIGNED_SHORT_5_6_5) is way too slow because of its
  // bad OpenGL support. The BGR formats have MMX(2) implementations but no speed-up
  // could be observed in comparison to the RGB versions.
  fSwScaleContext := sws_getContext(
      fCodecContext^.width, fCodecContext^.height,
      fCodecContext^.pix_fmt,
      fScaledWidth, fScaledHeight,
      PIXEL_FMT_FFMPEG,
      SWS_FAST_BILINEAR, nil, nil, nil);
  if (fSwScaleContext = nil) then
  begin
    Log.LogError('Failed to get swscale context', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  // we create the texture storage just once with glTexImage2D and update it
  // with glTexSubImage2D later (directly from the converted frame).
  glBindTexture(GL_TEXTURE_2D, fFrameTex);
  glTexImage2D(GL_TEXTURE_2D, 0, PIXEL_FMT_OPENGL, fTexWidth, fTexHeight, 0,
      PIXEL_FMT_OPENGL, GL_UNSIGNED_BYTE, nil);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindTexture(GL_TEXTURE_2D, 0);

  fOpened := true;
  Result := true;
end;

procedure TVideo_FFmpeg.Reset();
begin
  // close previously opened video
  Close();

  fOpened := False;
  fPaused := False;
  fFrameDuration := 0;
  fFrameTime := 0;
  fNextFrameTime := 0;
  fStream := nil;
  fStreamIndex := -1;
  fFrameTexValid := false;

  fEOF := false;
  fDraining := false;

  fLoop := false;
  fLoopTime := 0;

  fAspectCorrection := acoCrop;

  fScreen := 1;

  fPosX := 0;
  fPosY := 0;
  fPosZ := 0;
  fWidth := RenderW;
  fHeight := RenderH;

  fFrameRange.Left := 0;
  fFrameRange.Right := 1;
  fFrameRange.Upper := 0;
  fFrameRange.Lower := 1;

  fAlpha := 1;
  fReflectionSpacing := 0;
end;

procedure TVideo_FFmpeg.Close;
begin
  if (fFrameBuffer <> nil) then
    av_free(fFrameBuffer);
  if (fAVFrameRGB <> nil) then
    av_free(fAVFrameRGB);
  // av_frame_free() also releases the buffers referenced by the decoded frame
  if (fAVFrame <> nil) then
    av_frame_free(@fAVFrame);

  fAVFrame     := nil;
  fAVFrameRGB  := nil;
  fFrameBuffer := nil;

  if (fCodecContext <> nil) then
  begin
    // closing the codec is not thread-safe.
    // As we own the context (see Open) it is closed and freed here.
    FFmpegCore.LockAVCodec();
    try
      avcodec_free_context(fCodecContext);
    finally
      FFmpegCore.UnlockAVCodec();
    end;
  end;

  if (fFormatContext <> nil) then
    FFmpegCore.AVFormatCloseInput(@fFormatContext);

  fCodecContext  := nil;
  fFormatContext := nil;

  if (fSwScaleContext <> nil) then
  begin
    sws_freeContext(fSwScaleContext);
    fSwScaleContext := nil;
  end;

  fOpened := False;
end;

procedure TVideo_FFmpeg.SynchronizeTime(Frame: PAVFrame; pts: double);
var
  FrameDelay: double;
begin
  // a frame starts where the previous one ended ...
  fFrameTime := fNextFrameTime;
  if (pts <> 0) then
  begin
    // ... unless we have a pts, then set the video clock to it
    fFrameTime := pts;
  end;
  // duration of this frame.
  // Note: the codec context's time_base is not set for contexts created from
  // codec parameters. If there is no framerate either, we use the frame
  // duration determined in Open().
  if (fCodecContext^.framerate.num = 0) then
    FrameDelay := fFrameDuration
  else
    FrameDelay := fCodecContext^.framerate.den / fCodecContext^.framerate.num;
  // if we are repeating a frame, adjust clock accordingly
  FrameDelay := FrameDelay + Frame^.repeat_pict * (FrameDelay * 0.5);
  // update the video clock: position of the next frame
  fNextFrameTime := fFrameTime + FrameDelay;
end;

{**
 * Decode a new frame from the video stream.
 * The decoded frame is stored in fAVFrame. fFrameTime is updated to the new frame's
 * time.
 * @param pts will be updated to the presentation time of the decoded frame.
 * returns true if a frame could be decoded. False if an error or EOF occured.
 *}
function TVideo_FFmpeg.DecodeFrame(): boolean;
var
  FrameFinished: boolean;
  EOFReached: boolean;
  pbIOCtx: PAVIOContext;
  errnum: integer;
  Packet: PAVPacket;
  pts: int64;
  dts: int64;
  fileSize: int64;
  urlError: integer;
begin
  Result := false;

  if fEOF then
    Exit;

  Packet := av_packet_alloc();
  if (Packet = nil) then
  begin
    Log.LogError('Failed to allocate packet', 'TVideoPlayback_FFmpeg.DecodeFrame');
    Exit;
  end;

  try
    // read packets until we have a finished frame (or there are no more packets)
    FrameFinished := false;
    while (not FrameFinished) do
    begin
      // check if the decoder already has a finished frame for us.
      // Note: decoders may buffer several frames, so we have to ask for
      // output before we feed new input.
      errnum := avcodec_receive_frame(fCodecContext, fAVFrame);
      if (errnum = 0) then
      begin
        FrameFinished := true;
        Continue;
      end;

      if (fDraining) then
      begin
        // the decoder was flushed and has delivered all its frames
        // (the error is AVERROR_EOF)
        fEOF := true;
        Exit;
      end;

      // the decoder needs more input (EAGAIN).
      // Other decoding errors are ignored like before, we just read on.
      errnum := av_read_frame(fFormatContext, Packet^);
      if (errnum < 0) then
      begin
        // failed to read a frame, check reason

        pbIOCtx := fFormatContext^.pb;

        // check for end-of-file (EOF is not an error)
        EOFReached := (avio_feof(pbIOCtx) <> 0);

        if (not EOFReached) then
        begin
          // check for errors
          urlError := pbIOCtx^.error;
          if (urlError <> 0) then
          begin
            Log.LogError('Video decoding file error', 'TVideoPlayback_FFmpeg.DecodeFrame');
            Exit;
          end;

          // url_feof() does not detect an EOF for some mov-files (e.g. deluxe.mov)
          // so we have to do it this way.
          fileSize := avio_size(fFormatContext^.pb);
          EOFReached := ((fileSize <> 0) and (pbIOCtx^.pos >= fileSize)) or
                        (errnum = AVERROR_EOF); // newer libavformat versions tell us if EOF was reached
        end;

        if (not EOFReached) then
        begin
          // error occured, log and exit
          Log.LogError('Video decoding error: ' + IntToStr(errnum), 'TVideoPlayback_FFmpeg.DecodeFrame');
          Exit;
        end;

        // End of file: send a NULL packet to flush the decoder. Decoders with
        // delay (e.g. with B-frames) still hold frames that would be lost
        // otherwise. They are fetched with avcodec_receive_frame() above
        // until the decoder reports the end (see fDraining).
        avcodec_send_packet(fCodecContext, nil);
        fDraining := true;
        Continue;
      end;

      // if we got a packet from the video stream, then send it to the decoder
      if (Packet^.stream_index = fStreamIndex) then
        avcodec_send_packet(fCodecContext, Packet);

      // free the packet from av_read_frame
      av_packet_unref(Packet);
    end;
  finally
    av_packet_free(@Packet);
  end;

  // update pts (AVFrame.pkt_pts was removed in FFmpeg 5.0, AVFrame.pts
  // contains the same value)
  pts := fAVFrame^.pts;

  dts := fAVFrame^.pkt_dts;

  if (pts = AV_NOPTS_VALUE) or (fPreferDTS and (dts <> AV_NOPTS_VALUE)) then
    pts := dts;

  if pts = AV_NOPTS_VALUE then
    pts := 0
  else if fStream^.start_time <> AV_NOPTS_VALUE then
    pts := pts - fStream^.start_time;

  // synchronize time on each complete frame
  SynchronizeTime(fAVFrame, pts * av_q2d(fStream^.time_base));

  Result := true;
end;

procedure TVideo_FFmpeg.GetFrame(Time: Extended);
var
  errnum: Integer;
  CurrentTime: Extended;
  TimeDiff: Extended;
  DropFrameCount: Integer;
  i: Integer;
  Success: boolean;
const
  SKIP_FRAME_DIFF = 0.010; // start skipping if we are >= 10ms too late
begin
  if not fOpened then
    Exit;

  if fPaused then
    Exit;

  {*
   * Synchronization - begin
   *}

  // requested stream position (relative to the last loop's start)
  if (fLoop) then
    CurrentTime := Time - fLoopTime
  else
    CurrentTime := Time;

  // check if current texture still contains the active frame
  if (fFrameTexValid) then
  begin
    // time since the last frame was returned
    TimeDiff := CurrentTime - fFrameTime;

    {$IFDEF DebugDisplay}
    DebugWriteln('Time:      '+inttostr(floor(Time*1000)) + sLineBreak +
                 'VideoTime: '+inttostr(floor(fFrameTime*1000)) + sLineBreak +
                 'TimeBase:  '+inttostr(floor(fFrameDuration*1000)) + sLineBreak +
                 'TimeDiff:  '+inttostr(floor(TimeDifference*1000)));
    {$endif}

    // check if time has reached the next frame
    if (TimeDiff < fFrameDuration) then
    begin
      {$ifdef DebugFrames}
      // frame delay debug display
      GoldenRec.Spawn(200,15,1,16,0,-1,ColoredStar,$00ff00);
      {$endif}

      {$IFDEF DebugDisplay}
      DebugWriteln('not getting new frame' + sLineBreak +
          'Time:      '+inttostr(floor(Time*1000)) + sLineBreak +
          'VideoTime: '+inttostr(floor(fFrameTime*1000)) + sLineBreak +
          'TimeBase:  '+inttostr(floor(fFrameDuration*1000)) + sLineBreak +
          'TimeDiff:  '+inttostr(floor(TimeDifference*1000)));
      {$endif}

      // we do not need a new frame now
      Exit;
    end;
  end;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkStart(15);
  {$ENDIF}

  // fetch new frame (updates fFrameTime)
  Success := DecodeFrame();
  TimeDiff := CurrentTime - fFrameTime;

  // check if we have to skip frames
  // Either if we are one frame behind or if the skip threshold has been reached.
  // Do not skip if the difference is less than fFrameDuration as there is no next frame.
  // Note: We assume that fFrameDuration is the length of one frame.
  if (TimeDiff >= Max(fFrameDuration, SKIP_FRAME_DIFF)) then
  begin
    {$IFDEF DebugFrames}
    //frame drop debug display
    GoldenRec.Spawn(200,55,1,16,0,-1,ColoredStar,$ff0000);
    {$ENDIF}
    {$IFDEF DebugDisplay}
    DebugWriteln('skipping frames' + sLineBreak +
        'TimeBase:  '+inttostr(floor(fFrameDuration*1000)) + sLineBreak +
        'TimeDiff:  '+inttostr(floor(TimeDifference*1000)));
    {$endif}

    // update video-time
    DropFrameCount := Trunc(TimeDiff / fFrameDuration);
    fFrameTime := fFrameTime + DropFrameCount*fFrameDuration;

    // skip frames
    for i := 1 to DropFrameCount do
      Success := DecodeFrame();
  end;

  // check if we got an EOF or error
  if (not Success) then
  begin
    if fLoop then
    begin
      // we have to loop, so rewind
      SetPosition(0);
      // record the start-time of the current loop, so we can
      // determine the position in the stream (fFrameTime-fLoopTime) later.
      fLoopTime := Time;
    end;
    Exit;
  end;

  {*
   * Synchronization - end
   *}

  // TODO: support for pan&scan
  //if (fAVFrame.pan_scan <> nil) then
  //begin
  //  Writeln(Format('PanScan: %d/%d', [fAVFrame.pan_scan.width, fAVFrame.pan_scan.height]));
  //end;

  // otherwise we convert the pixeldata from YUV to RGB
  try
    errnum := sws_scale(fSwScaleContext, @fAVFrame.data, @fAVFrame.linesize, 0, fCodecContext^.Height, @fAVFrameRGB.data, @fAVFrameRGB.linesize);
  except
    ;
  end;

  {$IF (LIBSWSCALE_VERSION_MAJOR < 8) or ((LIBSWSCALE_VERSION_MAJOR = 8) and (LIBSWSCALE_VERSION_MINOR < 3))}
  {$IF DEFINED(CPUX86_64) or DEFINED(CPUX86)}
  // Unscaled conversion with libswscale lacked the emms instruction.
  // With FFmpeg 7.1 these mmx(ext) implementations have been removed.
  asm
    emms
  end ['st(0)','st(1)','st(2)','st(3)','st(4)','st(5)','st(6)','st(7)',
       'mm0','mm1','mm2','mm3','mm4','mm5','mm6','mm7'];
  {$ENDIF}
  {$IFEND}

  if (errnum < 0) then
  begin
    Log.LogError('Image conversion failed', 'TVideoPlayback_ffmpeg.GetFrame');
    Exit;
  end;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkEnd(15);
  Log.BenchmarkStart(16);
  {$ENDIF}


  // upload the converted frame directly into the texture
  glBindTexture(GL_TEXTURE_2D, fFrameTex);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, fAVFrameRGB.linesize[0] div PIXEL_FMT_SIZE);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
      fScaledWidth, fScaledHeight,
      PIXEL_FMT_OPENGL, GL_UNSIGNED_BYTE, fAVFrameRGB^.data[0]);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glBindTexture(GL_TEXTURE_2D, 0);

  if (not fFrameTexValid) then
    fFrameTexValid := true;

  {$ifdef DebugFrames}
  //frame decode debug display
  GoldenRec.Spawn(200, 35, 1, 16, 0, -1, ColoredStar, $ffff00);
  {$endif}

  {$IFDEF VideoBenchmark}
  Log.BenchmarkEnd(16);
  Log.LogBenchmark('FFmpeg', 15);
  Log.LogBenchmark('Texture', 16);
  {$ENDIF}
end;

procedure TVideo_FFmpeg.GetVideoRect(var ScreenRect, TexRect: TRectCoords);
var
  ScreenAspect: double;  // aspect of screen resolution
  ScaledVideoWidth, ScaledVideoHeight: double;

begin
  // Three aspects to take into account:
  //  1. Screen/display resolution (e.g. 1920x1080 -> 16:9)
  //  2. Render aspect (fWidth x fHeight -> variable)
  //  3. Movie aspect (video frame aspect stored in fAspect)
  ScreenAspect := fWidth*((ScreenW/Screens)/RenderW)/(fHeight*(ScreenH/RenderH));

  case fAspectCorrection of
    acoStretch: begin
      ScaledVideoWidth  := fWidth;
      ScaledVideoHeight := fHeight;
    end;

    acoCrop: begin
      if (ScreenAspect >= fAspect) then
      begin
        ScaledVideoWidth  := fWidth;
        ScaledVideoHeight := fHeight * ScreenAspect/fAspect;
      end else
      begin
        ScaledVideoHeight := fHeight;
        ScaledVideoWidth  := fWidth * fAspect/ScreenAspect;
      end;
    end;

    acoLetterBox: begin
      if (ScreenAspect <= fAspect) then
      begin
        ScaledVideoWidth  := fWidth;
        ScaledVideoHeight := fHeight * ScreenAspect/fAspect;
      end else
      begin
        ScaledVideoHeight := fHeight;
        ScaledVideoWidth  := fWidth * fAspect/ScreenAspect;
      end;
    end else
      raise Exception.Create('Unhandled aspect correction!');
  end;

  //center video
  ScreenRect.Left  := (fWidth - ScaledVideoWidth) / 2 + fPosX;
  ScreenRect.Right := ScreenRect.Left + ScaledVideoWidth;
  ScreenRect.Upper := (fHeight - ScaledVideoHeight) / 2 + fPosY;
  ScreenRect.Lower := ScreenRect.Upper + ScaledVideoHeight;

  // texture contains right/lower (power-of-2) padding.
  // Determine the texture coords of the video frame.
  TexRect.Left  := (fScaledWidth / fTexWidth) * fFrameRange.Left;
  TexRect.Right := (fScaledWidth / fTexWidth) * fFrameRange.Right;
  TexRect.Upper := (fScaledHeight / fTexHeight) * fFrameRange.Upper;
  TexRect.Lower := (fScaledHeight / fTexHeight) * fFrameRange.Lower;
end;

procedure TVideo_FFmpeg.DrawBorders(ScreenRect: TRectCoords);
  procedure DrawRect(left, right, upper, lower: double);
  begin
    glColor4f(0, 0, 0, fAlpha);
    glBegin(GL_QUADS);
      glVertex3f(left, upper, fPosZ);
      glVertex3f(right, upper, fPosZ);
      glVertex3f(right, lower, fPosZ);
      glVertex3f(left, lower, fPosZ);
    glEnd;
  end;
begin
  //upper border
  if(ScreenRect.Upper > fPosY) then
    DrawRect(fPosX, fPosX+fWidth, fPosY, ScreenRect.Upper);

  //lower border
  if(ScreenRect.Lower < fPosY+fHeight) then
    DrawRect(fPosX, fPosX+fWidth, ScreenRect.Lower, fPosY+fHeight);

  //left border
  if(ScreenRect.Left > fPosX) then
    DrawRect(fPosX, ScreenRect.Left, fPosY, fPosY+fHeight);

  //right border
  if(ScreenRect.Right < fPosX+fWidth) then
    DrawRect(ScreenRect.Right, fPosX+fWidth, fPosY, fPosY+fHeight);
end;

procedure TVideo_FFmpeg.DrawBordersReflected(ScreenRect: TRectCoords; AlphaUpper, AlphaLower: double);
var
  rPosUpper, rPosLower: double;

  procedure DrawRect(left, right, upper, lower: double);
  var
    AlphaTop: double;
    AlphaBottom: double;

  begin
    AlphaTop := AlphaUpper+(AlphaLower-AlphaUpper)*(upper-rPosUpper)/(fHeight*ReflectionH);
    AlphaBottom := AlphaLower+(AlphaUpper-AlphaLower)*(rPosLower-lower)/(fHeight*ReflectionH);

    glBegin(GL_QUADS);
      glColor4f(0, 0, 0, AlphaTop);
      glVertex3f(left, upper, fPosZ);
      glVertex3f(right, upper, fPosZ);

      glColor4f(0, 0, 0, AlphaBottom);
      glVertex3f(right, lower, fPosZ);
      glVertex3f(left, lower, fPosZ);
    glEnd;
  end;
begin
  rPosUpper := fPosY+fHeight+fReflectionSpacing;
  rPosLower := rPosUpper+fHeight*ReflectionH;

  //upper border
  if(ScreenRect.Upper > rPosUpper) then
    DrawRect(fPosX, fPosX+fWidth, rPosUpper, ScreenRect.Upper);

  //lower border
  if(ScreenRect.Lower < rPosLower) then
    DrawRect(fPosX, fPosX+fWidth, ScreenRect.Lower, rPosLower);

  //left border
  if(ScreenRect.Left > fPosX) then
    DrawRect(fPosX, ScreenRect.Left, rPosUpper, rPosLower);

  //right border
  if(ScreenRect.Right < fPosX+fWidth) then
    DrawRect(ScreenRect.Right, fPosX+fWidth, rPosUpper, rPosLower);
end;


{**
 * Creates the vertex buffer used for drawing. If this is not possible (or
 * VideoLegacyDraw is defined) the old immediate mode code is used instead.
 *}
procedure TVideo_FFmpeg.InitVertexBuffer();
begin
  fUseVBO := false;
  fVBO := 0;
  fVBOCursor := 0;
  fVBOBase := 0;
  fVertCount := 0;

  {$IFNDEF VideoLegacyDraw}
  if (not (Assigned(glGenBuffers) and Assigned(glBindBuffer) and
           Assigned(glBufferData) and Assigned(glBufferSubData) and
           Assigned(glDeleteBuffers))) then
    Exit;

  glGetError(); // clear previous errors
  glGenBuffers(1, @fVBO);
  glBindBuffer(GL_ARRAY_BUFFER, fVBO);
  glBufferData(GL_ARRAY_BUFFER, VBO_SIZE, nil, GL_STREAM_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  if (glGetError() <> GL_NO_ERROR) then
  begin
    Log.LogError('Vertex buffer initialization failed, using immediate mode', 'TVideo_FFmpeg.InitVertexBuffer');
    if (fVBO <> 0) then
      glDeleteBuffers(1, @fVBO);
    fVBO := 0;
    Exit;
  end;

  fUseVBO := true;
  {$ENDIF}
end;

{**
 * Compiles the shader used to draw from the vertex buffer.
 * It reads the same inputs as the fixed function pipeline (vertex, color and
 * texture coordinates from the vertex arrays, the current matrices via
 * ftransform()) and does the same calculation (texture * color), so the
 * result is identical. If anything fails the fixed function pipeline is used.
 *}
procedure TVideo_FFmpeg.InitShader();
{$IFNDEF VideoNoShader}
const
  VertexSource =
    '#version 110' + #10 +
    'void main()' + #10 +
    '{' + #10 +
    '  gl_Position = ftransform();' + #10 +
    '  gl_FrontColor = gl_Color;' + #10 +
    '  gl_TexCoord[0] = gl_MultiTexCoord0;' + #10 +
    '}' + #10;

  FragmentSource =
    '#version 110' + #10 +
    'uniform sampler2D tex;' + #10 +
    'uniform float use_tex;' + #10 +
    'void main()' + #10 +
    '{' + #10 +
    '  vec4 c = gl_Color;' + #10 +
    '  if (use_tex > 0.5)' + #10 +
    '    c = c * texture2D(tex, gl_TexCoord[0].xy);' + #10 +
    '  gl_FragColor = c;' + #10 +
    '}' + #10;
var
  VertexShader, FragmentShader: GLuint;
  CompileResult: GLint;
  ErrorBuf: array[0..511] of GLcharARB;

  function CompileShader(ShaderType: GLenum; Source: string; Name: string): GLuint;
  begin
    Result := glCreateShader(ShaderType);
    glShaderSource(Result, 1, PPGLcharARB(@Source), nil);
    glCompileShader(Result);
    glGetShaderiv(Result, GL_COMPILE_STATUS, @CompileResult);
    if (ByteBool(CompileResult) = GL_FALSE) then
    begin
      glGetShaderInfoLog(Result, SizeOf(ErrorBuf), nil, @ErrorBuf[0]);
      Log.LogError('Failed to compile ' + Name + ' shader: ' + ErrorBuf, 'TVideo_FFmpeg.InitShader');
      glDeleteShader(Result);
      Result := 0;
    end;
  end;
{$ENDIF}
begin
  fUseShader := false;
  fProg := 0;
  fLocUseTex := -1;

  {$IFNDEF VideoNoShader}
  if (not fUseVBO) then
    Exit;

  if (not (Assigned(glCreateShader) and Assigned(glShaderSource) and
           Assigned(glCompileShader) and Assigned(glGetShaderiv) and
           Assigned(glGetShaderInfoLog) and Assigned(glDeleteShader) and
           Assigned(glCreateProgram) and Assigned(glAttachShader) and
           Assigned(glLinkProgram) and Assigned(glGetProgramiv) and
           Assigned(glGetProgramInfoLog) and Assigned(glDeleteProgram) and
           Assigned(glUseProgram) and Assigned(glGetUniformLocation) and
           Assigned(glUniform1i) and Assigned(glUniform1f))) then
    Exit;

  VertexShader := CompileShader(GL_VERTEX_SHADER, VertexSource, 'vertex');
  if (VertexShader = 0) then
    Exit;
  FragmentShader := CompileShader(GL_FRAGMENT_SHADER, FragmentSource, 'fragment');
  if (FragmentShader = 0) then
  begin
    glDeleteShader(VertexShader);
    Exit;
  end;

  fProg := glCreateProgram();
  glAttachShader(fProg, VertexShader);
  glAttachShader(fProg, FragmentShader);
  glLinkProgram(fProg);
  glDeleteShader(VertexShader);
  glDeleteShader(FragmentShader);
  glGetProgramiv(fProg, GL_LINK_STATUS, @CompileResult);
  if (ByteBool(CompileResult) = GL_FALSE) then
  begin
    glGetProgramInfoLog(fProg, SizeOf(ErrorBuf), nil, @ErrorBuf[0]);
    Log.LogError('Failed to link video shader: ' + ErrorBuf, 'TVideo_FFmpeg.InitShader');
    glDeleteProgram(fProg);
    fProg := 0;
    Exit;
  end;

  fLocUseTex := glGetUniformLocation(fProg, 'use_tex');
  glUseProgram(fProg);
  glUniform1i(glGetUniformLocation(fProg, 'tex'), 0); // texture unit 0
  glUseProgram(0);

  fUseShader := true;
  {$ENDIF}
end;

procedure TVideo_FFmpeg.AddVertex(aX, aY, aZ, aR, aG, aB, aA, aU, aV: single);
begin
  if (fVertCount >= MAX_VERTICES) then
    Exit;
  fVerts[fVertCount].X := aX;
  fVerts[fVertCount].Y := aY;
  fVerts[fVertCount].Z := aZ;
  fVerts[fVertCount].R := aR;
  fVerts[fVertCount].G := aG;
  fVerts[fVertCount].B := aB;
  fVerts[fVertCount].A := aA;
  fVerts[fVertCount].U := aU;
  fVerts[fVertCount].V := aV;
  Inc(fVertCount);
end;

// black quad, the alpha value may differ between upper and lower edge
procedure TVideo_FFmpeg.AddBorderQuad(Left, Right, Upper, Lower, AlphaUpper, AlphaLower: single);
begin
  AddVertex(Left,  Upper, fPosZ, 0, 0, 0, AlphaUpper, 0, 0);
  AddVertex(Right, Upper, fPosZ, 0, 0, 0, AlphaUpper, 0, 0);
  AddVertex(Right, Lower, fPosZ, 0, 0, 0, AlphaLower, 0, 0);
  AddVertex(Left,  Lower, fPosZ, 0, 0, 0, AlphaLower, 0, 0);
end;

procedure TVideo_FFmpeg.AddBorders(ScreenRect: TRectCoords);
begin
  //upper border
  if(ScreenRect.Upper > fPosY) then
    AddBorderQuad(fPosX, fPosX+fWidth, fPosY, ScreenRect.Upper, fAlpha, fAlpha);

  //lower border
  if(ScreenRect.Lower < fPosY+fHeight) then
    AddBorderQuad(fPosX, fPosX+fWidth, ScreenRect.Lower, fPosY+fHeight, fAlpha, fAlpha);

  //left border
  if(ScreenRect.Left > fPosX) then
    AddBorderQuad(fPosX, ScreenRect.Left, fPosY, fPosY+fHeight, fAlpha, fAlpha);

  //right border
  if(ScreenRect.Right < fPosX+fWidth) then
    AddBorderQuad(ScreenRect.Right, fPosX+fWidth, fPosY, fPosY+fHeight, fAlpha, fAlpha);
end;

procedure TVideo_FFmpeg.AddBordersReflected(ScreenRect: TRectCoords; AlphaUpper, AlphaLower: double);
var
  rPosUpper, rPosLower: double;

  procedure AddRect(left, right, upper, lower: double);
  var
    AlphaTop: double;
    AlphaBottom: double;
  begin
    AlphaTop := AlphaUpper+(AlphaLower-AlphaUpper)*(upper-rPosUpper)/(fHeight*ReflectionH);
    AlphaBottom := AlphaLower+(AlphaUpper-AlphaLower)*(rPosLower-lower)/(fHeight*ReflectionH);
    AddBorderQuad(left, right, upper, lower, AlphaTop, AlphaBottom);
  end;
begin
  rPosUpper := fPosY+fHeight+fReflectionSpacing;
  rPosLower := rPosUpper+fHeight*ReflectionH;

  //upper border
  if(ScreenRect.Upper > rPosUpper) then
    AddRect(fPosX, fPosX+fWidth, rPosUpper, ScreenRect.Upper);

  //lower border
  if(ScreenRect.Lower < rPosLower) then
    AddRect(fPosX, fPosX+fWidth, ScreenRect.Lower, rPosLower);

  //left border
  if(ScreenRect.Left > fPosX) then
    AddRect(fPosX, ScreenRect.Left, rPosUpper, rPosLower);

  //right border
  if(ScreenRect.Right < fPosX+fWidth) then
    AddRect(ScreenRect.Right, fPosX+fWidth, rPosUpper, rPosLower);
end;

{**
 * Writes the collected vertices into the vertex buffer.
 * The buffer is used like a ring buffer: new vertices are written behind the
 * previous ones. When the end is reached the old storage is orphaned and we
 * start at the beginning again, so we never overwrite data the GPU may still
 * be reading.
 *}
procedure TVideo_FFmpeg.UploadVertices();
var
  Bytes: integer;
begin
  Bytes := fVertCount * VERTEX_BYTES;
  glBindBuffer(GL_ARRAY_BUFFER, fVBO);
  if (fVBOCursor + Bytes > VBO_SIZE) then
  begin
    glBufferData(GL_ARRAY_BUFFER, VBO_SIZE, nil, GL_STREAM_DRAW);
    fVBOCursor := 0;
  end;
  glBufferSubData(GL_ARRAY_BUFFER, fVBOCursor, Bytes, @fVerts[0]);
  fVBOBase := fVBOCursor;
  fVBOCursor := fVBOCursor + Bytes;
end;

// draws Count vertices (quads), beginning with vertex First of the last upload
procedure TVideo_FFmpeg.DrawVertices(First, Count: integer; Textured: boolean);
begin
  if (fUseShader) then
  begin
    glUseProgram(fProg);
    if (Textured) then
      glUniform1f(fLocUseTex, 1.0)
    else
      glUniform1f(fLocUseTex, 0.0);
  end;

  glEnableClientState(GL_VERTEX_ARRAY);
  glEnableClientState(GL_COLOR_ARRAY);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glVertexPointer(3, GL_FLOAT, VERTEX_BYTES, Pointer(PtrUInt(fVBOBase)));
  glColorPointer(4, GL_FLOAT, VERTEX_BYTES, Pointer(PtrUInt(fVBOBase + 3 * SizeOf(GLfloat))));
  glTexCoordPointer(2, GL_FLOAT, VERTEX_BYTES, Pointer(PtrUInt(fVBOBase + 7 * SizeOf(GLfloat))));
  glDrawArrays(GL_QUADS, First, Count);
end;

// restores the state that was changed for drawing from the vertex buffer
procedure TVideo_FFmpeg.EndVertexDraw();
begin
  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
  glDisableClientState(GL_VERTEX_ARRAY);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  if (fUseShader) then
    glUseProgram(0);
end;


procedure TVideo_FFmpeg.Draw();
var
  ScreenRect:   TRectCoords;
  TexRect:      TRectCoords;
  HeightFactor: double;
  WidthFactor:  double;

begin
  // exit if there's nothing to draw
  if (not fOpened) then
    Exit;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkStart(15);
  {$ENDIF}

  // get texture and screen positions
  GetVideoRect(ScreenRect, TexRect);

  WidthFactor := (ScreenW/Screens) / RenderW;
  HeightFactor := ScreenH / RenderH;

  glScissor(
    round(fPosX*WidthFactor + (ScreenW/Screens)*(fScreen-1)),
    round((RenderH-fPosY-fHeight)*HeightFactor),
    round(fWidth*WidthFactor),
    round(fHeight*HeightFactor)
    );

  glEnable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glDepthRange(0, 10);
  glDepthFunc(GL_LEQUAL);
  glEnable(GL_DEPTH_TEST);

  if (fUseVBO) then
  begin
    // the video frame and the black borders are written into the vertex
    // buffer with one upload. The first 4 vertices are the video frame.
    fVertCount := 0;
    // upper-left coord
    AddVertex(ScreenRect.Left, ScreenRect.Upper, fPosZ, 1, 1, 1, fAlpha, TexRect.Left, TexRect.Upper);
    // lower-left coord
    AddVertex(ScreenRect.Left, ScreenRect.Lower, fPosZ, 1, 1, 1, fAlpha, TexRect.Left, TexRect.Lower);
    // lower-right coord
    AddVertex(ScreenRect.Right, ScreenRect.Lower, fPosZ, 1, 1, 1, fAlpha, TexRect.Right, TexRect.Lower);
    // upper-right coord
    AddVertex(ScreenRect.Right, ScreenRect.Upper, fPosZ, 1, 1, 1, fAlpha, TexRect.Right, TexRect.Upper);
    AddBorders(ScreenRect);

    UploadVertices();

    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, fFrameTex);
    DrawVertices(0, 4, true);
    glDisable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, 0);

    //draw black borders
    if (fVertCount > 4) then
      DrawVertices(4, fVertCount - 4, false);

    EndVertexDraw();
  end
  else
  begin
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, fFrameTex);
    glColor4f(1, 1, 1, fAlpha);
    glBegin(GL_QUADS);
      // upper-left coord
      glTexCoord2f(TexRect.Left, TexRect.Upper);
      glVertex3f(ScreenRect.Left, ScreenRect.Upper, fPosZ);
      // lower-left coord
      glTexCoord2f(TexRect.Left, TexRect.Lower);
      glVertex3f(ScreenRect.Left, ScreenRect.Lower, fPosZ);
      // lower-right coord
      glTexCoord2f(TexRect.Right, TexRect.Lower);
      glVertex3f(ScreenRect.Right, ScreenRect.Lower, fPosZ);
      // upper-right coord
      glTexCoord2f(TexRect.Right, TexRect.Upper);
      glVertex3f(ScreenRect.Right, ScreenRect.Upper, fPosZ);
    glEnd;

    glDisable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, 0);

    //draw black borders
    DrawBorders(ScreenRect);
  end;

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);

  {$IFDEF VideoBenchmark}
  Log.BenchmarkEnd(15);
  Log.LogBenchmark('Draw', 15);
  {$ENDIF}

  {$IF Defined(Info) or Defined(DebugFrames)}
  ShowDebugInfo();
  {$IFEND}
end;

procedure TVideo_FFmpeg.DrawReflection();
var
  ScreenRect:   TRectCoords;
  TexRect:      TRectCoords;
  HeightFactor: double;
  WidthFactor:  double;

  AlphaTop:     double;
  AlphaBottom:  double;

  AlphaUpper:   double;
  AlphaLower:   double;

begin
  // exit if there's nothing to draw
  if (not fOpened) then
    Exit;

  // get texture and screen positions
  GetVideoRect(ScreenRect, TexRect);

  WidthFactor := (ScreenW/Screens) / RenderW;
  HeightFactor := ScreenH / RenderH;

  glScissor(
    round(fPosX*WidthFactor + (ScreenW/Screens)*(fScreen-1)),
    round((RenderH-fPosY-fHeight-fReflectionSpacing-fHeight*ReflectionH)*HeightFactor),
    round(fWidth*WidthFactor),
    round(fHeight*HeightFactor*ReflectionH)
    );

  glEnable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glDepthRange(0, 10);
  glDepthFunc(GL_LEQUAL);
  glEnable(GL_DEPTH_TEST);

  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  //calculate new ScreenRect coordinates for Reflection
  ScreenRect.Lower := fPosY + fHeight + fReflectionSpacing
    + (ScreenRect.Upper-fPosY) + (ScreenRect.Lower-ScreenRect.Upper)*ReflectionH;
  ScreenRect.Upper := fPosY + fHeight + fReflectionSpacing
    + (ScreenRect.Upper-fPosY);

  AlphaUpper := fAlpha-0.3;
  AlphaLower := 0;

  AlphaTop := AlphaUpper-(AlphaLower-AlphaUpper)*
    (ScreenRect.Upper-fPosY-fHeight-fReflectionSpacing)/fHeight;
  AlphaBottom := AlphaLower+(AlphaUpper-AlphaLower)*
    (fPosY+fHeight+fReflectionSpacing+fHeight*ReflectionH-ScreenRect.Lower)/fHeight;

  if (fUseVBO) then
  begin
    // reflected video frame (first 4 vertices) followed by the black borders
    fVertCount := 0;
    //Top Left
    AddVertex(ScreenRect.Left, ScreenRect.Upper, fPosZ, 1, 1, 1, AlphaTop,
              TexRect.Left, TexRect.Lower);
    //Bottom Left
    AddVertex(ScreenRect.Left, ScreenRect.Lower, fPosZ, 1, 1, 1, AlphaBottom,
              TexRect.Left, (TexRect.Lower-TexRect.Upper)*(1-ReflectionH));
    //Bottom Right
    AddVertex(ScreenRect.Right, ScreenRect.Lower, fPosZ, 1, 1, 1, AlphaBottom,
              TexRect.Right, (TexRect.Lower-TexRect.Upper)*(1-ReflectionH));
    //Top Right
    AddVertex(ScreenRect.Right, ScreenRect.Upper, fPosZ, 1, 1, 1, AlphaTop,
              TexRect.Right, TexRect.Lower);
    AddBordersReflected(ScreenRect, AlphaUpper, AlphaLower);

    UploadVertices();

    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, fFrameTex);
    DrawVertices(0, 4, true);
    glDisable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, 0);

    //draw black borders
    if (fVertCount > 4) then
      DrawVertices(4, fVertCount - 4, false);

    EndVertexDraw();
  end
  else
  begin
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, fFrameTex);

    glBegin(GL_QUADS);
      //Top Left
      glColor4f(1, 1, 1, AlphaTop);
      glTexCoord2f(TexRect.Left, TexRect.Lower);
      glVertex3f(ScreenRect.Left, ScreenRect.Upper, fPosZ);

      //Bottom Left
      glColor4f(1, 1, 1, AlphaBottom);
      glTexCoord2f(TexRect.Left, (TexRect.Lower-TexRect.Upper)*(1-ReflectionH));
      glVertex3f(ScreenRect.Left, ScreenRect.Lower, fPosZ);

      //Bottom Right
      glColor4f(1, 1, 1, AlphaBottom);
      glTexCoord2f(TexRect.Right, (TexRect.Lower-TexRect.Upper)*(1-ReflectionH));
      glVertex3f(ScreenRect.Right, ScreenRect.Lower, fPosZ);

      //Top Right
      glColor4f(1, 1, 1, AlphaTop);
      glTexCoord2f(TexRect.Right, TexRect.Lower);
      glVertex3f(ScreenRect.Right, ScreenRect.Upper, fPosZ);
    glEnd;

    glDisable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, 0);

    //draw black borders
    DrawBordersReflected(ScreenRect, AlphaUpper, AlphaLower);
  end;

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
end;

procedure TVideo_FFmpeg.ShowDebugInfo();
begin
  {$IFDEF Info}
  if (fFrameTime+fFrameDuration < 0) then
  begin
    glColor4f(0.7, 1, 0.3, 1);
    SetFontStyle (1);
    SetFontItalic(False);
    SetFontSize(27);
    SetFontPos (300, 0);
    glPrint('Delay due to negative VideoGap');
    glColor4f(1, 1, 1, 1);
  end;
  {$ENDIF}

  {$IFDEF DebugFrames}
    glColor4f(0, 0, 0, 0.2);
    glbegin(GL_QUADS);
      glVertex2f(0, 0);
      glVertex2f(0, 70);
      glVertex2f(250, 70);
      glVertex2f(250, 0);
    glEnd;

    glColor4f(1, 1, 1, 1);
    SetFontStyle (1);
    SetFontItalic(False);
    SetFontSize(27);
    SetFontPos (5, 0);
    glPrint('delaying frame');
    SetFontPos (5, 20);
    glPrint('fetching frame');
    SetFontPos (5, 40);
    glPrint('dropping frame');
  {$ENDIF}
end;

procedure TVideo_FFmpeg.Play;
begin
end;

procedure TVideo_FFmpeg.Pause;
begin
  fPaused := not fPaused;
end;

procedure TVideo_FFmpeg.Stop;
begin
end;

procedure TVideo_FFmpeg.SetLoop(Enable: boolean);
begin
  fLoop := Enable;
  fLoopTime := 0;
end;

function TVideo_FFmpeg.GetLoop(): boolean;
begin
  Result := fLoop;
end;

{**
 * Sets the stream's position.
 * The stream is set to the first keyframe with timestamp <= Time.
 * Note that fFrameTime is set to Time no matter if the actual position seeked to is
 * at Time or the time of a preceding keyframe. fFrameTime will be updated to the
 * actual frame time when GetFrame() is called the next time.
 * @param Time new position in seconds
 *}
procedure TVideo_FFmpeg.SetPosition(Time: real);
var
  SeekFlags: integer;
begin
  if not fOpened then
    Exit;

  if (Time < 0) then
    Time := 0;

  // TODO: handle fLoop-times
  //Time := Time mod VideoDuration;

  // Do not use the AVSEEK_FLAG_ANY here. It will seek to any frame, even
  // non keyframes (P-/B-frames). It will produce corrupted video frames as
  // FFmpeg does not use the information of the preceding I-frame.
  // The picture might be gray or green until the next keyframe occurs.
  // Instead seek the first keyframe smaller than the requested time
  // (AVSEEK_FLAG_BACKWARD). As this can be some seconds earlier than the
  // requested time, let the sync in GetFrame() do its job.
  SeekFlags := AVSEEK_FLAG_BACKWARD;

  fFrameTime := Time;
  fNextFrameTime := Time;
  fEOF := false;
  fDraining := false;
  fFrameTexValid := false;

  if (av_seek_frame(fFormatContext,
     fStreamIndex,
     Round(Time / av_q2d(fStream^.time_base)),
     SeekFlags) < 0) then
  begin
      Log.LogError('av_seek_frame() failed', 'TVideoPlayback_ffmpeg.SetPosition');
      Exit;
  end;

  avcodec_flush_buffers(fCodecContext);
end;

function  TVideo_FFmpeg.GetPosition: real;
begin
  Result := fFrameTime;
end;

procedure TVideo_FFmpeg.SetScreen(Screen: integer);
begin
  fScreen := Screen;
end;

function TVideo_FFmpeg.GetScreen(): integer;
begin
  Result := fScreen;
end;


procedure TVideo_FFmpeg.SetScreenPosition(X, Y, Z: double);
begin
  fPosX := X;
  fPosY := Y;
  fPosZ := Z;
end;

procedure TVideo_FFmpeg.GetScreenPosition(var X, Y, Z: double);
begin
  X := fPosX;
  Y := fPosY;
  Z := fPosZ;
end;


procedure TVideo_FFmpeg.SetWidth(Width: double);
begin
  fWidth := Width;
end;

function TVideo_FFmpeg.GetWidth(): double;
begin
  Result := fWidth;
end;


procedure TVideo_FFmpeg.SetHeight(Height: double);
begin
  fHeight := Height;
end;

function TVideo_FFmpeg.GetHeight(): double;
begin
  Result := fHeight;
end;


procedure TVideo_FFmpeg.SetFrameRange(Range: TRectCoords);
begin
  fFrameRange := Range;
end;

function TVideo_FFmpeg.GetFrameRange(): TRectCoords;
begin
  Result := fFrameRange;
end;


function TVideo_FFmpeg.GetFrameAspect(): real;
begin
  Result := fAspect;
end;


procedure TVideo_FFmpeg.SetAspectCorrection(AspectCorrection: TAspectCorrection);
begin
  fAspectCorrection := AspectCorrection;
end;

function TVideo_FFmpeg.GetAspectCorrection(): TAspectCorrection;
begin
  Result := fAspectCorrection;
end;



procedure TVideo_FFmpeg.SetAlpha(Alpha: double);
begin
  fAlpha := Alpha;

  if (fAlpha>1) then
    fAlpha := 1;

  if (fAlpha<0) then
    fAlpha := 0;
end;

function TVideo_FFmpeg.GetAlpha(): double;
begin
  Result := fAlpha;
end;


procedure TVideo_FFmpeg.SetReflectionSpacing(Spacing: double);
begin
  fReflectionSpacing := Spacing;
end;

function TVideo_FFmpeg.GetReflectionSpacing(): double;
begin
  Result := fReflectionSpacing;
end;


initialization
  MediaManager.Add(TVideoPlayback_FFmpeg.Create);

end.
