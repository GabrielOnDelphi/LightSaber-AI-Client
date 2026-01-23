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

TYPE
  { File categories for UI thumbnail display and AI processing.
    Note: This only affects how we display the preview thumbnail in the UI.
    All file types are sent to Gemini as cptFileData - the AI handles format internally based on MIME type. }
  TFileCategory = (
    fcImage,       // PNG, JPG, GIF - display the actual image as thumbnail
    fcText,        // TXT, MD - display TextThumb.png placeholder
    fcDocument);   // PDF, RTF, DOC, DOCX - display DataThumb.png placeholder (future)

// Log
function  PrintError(ErrMsg: string): Boolean;

// File category
function  GetFileCategory(const FilePath: string): TFileCategory;
function  IsImageFile(const FilePath: string): Boolean;
function  IsTextFile(const FilePath: string): Boolean;

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
   FILE CATEGORY DETECTION
   Determines how to display the file in UI (thumbnail type) and helps with AI processing decisions.
   Note: All files go to Gemini as cptFileData - this is purely for UI thumbnail selection.
-------------------------------------------------------------------------------------------------------------}
function GetFileCategory(const FilePath: string): TFileCategory;
VAR Ext: string;
begin
  Ext:= LowerCase(ExtractFileExt(FilePath));

//todo 1: I have my own function
  // Images - can be displayed directly as thumbnails
  if (Ext = '.png') OR (Ext = '.jpg') OR (Ext = '.jpeg') OR (Ext = '.gif') OR (Ext = '.bmp') OR (Ext = '.webp')
  then EXIT(fcImage);

  // Text files - show generic "TEXT" thumbnail, but send actual content to AI
  // WARNING: Gemini 2.5 has a bug where 'text/markdown' MIME type is rejected (works in 2.0 Flash).
  // See: https://discuss.ai.google.dev/t/unsupported-mime-type-text-md/83918
  // Workaround: Use 'text/plain' for .md files, or upgrade to a model version that supports it.
  if (Ext = '.txt') OR (Ext = '.md')
  then EXIT(fcText);

  // Documents - show generic "DATA" thumbnail (future: PDF, RTF, Word)
  // These are sent to Gemini as-is; the API handles them based on MIME type
  if (Ext = '.pdf') OR (Ext = '.rtf') OR (Ext = '.doc') OR (Ext = '.docx')
  then EXIT(fcDocument);

  // Default: treat as document (safest for unknown types)
  Result:= fcDocument;
end;


function IsImageFile(const FilePath: string): Boolean;
begin
  Result:= GetFileCategory(FilePath) = fcImage;
end;


function IsTextFile(const FilePath: string): Boolean;
begin
  Result:= GetFileCategory(FilePath) = fcText;
end;


{-------------------------------------------------------------------------------------------------------------
   AI JSON RESPONSES - SAVE TO DISK
-------------------------------------------------------------------------------------------------------------}
function GetBackupJsonFullName(CONST SchemaName: string; AppendDate: Boolean= FALSE): string;
begin
  {$IFDEF MsWindows}
    Result:= AppDataCore.AppFolder;  // The resources are in executable's folder
  {$ELSE}
    Result:= AppDataCore.AppDataFolder;  // The resources are deployed by the Deployment Manager
  {$ENDIF}

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
// This specific for Gemini images
// Rescale bounding box from 0-1000 normalized coordinates to actual pixel coordinates
procedure Rescale(var BoundBox: TRectF; aWidth, aHeight: integer);
begin
  BoundBox.Left   := round((BoundBox.Left   / 1000) * aWidth);
  BoundBox.Right  := round((BoundBox.Right  / 1000) * aWidth);
  BoundBox.Top    := round((BoundBox.Top    / 1000) * aHeight);
  BoundBox.Bottom := round((BoundBox.Bottom / 1000) * aheight);
end;





{-------------------------------------------------------------------------------------------------------------
   MIME

   KNOWN ISSUE - Gemini 2.5 text/markdown bug:
   Gemini 2.5 rejects 'text/markdown' MIME type with "Unsupported MIME type" error.
   The same files work fine with Gemini 2.0 Flash.
   See: https://discuss.ai.google.dev/t/unsupported-mime-type-text-md/83918

   Possible workarounds:
   1. Use 'text/plain' for .md files (loses markdown semantic info but content still readable)
   2. Wait for Google to fix the bug in Gemini 2.5
   3. Use Gemini 2.0 Flash for markdown files

   Current behavior: Returns 'text/markdown' - if you encounter issues, consider using text/plain instead.
-------------------------------------------------------------------------------------------------------------}

// Determines the MIME type of a file based on its extension
function Extension2MimeType(const FilePath: string): string;
begin
  var Ext:= LowerCase(ExtractFileExt(FilePath));

  if Ext = '.txt'  then Result := 'text/plain' else
  if Ext = '.md'   then Result := 'text/markdown' else         // WARNING: Gemini 2.5 may reject 'text/markdown'. See comment above. If issues occur, change to 'text/plain' as a workaround.
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
