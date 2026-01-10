UNIT AIUtils;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   General functions
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES
  //posix.UniStd,
  System.SysUtils, System.Types;


// Log
function  PrintError(ErrMsg: string): Boolean;

// Mime
function  Extension2MimeType(const FilePath: string): string;
function  ExtensionFromMimeType(const MimeType: string): string;

// JSON
procedure SaveAiResponse       (CONST SchemaName, Text: string);
procedure DeleteResponseFile   (CONST SchemaName: string);
procedure DeleteResponseFiles  (CONST SchemaName: string);
function  GetBackupJsonFullName(CONST SchemaName: string; AppendDate: Boolean= FALSE): string;


// Gemini specific
procedure Rescale(var BoundBox: TRectF; aWidth, aHeight: integer);



IMPLEMENTATION
USES
  LightCore.AppData, LightCore.TextFile, LightCore.IO;


{-------------------------------------------------------------------------------------------------------------
   LOG
-------------------------------------------------------------------------------------------------------------}

// If the ErrMsg is not empty, returns true AND shows the error in the log
function PrintError(ErrMsg: string): Boolean;
begin
  Result:= ErrMsg <> '';
  if Result
  then AppDataCore.RamLog.AddError(ErrMsg);
end;


{-------------------------------------------------------------------------------------------------------------
   AI JSON RESPONSES - SAVE TO DISK
-------------------------------------------------------------------------------------------------------------}
function GetBackupJsonFullName(CONST SchemaName: string; AppendDate: Boolean= FALSE): string;
begin
  if AppDataCore.RunningHome
  then Result:= AppDataCore.AppFolder
  else Result:= AppDataCore.AppDataFolder;

  Result:= Result+ Trail('AI Answers') + SchemaName;

  if AppendDate
  then Result:= Result+ ' - ' + DateTimeToStr_IO;

  Result:= Result+'.Json';
end;


procedure SaveAiResponse(CONST SchemaName, Text: string); // Note: the loading is happening in TItemLesson.StartMakeQuestionsAI, based on the Sw_LoadJsonSectionsFromFile constant
begin
  if AppDataCore.RunningHome
  then StringToFile(GetBackupJsonFullName(SchemaName), Text);
end;


procedure DeleteResponseFile(CONST SchemaName: string);
begin
  if AppDataCore.RunningHome
  then DeleteFile(GetBackupJsonFullName(SchemaName));
end;


// Clean up old question files before generating new ones
procedure DeleteResponseFiles(CONST SchemaName: string);
begin
  for VAR i:= 0 to 40 do                                    // Delete up to 40 old question files (40 sections should be more than enough)
    begin
      VAR JsonFileName:= SchemaName+ IntToStr(i);
      DeleteResponseFile(JsonFileName);
    end;
end;





{-------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------}
// This is for Gemini images
procedure Rescale(var BoundBox: TRectF; aWidth, aHeight: integer);
begin
  BoundBox.Left   := round((BoundBox.Left   / 1000) * aWidth);
  BoundBox.Right  := round((BoundBox.Right  / 1000) * aWidth);
  BoundBox.Top    := round((BoundBox.Top    / 1000) * aHeight);
  BoundBox.Bottom := round((BoundBox.Bottom / 1000) * aheight);
end;





{-------------------------------------------------------------------------------------------------------------
   MIME
-------------------------------------------------------------------------------------------------------------}

// Determines the MIME type of a file based on its extension
function Extension2MimeType(const FilePath: string): string;
begin
  var Ext:= LowerCase(ExtractFileExt(FilePath));

  if Ext = '.txt'  then Result := 'text/plain' else
  if Ext = '.md'   then Result := 'text/markdown' else
  if Ext = '.pdf'  then Result := 'application/pdf' else
  if Ext = '.jpg'  then Result := 'image/jpeg' else
  if Ext = '.jpeg' then Result := 'image/jpeg' else
  if Ext = '.png'  then Result := 'image/png' else
  if Ext = '.gif'  then Result := 'image/gif'

  else Result := 'application/octet-stream'; // Default to octet-stream for unknown types
end;


// Determines the file extension based on a given MIME type
function ExtensionFromMimeType(const MimeType: string): string;
begin
  if MimeType = 'text/plain'      then Result := '.txt' else
  if MimeType = 'text/markdown'   then Result := '.md'  else
  if MimeType = 'application/pdf' then Result := '.pdf' else
  if MimeType = 'image/jpeg'      then Result := '.jpg' else
  if MimeType = 'image/png'       then Result := '.png' else
  if MimeType = 'image/gif'       then Result := '.gif'
  else Result := '';
end;


end.
