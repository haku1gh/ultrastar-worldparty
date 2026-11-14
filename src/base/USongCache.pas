{*
    UltraStar WorldParty - Karaoke Game

    Song cache: stores the header data of all songs in a SQLite database
    so that the song directories do not have to be scanned and parsed on
    every program start.

    NOTE: the notes/lines of a song (TSong.Lines) are NOT stored. They are
    loaded by TSong.Analyse() when a song is really needed (singing, editor).
 *}

unit USongCache;

interface

{$MODE OBJFPC}

{$I switches.inc}

uses
  Classes,
  SysUtils,
  SQLiteTable3;

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

implementation

uses
  UPath,
  UPathUtils,
  USong,
  UTextEncoding;

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
end;

end.
