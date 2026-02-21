UNIT JsonUtils;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   General JSON functions
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES
   System.JSON, System.SysUtils;


function File2Json   (const FilePath  : String): TJSONObject;
function MakeTextPart(const TextPrompt: String): TJSONObject;


IMPLEMENTATION
USES
  LightCore.TextFile;



// Reads and parses a JSON file from disk and returns a JSON object.
function File2Json(const FilePath: String): TJSONObject;
var
  JsonContent: string;
  JsonValue: TJSONValue;
begin
  // The program crashes in HTTP request if resource file not found, so we check if files are found BEFORE we send the request.
  if NOT FileExists(FilePath) then
    RAISE Exception.Create('Schema file not found: ' + FilePath + sLineBreak + 'If running in development mode, ensure the Resources/API_call folder exists.');

  JsonContent:= StringFromFile(FilePath);

  // Parse the JSON and ensure it's an object
  JsonValue:= TJSONObject.ParseJSONValue(JsonContent);

  if JsonValue = NIL
  then RAISE Exception.Create('Invalid JSON in file: ' + FilePath);

  if NOT (JsonValue is TJSONObject) then
    begin
      JsonValue.Free;
      RAISE Exception.Create('JSON file does not contain an object: ' + FilePath);
    end;

  Result:= TJSONObject(JsonValue);
end;


// Makes the text object
function MakeTextPart(const TextPrompt: String): TJSONObject;
begin
  VAR Pair:= TJsonPair.Create('text', TextPrompt);
  Result:= TJSONObject.Create(Pair);
end;


end.
