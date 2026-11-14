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

unit USongs;

interface

{$MODE OBJFPC}

{$I switches.inc}

uses
  Classes,
  {$IFDEF MSWINDOWS}
    Windows,
    LazUTF8Classes,
  {$ELSE}
    baseunix,
    cthreads,
    cmem,
    {$IFNDEF DARWIN}
    syscall,
    {$ENDIF}
    UnixType,
  {$ENDIF}
  CpuCount,
  sdl2,
  SysUtils,
  UCatCovers,
  UCommon,
  UImage,
  UIni,
  ULog,
  UPath,
  UPlatform,
  UPlaylist,
  USong,
  UTexture;

type
  TSongFilter = (sfAll, sfArtist, sfCategory, sfPlaylist, sfTitle);

  TScore = record
    Name:   UTF8String;
    Score:  integer;
    Length: string;
  end;

  TProgressSong = record
    Folder: UTF8String;
    FolderProcessed: UTF8String;
    Total: integer;
    Finished: boolean;
    CoversPreload: boolean;
  end;

  TSongsParse = class(TThread)
    private
      Event: PRTLEvent; //event to fire parsing songs
      TxtParsed: integer; //number of txts parsed
      TxtsParsed: TList; //list to store all parsed songs as TSong object
      Txts: TList; //list to store only correct songs from TxtsParsed
    protected
      procedure Execute; override;
    public
      constructor Create();
      destructor Destroy(); override;
      procedure Stop(); //wakes up and ends the thread
      procedure AddSong(const TxtFile: IPath);
      function GetTxtParsed(): integer;
      function GetTxts(): TList;
  end;

  TSongs = class(TThread)
    private
      Event: PRTLEvent; //event to fire cover preload
      PreloadCover: boolean;
      ProgressSong: TProgressSong;
      Threads: array of TSongsParse; //threads to parse songs
      Thread: integer; //current thread
      CoresAvailable: integer; //cores available for working threads
      ForceScan: boolean; //true = ignore the song database and search the song directories
      procedure FindTxts(const Dir: IPath);
      function CacheFileName(): UTF8String;
      function LoadFromCache(): boolean;
      procedure SaveToCache();
      procedure FreeSongs();
      procedure ScanDirs();
      procedure PreloadAllCovers();
    protected
      procedure Execute; override;
    public
      SongList: TList; //array of songs
      Selected: integer; //selected song index
      constructor Create(AForceScan: boolean = false);
      destructor Destroy(); override;
      function GetLoadProgress(): TProgressSong;
      procedure PreloadCovers(Preload: boolean);
      procedure Sort(OrderType: TSortingType);
  end;

  TCatSongs = class
    private
      ShowDuets: boolean;
      ShowCategories: boolean;
      Sorting: integer;
      VisibleSongs: integer;
      procedure SortSongs();
    public
      Song: array of TSong; //songs categorized
      Selected: integer; //selected song index
      CatNumShow: integer; //selected category (-1 = all songs/all categories, -3 = playlist)
      CatCount: integer; //number of categories
      constructor Create();
      function FindGlobalIndex(VisibleIndex:integer): integer; //find global index of all songs from a index of visible songs subgroup
      function FindVisibleIndex(Index: integer): integer; //find the index of a song in the subset of all visible songs
      function GetVisibleSongs(): integer; //returns number of visible songs
      function IsFilterApplied(): boolean; //returns if some filter has been applied to song list
      function Refresh(Sort: integer; Categories: boolean; Duets: boolean): boolean; //sets sorting, show or not songs in categories and/or duets refreshing songs array
      function SetFilter(FilterStr: UTF8String; Filter: TSongFilter = sfAll): cardinal;
      function ShowCategory(Index: integer): integer; //show songs of a category
      procedure ShowPlaylist(Index: integer); //show songs of a playlist
  end;

var
  Songs: TSongs; //all songs
  CatSongs: TCatSongs; //categorized songs

implementation

uses
  FileUtil,
  Math,
  StrUtils,
  UFiles,
  UFilesystem,
  UGraphic,
  ULanguage,
  UMain,
  UNote,
  SQLiteTable3,
  UPathUtils,
  UTextEncoding,
  UUnicodeUtils;

const
  SONG_CACHE_VERSION = 1; // increase if the table layout or the TSong fields change

type
  TSongCache = class
    private
      DB: TSQLiteDatabase;
      function GetMeta(const Key: UTF8String): UTF8String;
      procedure SetMeta(const Key, Value: UTF8String);
      function SongDirsSignature(): UTF8String;
    public
      constructor Create(const FileName: UTF8String);
      destructor Destroy(); override;
      // true if the cache was written with this version and for the same song directories
      function IsValid(): boolean;
      // appends TSong objects to List (owner of the objects is the caller!)
      function Load(List: TList): boolean;
      // replaces the whole cache content with the songs of List
      procedure Save(List: TList);
  end;

const
  cSongs = 'us_songcache';
  cMeta  = 'us_songcache_meta';

function PathToStr(const P: IPath): UTF8String;
begin
  if P.IsUnset() then
    Result := ''
  else
    Result := P.ToUTF8();
end;

function StrToPath(const S: UTF8String): IPath;
begin
  if S = '' then
    Result := PATH_NONE()
  else
    Result := UPath.Path(S);
end;

constructor TSongCache.Create(const FileName: UTF8String);
begin
  inherited Create();
  Self.DB := TSQLiteDatabase.Create(FileName);

  Self.DB.ExecSQL('CREATE TABLE IF NOT EXISTS [' + cMeta + '] (' +
                    '[Key] TEXT PRIMARY KEY, ' +
                    '[Value] TEXT NULL' +
                  ');');

  Self.DB.ExecSQL('CREATE TABLE IF NOT EXISTS [' + cSongs + '] (' +
                    '[TxtFile] TEXT NOT NULL, ' +
                    '[Title] TEXT NULL, ' +
                    '[Artist] TEXT NULL, ' +
                    '[TitleNoAccent] TEXT NULL, ' +
                    '[ArtistNoAccent] TEXT NULL, ' +
                    '[Genre] TEXT NULL, ' +
                    '[Edition] TEXT NULL, ' +
                    '[Language] TEXT NULL, ' +
                    '[Year] INTEGER NULL, ' +
                    '[Creator] TEXT NULL, ' +
                    '[Fixer] TEXT NULL, ' +
                    '[Mp3] TEXT NULL, ' +
                    '[Cover] TEXT NULL, ' +
                    '[Background] TEXT NULL, ' +
                    '[Video] TEXT NULL, ' +
                    '[VideoGAP] REAL NULL, ' +
                    '[StartSec] REAL NULL, ' +
                    '[Finish] INTEGER NULL, ' +
                    '[BPM] REAL NULL, ' +
                    '[GAP] REAL NULL, ' +
                    '[Encoding] INTEGER NULL, ' +
                    '[PreviewStart] REAL NULL, ' +
                    '[MedleySource] INTEGER NULL, ' +
                    '[MedleyStart] INTEGER NULL, ' +
                    '[MedleyEnd] INTEGER NULL, ' +
                    '[IsDuet] INTEGER NULL, ' +
                    '[HasRap] INTEGER NULL, ' +
                    '[DuetName1] TEXT NULL, ' +
                    '[DuetName2] TEXT NULL, ' +
                    '[MD5] TEXT NULL' +
                  ');');
end;

destructor TSongCache.Destroy();
begin
  Self.DB.Free();
  inherited;
end;

function TSongCache.GetMeta(const Key: UTF8String): UTF8String;
begin
  Result := Self.DB.GetTableString('SELECT [Value] FROM [' + cMeta + '] WHERE [Key] = ?', [Key]);
end;

procedure TSongCache.SetMeta(const Key, Value: UTF8String);
begin
  Self.DB.ExecSQL('INSERT OR REPLACE INTO [' + cMeta + '] ([Key], [Value]) VALUES (?, ?)', [Key, Value]);
end;

{ All configured song directories as one string. If the user changes the
  directories in the ini file the cache is not valid anymore. }
function TSongCache.SongDirsSignature(): UTF8String;
var
  I: integer;
begin
  Result := '';
  for I := 0 to UPathUtils.SongPaths.Count - 1 do
    Result := Result + IPath(UPathUtils.SongPaths[I]).ToUTF8() + '|';
end;

function TSongCache.IsValid(): boolean;
begin
  Result := (Self.GetMeta('version') = IntToStr(SONG_CACHE_VERSION)) and
            (Self.GetMeta('songdirs') = Self.SongDirsSignature());
end;

function TSongCache.Load(List: TList): boolean;
var
  Table: TSQLiteUniTable;
  Song: TSong;
begin
  Result := false;
  if not Self.IsValid() then
    Exit;

  Table := Self.DB.GetUniTable(
    'SELECT [TxtFile], [Title], [Artist], [TitleNoAccent], [ArtistNoAccent], ' +      // 0..4
           '[Genre], [Edition], [Language], [Year], [Creator], [Fixer], ' +           // 5..10
           '[Mp3], [Cover], [Background], [Video], ' +                                // 11..14
           '[VideoGAP], [StartSec], [Finish], [BPM], [GAP], ' +                       // 15..19
           '[Encoding], [PreviewStart], [MedleySource], [MedleyStart], [MedleyEnd], ' + // 20..24
           '[IsDuet], [HasRap], [DuetName1], [DuetName2], [MD5] ' +                   // 25..29
    'FROM [' + cSongs + ']');
  try
    while not Table.EOF do
    begin
      // sets Path, FileName, FullPath and Folder (category) from the txt filename
      Song := TSong.Create(UPath.Path(Table.FieldAsString(0)));
      List.Add(Song);

      Song.Title          := Table.FieldAsString(1);
      Song.Artist         := Table.FieldAsString(2);
      Song.TitleNoAccent  := Table.FieldAsString(3);
      Song.ArtistNoAccent := Table.FieldAsString(4);
      Song.Genre          := Table.FieldAsString(5);
      Song.Edition        := Table.FieldAsString(6);
      Song.Language       := Table.FieldAsString(7);
      Song.Year           := Integer(Table.FieldAsInteger(8));
      Song.Creator        := Table.FieldAsString(9);
      Song.Fixer          := Table.FieldAsString(10);
      Song.Mp3            := StrToPath(Table.FieldAsString(11));
      Song.Cover          := StrToPath(Table.FieldAsString(12));
      Song.Background     := StrToPath(Table.FieldAsString(13));
      Song.Video          := StrToPath(Table.FieldAsString(14));
      Song.VideoGAP       := Table.FieldAsDouble(15);
      Song.Start          := Table.FieldAsDouble(16);
      Song.Finish         := Integer(Table.FieldAsInteger(17));
      Song.BPM            := Table.FieldAsDouble(18);
      Song.GAP            := Table.FieldAsDouble(19);
      Song.Encoding       := TEncoding(Integer(Table.FieldAsInteger(20)));
      Song.PreviewStart   := Table.FieldAsDouble(21);
      Song.Medley.Source    := TMedleySource(Integer(Table.FieldAsInteger(22)));
      Song.Medley.StartBeat := Integer(Table.FieldAsInteger(23));
      Song.Medley.EndBeat   := Integer(Table.FieldAsInteger(24));
      Song.isDuet         := Table.FieldAsInteger(25) <> 0;
      Song.hasRap         := Table.FieldAsInteger(26) <> 0;
      Song.DuetNames[0]   := Table.FieldAsString(27);
      Song.DuetNames[1]   := Table.FieldAsString(28);
      Song.MD5            := Table.FieldAsString(29);
      Song.Validated      := true;

      Table.Next();
    end;
  finally
    Table.Free();
  end;

  Result := List.Count > 0;
end;

procedure TSongCache.Save(List: TList);
var
  I: integer;
  Song: TSong;
begin
  Self.DB.BeginTransaction();
  try
    Self.DB.ExecSQL('DELETE FROM [' + cSongs + ']');

    for I := 0 to List.Count - 1 do
    begin
      Song := TSong(List[I]);
      Self.DB.ExecSQL(
        'INSERT INTO [' + cSongs + '] (' +
          '[TxtFile], [Title], [Artist], [TitleNoAccent], [ArtistNoAccent], ' +
          '[Genre], [Edition], [Language], [Year], [Creator], [Fixer], ' +
          '[Mp3], [Cover], [Background], [Video], ' +
          '[VideoGAP], [StartSec], [Finish], [BPM], [GAP], ' +
          '[Encoding], [PreviewStart], [MedleySource], [MedleyStart], [MedleyEnd], ' +
          '[IsDuet], [HasRap], [DuetName1], [DuetName2], [MD5]) ' +
        'VALUES (?,?,?,?,?, ?,?,?,?,?,?, ?,?,?,?, ?,?,?,?,?, ?,?,?,?,?, ?,?,?,?,?)',
        [
          PathToStr(Song.Path.Append(Song.FileName)),
          Song.Title, Song.Artist, Song.TitleNoAccent, Song.ArtistNoAccent,
          Song.Genre, Song.Edition, Song.Language, Song.Year, Song.Creator, Song.Fixer,
          PathToStr(Song.Mp3), PathToStr(Song.Cover), PathToStr(Song.Background), PathToStr(Song.Video),
          Song.VideoGAP, Song.Start, Song.Finish, Song.BPM, Song.GAP,
          Ord(Song.Encoding), Song.PreviewStart, Ord(Song.Medley.Source), Song.Medley.StartBeat, Song.Medley.EndBeat,
          Song.isDuet, Song.hasRap, Song.DuetNames[0], Song.DuetNames[1], Song.MD5
        ]);
    end;

    Self.SetMeta('version', IntToStr(SONG_CACHE_VERSION));
    Self.SetMeta('songdirs', Self.SongDirsSignature());
    Self.DB.Commit();
  except
    Self.DB.Rollback();
    raise;
  end;

  // SQLite does not give free space back to the file system after DELETE,
  // so shrink the file (must be outside of a transaction)
  try
    Self.DB.ExecSQL('VACUUM');
  except
    on E: Exception do
      ; // not critical, the file is only bigger than needed
  end;
end;


constructor TSongsParse.Create();
begin
  inherited Create(true); //suspended: the thread must not run before the fields exist
  Self.Event := RTLEventCreate();
  Self.FreeOnTerminate := true;
  Self.TxtParsed := 0;
  Self.Txts := TList.Create();
  Self.TxtsParsed := TList.Create();
  Self.Start();
end;

destructor TSongsParse.Destroy();
begin
  RTLeventDestroy(Self.Event);
  Self.Txts.Free();
  Self.TxtsParsed.Free();
  inherited;
end;

procedure TSongsParse.Stop();
begin
  Self.Terminate();
  RtlEventSetEvent(Self.Event); //otherwise the thread sleeps forever in RtlEventWaitFor
end;

procedure TSongsParse.Execute();
var
  Song: TSong;
  I: integer;
begin
  while not Self.Terminated do
  begin
    RtlEventWaitFor(Self.Event);
    for I := Self.TxtParsed to Self.TxtsParsed.Count - 1 do //start to parse from the last position
    begin
      Song := TSong(Self.TxtsParsed.Items[I]);
      if Song.Analyse() then
        Self.Txts.Add(Song);

      Inc(Self.TxtParsed);
    end;
  end;
end;

procedure TSongsParse.AddSong(const TxtFile: IPath);
begin
  Self.TxtsParsed.Add(USong.TSong.Create(TxtFile));
  RtlEventSetEvent(Self.Event);
end;

function TSongsParse.GetTxtParsed(): integer;
begin
  Result := Self.TxtParsed;
end;

function TSongsParse.GetTxts(): TList;
begin
  Result := Self.Txts;
end;

constructor TSongs.Create(AForceScan: boolean = false);
begin
  inherited Create(true); //suspended: the thread must not run before the fields exist
  Self.Event := RTLEventCreate();
  Self.FreeOnTerminate := false;
  Self.ForceScan := AForceScan;
  Self.SongList := TList.Create();
  Self.Thread := 0;
  Self.CoresAvailable := Max(0, CpuCount.GetLogicalCpuCount() - 2); //total core - main and songs threads
  Self.Start();
end;

destructor TSongs.Destroy();
begin
  Self.Terminate(); //stops a running cover preload
  RtlEventSetEvent(Self.Event);
  inherited; //waits for the thread
  RTLeventDestroy(Self.Event);
end;

{ Search for all files and directories }
procedure TSongs.FindTxts(const Dir: IPath);
var
  FileInfo: TFileInfo;
  Iter: IFileIterator;
begin
  Iter := FileSystem.FileFind(Dir.Append('*'), faAnyFile);
  while Iter.HasNext do //content of current folder
  begin
    FileInfo := Iter.Next; //get file info
    if ((FileInfo.Attr and faDirectory) <> 0) and (not (FileInfo.Name.ToUTF8()[1] = '.')) then //if is a directory try to find more
    begin
      Self.ProgressSong.FolderProcessed := FileInfo.Name.ToNative();
      Self.FindTxts(Dir.Append(FileInfo.Name))
    end
    else if FileInfo.Name.GetExtension().ToNative() = '.txt' then //if is a txt file send to a thread to parse it
    begin
      Inc(Self.ProgressSong.Total);
      Self.Threads[Self.Thread].AddSong(Dir.Append(FileInfo.Name));
      if Self.Thread = Self.CoresAvailable then //each txt to one thread
        Self.Thread := 0
      else
        Inc(Self.Thread)
    end
  end;
end;

{ File of the song database (next to Ultrastar.db) }
function TSongs.CacheFileName(): UTF8String;
begin
  Result := Platform.GetGameUserPath.Append('Ultrastar.songs.db').ToUTF8();
end;

{ Free songs which are not needed anymore (only used if the database is broken) }
procedure TSongs.FreeSongs();
var
  I: integer;
begin
  for I := 0 to Self.SongList.Count - 1 do
    TSong(Self.SongList.Items[I]).Free();
  Self.SongList.Clear();
end;

{ Try to fill SongList from the database. Returns false if there is no valid database. }
function TSongs.LoadFromCache(): boolean;
var
  Cache: TSongCache;
begin
  Result := false;
  Log.BenchmarkStart(2);
  try
    Cache := TSongCache.Create(Self.CacheFileName());
    try
      Result := Cache.Load(Self.SongList);
    finally
      Cache.Free();
    end;
  except
    on E: Exception do
      Log.LogError('Song database could not be read: ' + E.Message, 'TSongs.LoadFromCache');
  end;

  if Result then
  begin
    Log.LogStatus('Loaded ' + IntToStr(Self.SongList.Count) + ' songs from database', 'SongList');
    Self.ProgressSong.Total := Self.SongList.Count; //ScreenMain hides the error popup if Total > 0
    Self.ProgressSong.Folder := '';
    Self.ProgressSong.Finished := true;
    Log.LogBenchmark('Song loading (database)', 2);
  end
  else
    Self.FreeSongs(); //throw away partially loaded data
end;

{ Write SongList to the database }
procedure TSongs.SaveToCache();
var
  Cache: TSongCache;
begin
  try
    Cache := TSongCache.Create(Self.CacheFileName());
    try
      Cache.Save(Self.SongList);
    finally
      Cache.Free();
    end;
  except
    on E: Exception do
      Log.LogError('Song database could not be written: ' + E.Message, 'TSongs.SaveToCache');
  end;
end;

{ Search the song directories, parse all txt files and store the result in the database }
procedure TSongs.ScanDirs();
var
  I, Processed: integer;
begin
  Log.BenchmarkStart(2);
  Log.LogStatus('Searching for songs', 'SongList');
  Self.ProgressSong.Total := 0;
  Self.ProgressSong.Finished := false;

  //parser threads are only needed for a scan
  SetLength(Self.Threads, Self.CoresAvailable + 1);
  for I := 0 to Self.CoresAvailable do
    Self.Threads[I] := TSongsParse.Create();

  for I := 0 to UPathUtils.SongPaths.Count - 1 do //find txt files on directories and add songs
  begin
    Self.ProgressSong.Folder := Format(ULanguage.Language.Translate('SING_LOADING_SONGS'), [IPath(UPathUtils.SongPaths[I]).ToNative()]);
    Self.FindTxts(IPath(UPathUtils.SongPaths[I]));
  end;

  repeat //wait a little to finish parsing last songs
    Processed := 0;
    for I := 0 to Self.CoresAvailable do
      Inc(Processed, Self.Threads[I].GetTxtParsed());
    if Processed < Self.ProgressSong.Total then
      Sleep(5);
  until Processed >= Self.ProgressSong.Total;

  for I := 0 to Self.CoresAvailable do
  begin
    Self.SongList.AddList(Self.Threads[I].GetTxts()); //add all songs parsed to main list
    Self.Threads[I].Stop(); //the thread frees itself
  end;

  Log.LogStatus('Search complete: '+IntToStr(Processed)+' songs found ('+IntToStr(Processed - Self.SongList.Count)+' with errors)', 'SongList');
  Self.SaveToCache();
  Self.ProgressSong.Folder := '';
  Self.ProgressSong.Finished := true;
  Log.LogBenchmark('Song loading', 2);
end;

{ preloading covers in HDD cache only touching the file }
procedure TSongs.PreloadAllCovers();
var
  I: integer;
  Song: TSong;
begin
  Log.BenchmarkStart(3);
  Self.PreloadCover := true;
  for I := 0 to Self.SongList.Count - 1 do
  begin
    if Self.Terminated then
      Break;
    Song := TSong(Self.SongList.Items[I]);
    if not Self.PreloadCover then
      RtlEventWaitFor(Self.Event);

    SDL_FreeSurface(UImage.LoadImage(Song.Path.Append(Song.Cover)));
  end;
  Self.ProgressSong.CoversPreload := false;
  Log.LogBenchmark('Cover loading', 3);
end;

{ Create a new thread to load songs and update main screen with progress.
  The songs are read from the database; the directories are only searched
  if there is no valid database or if ForceScan is set. }
procedure TSongs.Execute();
begin
  Self.ProgressSong.Total := 0;
  Self.ProgressSong.Finished := false;
  Self.ProgressSong.CoversPreload := true;

  if Self.ForceScan or (not Self.LoadFromCache()) then
    Self.ScanDirs();
  Self.PreloadAllCovers();
  Self.Terminate();
end;

function TSongs.GetLoadProgress(): TProgressSong;
begin
  Result := Self.ProgressSong;
end;

{* Start/stop the covers preloading *}
procedure TSongs.PreloadCovers(Preload: boolean);
begin
  Self.PreloadCover := Preload;
  if Preload then
    RtlEventSetEvent(Self.Event);
end;

(*
 * Comparison functions for sorting
 *)

function CompareByEdition(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Edition, TSong(Song2).Edition);
end;

function CompareByGenre(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Genre, TSong(Song2).Genre);
end;

function CompareByTitle(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).TitleNoAccent, TSong(Song2).TitleNoAccent);
end;

function CompareByArtist(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).ArtistNoAccent, TSong(Song2).ArtistNoAccent);
end;

function CompareByFolder(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Folder, TSong(Song2).Folder);
end;

function CompareByLanguage(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Language, TSong(Song2).Language);
end;

function CompareByYear(Song1, Song2: Pointer): integer;
begin
  if (TSong(Song1).Year > TSong(Song2).Year) then
    Result := 1
  else
    Result := 0;
end;

procedure TSongs.Sort(OrderType: TSortingType);
var
  CompareFunc: TListSortCompare;
begin
  // FIXME: what is the difference between artist and artist2, etc.?
  case OrderType of
    sEdition: // by edition
      CompareFunc := @CompareByEdition;
    sGenre: // by genre
      CompareFunc := @CompareByGenre;
    sTitle: // by title
      CompareFunc := @CompareByTitle;
    sArtist: // by artist
      CompareFunc := @CompareByArtist;
    sFolder: // by folder
      CompareFunc := @CompareByFolder;
    sArtist2: // by artist2
      CompareFunc := @CompareByArtist;
    sLanguage: // by Language
      CompareFunc := @CompareByLanguage;
    sYear: // by Year
      CompareFunc := @CompareByYear;
    sDecade: // by Decade
      CompareFunc := @CompareByYear;
    else
      Log.LogCritical('Unsupported comparison', 'TSongs.Sort');
      Exit; // suppress warning
  end; // case

  // Note: Do not use TList.Sort() as it uses QuickSort which is instable.
  // For example, if a list is sorted by title first and
  // by artist afterwards, the songs of an artist will not be sorted by title anymore.
  // The stable MergeSort guarantees to maintain this order.
  MergeSort(Self.SongList, CompareFunc);
end;

constructor TCatSongs.Create();
begin
  Self.ShowDuets := true;
  Self.ShowCategories := false;
  Self.Sorting := -1;
  Self.VisibleSongs := 0;
end;

procedure TCatSongs.SortSongs();
begin
  case TSortingType(Self.Sorting) of
    sEdition:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sEdition);
      end;
    sGenre:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sGenre);
      end;
    sLanguage:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sLanguage);
      end;
    sFolder:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sFolder);
      end;
    sTitle:
        Songs.Sort(sTitle);
    sArtist:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
      end;
    sArtist2:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist2);
      end;
    sYear:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sYear);
      end;
    sDecade:
      begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sYear);
      end;
  end; // case
end;

{* Find global index of all songs from a index of visible songs subgroup  *}
function TCatSongs.FindGlobalIndex(VisibleIndex:integer): integer;
begin
  if (not Self.IsFilterApplied()) or (Self.GetVisibleSongs() = 0) then
    Result := VisibleIndex
  else
  begin
    Result := -1;
    while VisibleIndex >= 0 do
    begin
      Inc(Result);
      if Self.Song[Result].Visible then
        Dec(VisibleIndex);
    end;
  end;
end;

(* Returns the index of a song in the subset of all visible songs *)
function TCatSongs.FindVisibleIndex(Index: integer): integer;
var
  SongIndex: integer;
begin
  if not Self.IsFilterApplied() then
    Result := Index
  else
  begin
    Result := 0;
    for SongIndex := 0 to Index - 1 do
    begin
      if Self.Song[SongIndex].Visible then
        Inc(Result);
    end;
  end;
end;

{* Returns number of visible songs *}
function TCatSongs.GetVisibleSongs(): integer;
begin
  Result := Self.VisibleSongs;
end;

{* Returns if some filter has been applied to song list *}
function TCatSongs.IsFilterApplied(): boolean;
begin
  Result := Self.VisibleSongs < High(Self.Song) + 1;
end;

{* Sets sorting, show or not songs in categories and/or duets refreshing songs array *}
function TCatSongs.Refresh(Sort: integer; Categories: boolean; Duets: boolean): boolean;
var
  I: integer;
  NewSong, NewCategory: TSong;
  CurCategory, CategoryName, tmpCategory: UTF8String;
begin
  Result := false;
  if (Self.VisibleSongs = 0) or (Self.Sorting <> Sort) or (Self.ShowCategories <> Categories) or (Self.ShowDuets <> Duets) then
  begin
    Result := true;
    Self.Selected := 0;
    Self.Sorting := Sort;
    Self.ShowCategories := Categories;
    Self.ShowDuets := Duets;
    Self.CatCount := 0;
    Self.CatNumShow := -1;
    Self.VisibleSongs := 0;
    Self.SortSongs();
    CurCategory := '';
    SetLength(Self.Song, 0);
    NewCategory := nil;
    for I := 0 to Songs.SongList.Count - 1 do
    begin
      NewSong := TSong(Songs.SongList[I]);
      if Self.ShowDuets or (not NewSong.isDuet) then //add a new song
      begin
        Inc(Self.VisibleSongs);
        if Self.ShowCategories then
        begin
          CategoryName := '';
          case (TSortingType(Self.Sorting)) of
            sEdition:
              if (CompareText(CurCategory, NewSong.Edition) <> 0) then
                CategoryName := NewSong.Edition;
            sGenre:
              if (CompareText(CurCategory, NewSong.Genre) <> 0) then
                CategoryName := NewSong.Genre;
            sLanguage:
              if (CompareText(CurCategory, NewSong.Language) <> 0) then
                CategoryName := NewSong.Language;
            sTitle:
              if (Length(NewSong.TitleNoAccent) > 0) and (UTF8CompareText(CurCategory, NewSong.TitleNoAccent[1]) <> 0) then
                CategoryName := UTF8UpperCase(NewSong.TitleNoAccent[1]);
            sArtist:
              if (Length(NewSong.ArtistNoAccent) > 0) and (UTF8CompareText(CurCategory, NewSong.ArtistNoAccent[1]) <> 0) then
                CategoryName := UTF8UpperCase(NewSong.ArtistNoAccent[1]);
            sFolder:
              if (UTF8CompareText(CurCategory, NewSong.Folder) <> 0) then
                CategoryName := NewSong.Folder;
            sArtist2:
              { this new sorting puts all songs by the same artist into
                a single category }
              if (UTF8CompareText(CurCategory, NewSong.Artist) <> 0) then
                CategoryName := NewSong.Artist;
            sYear:
            begin
               tmpCategory := IfThen(NewSong.Year <> 0, IntToStr(NewSong.Year), '-');
               if (tmpCategory <> CurCategory) then
                 CategoryName := tmpCategory;
             end;
            sDecade:
            begin
              tmpCategory := IfThen(Length(IntToStr(NewSong.Year)) = 4, UTF8Copy(IntToStr(NewSong.Year), 1, 3)+'0', '-');
              if (tmpCategory <> CurCategory) then
                CategoryName := tmpCategory;
            end;
          end;
          if CategoryName <> '' then //add a new category if needed
          begin
            CurCategory := CategoryName;
            Inc(Self.CatCount);
            NewCategory := TSong.Create();
            NewCategory.Artist := CategoryName;
            NewCategory.CatNumber := 0;
            NewCategory.Cover := UCatCovers.CatCovers.GetCover(TSortingType(Self.Sorting), CategoryName);
            NewCategory.Main := true;
            NewCategory.OrderNum := Self.CatCount;
            NewCategory.Visible := true;
            SetLength(Self.Song, Self.VisibleSongs);
            Self.Song[Self.VisibleSongs - 1] := NewCategory;
            Inc(Self.VisibleSongs);
          end;
          Inc(NewCategory.CatNumber);
          NewSong.CatNumber := NewCategory.CatNumber;
          NewSong.OrderNum := Self.CatCount;
          NewSong.Visible := false;
        end
        else
        begin
          NewSong.CatNumber := Self.VisibleSongs;
          NewSong.OrderNum := 0;
          NewSong.Visible := true;
        end;
        NewSong.Main := false;
        SetLength(Self.Song, Self.VisibleSongs);
        Self.Song[Self.VisibleSongs - 1] := NewSong;
      end;
    end;
    UPlaylist.PlayListMan.LoadPlayLists();
  end;
end;

function TCatSongs.SetFilter(FilterStr: UTF8String; Filter: TSongFilter = sfAll): cardinal;
var
  I, J:      integer;
  TmpString: UTF8String;
  WordArray: array of UTF8String;
begin
  Result := 0;
  if FilterStr <> '' then //FIXME required because fails when cancel a search without results
    FilterStr := UCommon.RemoveSpecialChars(FilterStr);

  if FilterStr <> '' then
  begin
    Self.CatNumShow := -2;
    // initialize word array
    SetLength(WordArray, 1);

    // Copy words to SearchStr
    I := Pos(' ', FilterStr);
    while (I <> 0) do
    begin
      WordArray[High(WordArray)] := Copy(FilterStr, 1, I-1);
      SetLength(WordArray, Length(WordArray) + 1);

      FilterStr := TrimLeft(Copy(FilterStr, I+1, Length(FilterStr)-I));
      I := Pos(' ', FilterStr);
    end;

    // Copy last word
    WordArray[High(WordArray)] := FilterStr;

    for I := 0 to High(Song) do
    begin
      if not Song[i].Main then
      begin
        case Filter of
          sfAll:
            TmpString := Song[I].ArtistNoAccent + ' ' + Song[i].TitleNoAccent; //+ ' ' + Song[i].Folder;
          sfTitle:
            TmpString := Song[I].TitleNoAccent;
          sfArtist:
            TmpString := Song[I].ArtistNoAccent;
          else
            TmpString := '';
        end;
        Song[i].Visible := true;
        // Look for every searched word
        for J := 0 to High(WordArray) do
          Song[i].Visible := Song[i].Visible and UTF8ContainsStr(TmpString, WordArray[J]);

        if Song[i].Visible then
          Inc(Result);
      end
      else
        Song[i].Visible := false;
    end
  end
  else
  begin
    Self.CatNumShow := -1;
    for I := 0 to High(Self.Song) do
    begin
      Self.Song[I].Visible := (Self.ShowCategories and Self.Song[I].Main)
        or ((not Self.ShowCategories) and (not Self.Song[I].Main) and (Self.ShowDuets or (not Self.Song[I].IsDuet)));

      if Self.Song[I].Visible then
        Inc(Result);
    end;
  end;
  Self.VisibleSongs := Result;
end;

{* Show songs of a category *}
function TCatSongs.ShowCategory(Index: integer): integer;
var
  I: integer;
begin
  Result := 0;
  Self.CatNumShow := Index;
  Self.VisibleSongs := 0;
  for I := 0 to High(Self.Song) do
  begin
    Self.Song[I].Visible := false;
    if Self.Song[I].OrderNum = Index then
      if Self.Song[I].Main then
      begin
        Result := I;
        Self.VisibleSongs := Self.Song[I].CatNumber
      end
      else
        Self.Song[I].Visible := true
  end
end;

{* Show songs of a playlistt *}
procedure TCatSongs.ShowPlaylist(Index: integer);
var
  I: integer;
begin
  Self.CatNumShow := -3;
  Self.VisibleSongs := Length(UPlaylist.PlayListMan.PlayLists[Index].Items);

  for I := 0 to High(Self.Song) do
    Self.Song[I].Visible := false;

  for I := 0 to Self.VisibleSongs - 1 do
    Self.Song[UPlaylist.PlayListMan.PlayLists[Index].Items[I].SongID].Visible := true;
end;

end.
