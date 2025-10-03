UNIT AiClientEx;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   Higher level functions
-------------------------------------------------------------------------------------------------------------}

INTERFACE
USES
   System.JSON, System.SysUtils, System.IOUtils, System.Generics.Collections,
   AiHistory, AiClient, AiLLM;

TYPE
  TContentFileParts= TObjectList<TJSONObject>;

  TAiClientEx = class(TAiClient)
  private
    // JSON SYSTEM
    function file2JsonObj         (CONST FilePath: string): TJSONObject;
    function makeGenerationConfig (CONST FilePath: string ): TJSONPair;

    // JSON CONTENTS
    function makeContentsSingleTurn (TextPart: TJSONObject; InputFiles: TChatParts; Role: TChatRole): TJsonPair;
    function makeFileDataParts      (InputFiles: TChatParts): TContentFileParts;
  protected
    function addTurns2Contents(CallJsonBody: TJSONObject; TextPart: TJSONObject; Role: TChatRole): Boolean;
  public
    constructor Create; override;
    destructor Destroy; override;

    function SendAPICall(TextPart: TJSONObject; InputFiles: TChatParts; Schema: string; JsonShortName: string; SysInstr: TJSONPair): TAIResponse;
  end;


function MakeTextPart(const TextPrompt: String): TJSONObject;


IMPLEMENTATION
USES
   AiUtils, LightCore.AppData;



constructor TAiClientEx.Create;
begin
  inherited Create;
end;


destructor TAiClientEx.Destroy;
begin
  inherited;
end;




{-------------------------------------------------------------------------------------------------------------
   MAIN
-------------------------------------------------------------------------------------------------------------}
// SaveJsonFile is the file where we save the Json for inspections or to be loaded later. It must be short file name (no path, no extenstion)!
function TAiClientEx.SendAPICall(TextPart: TJSONObject; InputFiles: TChatParts; Schema: string; JsonShortName: string {todo: add here LLM.Temperature, etc}; SysInstr: TJSONPair): TAIResponse;
var
  Contents: TJSONPair;
  LLMConfig  : TJSONPair;
  BodyJSON: TJSONObject;
begin
  Contents := nil;
  LLMConfig:= nil;
  BodyJSON := nil;
  AppDataCore.RamLog.AddVerb('SendAPICall for Schema: '+ Schema);

  TRY
    // Prepare parameters
    Contents := makeContentsSingleTurn(TextPart, InputFiles, TChatRole.crUser);
    LLMConfig:= makeGenerationConfig(Schema); // LLM configuration

    // Creates the JSON part of the APIcall to AI.
    // The input JsonPairs should be freed separately
    BodyJSON:= TJSONObject.Create;
    BodyJSON.AddPair(TJSONPair(SysInstr.Clone));   //ToDo 5 -oGabi: Should be ok if we don't free this here so we don't need to clone the objects.
    BodyJSON.AddPair(TJSONPair(Contents.Clone));
    BodyJSON.AddPair(TJSONPair(LLMConfig.Clone));

    // Make API call
    Result:= postHttpRequest(BodyJSON);

    // Log errors
    PrintError(Result.ErrorMsg);

    // Save output
    if Result.Valid
    then SaveAiResponse(JsonShortName, Result.ExtractedJSONObj.ToString)    // Save JSON to disk
  FINALLY
    FreeAndNil(BodyJSON);     // BodyJSON owns the cloned pairs, so freeing it will free the cloned content
    FreeAndNil(Contents);
    FreeAndNil(LLMConfig);
  END;
end;





{-------------------------------------------------------------------------------------------------------------
   JSON CONTENTS
-------------------------------------------------------------------------------------------------------------}

// Makes the uploaded file part for Contents
function TAiClientEx.makeFileDataParts(InputFiles: TChatParts): TContentFileParts;

  function makeFileDataPart(const MimeType, FileUri: string): TJSONObject;
  begin
     var Value:= TJSONObject.Create;
     Value.AddPair('mimeType', MimeType);
     Value.AddPair('fileUri' , FileUri);   // Example: 'https://generativelanguage.googleapis.com/v1beta/files/ouss1rakhp8a'

     var FileDataPair := TJsonPair.Create('fileData', Value);
     Result:= TJSONObject.Create(FileDataPair);
  end;

begin
  Assert(InputFiles <> NIL, 'MakeFileDataParts: InputFiles is NIL');

  Result:= TContentFileParts.Create(True); // Own objects
  for var FilePart in InputFiles do
    if FilePart.FileUri > '' then
     begin
       VAR JSON:= makeFileDataPart(Extension2MimeType(FilePart.Path), FilePart.FileUri);
       Result.Add(JSON);
     end;
    ///else AppDataCore.RamLog.AddError('CRITICAL: File does not have URI!'+ FilePart.Path);
end;




// makeContents4SingleTurnConversations
// create the Contents object for single turn conversations, with or without uploaded files
// the returned JSON Pair can be used in function AddTurns2Contents4MultiTurnConversations to add more turns to Contents the input JSON Objects should be freed separately
function TAiClientEx.makeContentsSingleTurn(TextPart: TJSONObject; InputFiles: TChatParts; Role: TChatRole): TJsonPair;
VAR
  ListFileDataParts: TContentFileParts;
  PartsArray: TJSONArray;
  SingleTurnContents: TJSONObject;
  ContentsArray: TJSONArray;
  TextPartClone: TJSONObject;
begin
  PartsArray := TJSONArray.Create; // Will be freed by SingleTurnContents

  if Assigned(InputFiles) then
  begin
    ListFileDataParts:= MakeFileDataParts(InputFiles);   // First attach the files (IF ANY)
    try
      for var FileData in ListFileDataParts do
      begin
        // Clone the FileData object to avoid ownership issues
        var ClonedFileData := FileData.Clone as TJSONObject;
        PartsArray.AddElement(ClonedFileData);
      end;
    finally
      // Free the list and its contents since we've cloned everything we need
      FreeAndNil(ListFileDataParts);
    end;
  end;

  // Clone the TextPart to avoid ownership conflicts
  TextPartClone := TextPart.Clone as TJSONObject;  //todo 5 -oGabi: don't close this. this means that its caller won't have to free it anymore because we (Result) free it.
  PartsArray.AddElement(TextPartClone);

  // Create the single turn contents object
  SingleTurnContents := TJSONObject.Create;
  SingleTurnContents.AddPair('role', RoleToStr(Role));
  SingleTurnContents.AddPair('parts', PartsArray);

  // Create the contents array
  ContentsArray := TJSONArray.Create;
  ContentsArray.AddElement(SingleTurnContents);

  Result:= TJSONPair.Create('contents', ContentsArray);
end;


// addTurns2Contents4MultiTurnConversations
// UNUSED!
//
// adds new (text) turns to the Contents part of an JSONBody from API Call
// the input JSonObjects should be freed separately
function TAiClientEx.addTurns2Contents(CallJsonBody: TJSONObject; TextPart: TJSONObject; Role: TChatRole): Boolean;
var
  PartsArray: TJSONArray;
  TextPartClone: TJSONObject;
  SingleTurnContents: TJSONObject;
  ContentsArray: TJSONArray;
begin
  // prepare the JSON object for the new turn
  PartsArray := TJSONArray.Create;

  // Clone the TextPart to avoid ownership issues
  TextPartClone := TextPart.Clone as TJSONObject;
  PartsArray.AddElement(TextPartClone);

  SingleTurnContents := TJSONObject.Create;
  SingleTurnContents.AddPair('role', RoleToStr(Role));
  SingleTurnContents.AddPair('parts', PartsArray);

  // Add the SingleTurn to the contentsarray
  ContentsArray:= CallJsonBody.GetValue<TJSONArray>('contents');
  Result:= Assigned(ContentsArray);
  if Result
  then ContentsArray.AddElement(SingleTurnContents)
  else FreeAndNil(SingleTurnContents); // If we can't find the contents array, free the objects we created
end;




{-------------------------------------------------------------------------------------------------------------
   JSON GenConfig
-------------------------------------------------------------------------------------------------------------}

function TAiClientEx.file2JsonObj(const FilePath: String): TJSONObject;
var
  JsonFileContent: string;
  JsonValue: TJSONValue;
begin

  if not TFile.Exists(FilePath)
  then RAISE Exception.CreateFmt('JSON file not found: %s', [FilePath]);

  try
    JsonFileContent := TFile.ReadAllText(FilePath);

    // Parse the JSON and ensure it's an object
    JsonValue := TJSONObject.ParseJSONValue(JsonFileContent);
    if NOT Assigned(JsonValue)
    then RAISE Exception.CreateFmt('Invalid JSON in file: %s', [FilePath]);

    if NOT (JsonValue is TJSONObject) then
    begin
      FreeAndNil(JsonValue);
      RAISE Exception.CreateFmt('JSON file does not contain an object: %s', [FilePath]);
    end;

    Result := JsonValue as TJSONObject;
  except
    on E: Exception do
    begin
      if Assigned(JsonValue)
      then FreeAndNil(JsonValue);
      RAISE Exception.CreateFmt('Error parsing JSON file %s: %s', [FilePath, E.Message]);
    end;
  end;
end;


function TAiClientEx.makeGenerationConfig(CONST FilePath: String): TJSONPair;
VAR
  ResponseSchema: TJSONObject;
  GenerationConfigObj: TJSONObject;
  ThinkingConfig25: TJSONObject;
CONST
  ResponseMimeType = 'application/json';
begin
  ResponseSchema     := nil;
  ThinkingConfig25   := NIL;
  GenerationConfigObj:= nil;

  TRY
    ResponseSchema := File2JsonObj(FilePath);              // Transfer ownership to the pair, so don't free this object here

    // This is only for Gemini 2.5
    ThinkingConfig25 := TJSONObject.Create;                // Transfer ownership to the pair, so don't free this object here
    ThinkingConfig25.AddPair('thinkingBudget', 0);
    ThinkingConfig25.AddPair('includeThoughts', FALSE);

    // This is for both 2.0 and 2.5
    GenerationConfigObj := TJSONObject.Create;             // Transfer ownership to the pair, so don't free this object here
    GenerationConfigObj.AddPair('responseMimeType', ResponseMimeType);
    GenerationConfigObj.AddPair('responseSchema',   ResponseSchema);
    GenerationConfigObj.AddPair('candidateCount',   LLM.CandidateCnt);
    GenerationConfigObj.AddPair('maxOutputTokens',  LLM.MaxTokens);
    GenerationConfigObj.AddPair('temperature',      LLM.Temperature);
    GenerationConfigObj.AddPair('topP',             LLM.TopP);
    GenerationConfigObj.AddPair('topK',             LLM.TopK);
    GenerationConfigObj.AddPair('thinkingConfig',   ThinkingConfig25);

    Result:= TJSONPair.Create('generationConfig', GenerationConfigObj);
  EXCEPT
    FreeAndNil(ResponseSchema);
    FreeAndNil(ThinkingConfig25);
    FreeAndNil(GenerationConfigObj);
    RAISE;
  END;
end;


// Makes the text part for Contents
function MakeTextPart(const TextPrompt: String): TJSONObject;
begin
  VAR Pair:= TJsonPair.Create('text', TextPrompt);
  Result:= TJSONObject.Create(Pair);
end;


end.
