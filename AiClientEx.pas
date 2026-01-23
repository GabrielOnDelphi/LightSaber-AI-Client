UNIT AiClientEx;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   Higher level functions
-------------------------------------------------------------------------------------------------------------}

INTERFACE
USES
   System.JSON, System.SysUtils, System.Generics.Collections,
   AiHistory, AiClient;

TYPE
  TContentFileParts= TObjectList<TJSONObject>;

  TAiClientEx = class(TAiClient)
  private
    // JSON CONTENTS
    function makeContentsSingleTurn (TextPart: TJSONObject; InputFiles: TChatParts; Role: TChatRole): TJsonPair;
    function makeFileDataParts      (InputFiles: TChatParts): TContentFileParts;
  protected
    function addTurns2Contents(CallJsonBody: TJSONObject; TextPart: TJSONObject; Role: TChatRole): Boolean;
  public
    constructor Create; override;

    function SendAPICall(TextPart: TJSONObject; InputFiles: TChatParts; Schema: string; JsonShortName: string; SysInstr: TJSONPair): TAIResponse;
  end;



IMPLEMENTATION
USES
   LightCore.Types, AiUtils, LightCore.AppData;



constructor TAiClientEx.Create;
begin
  inherited Create;
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

    // Make API call (one per section)
    Result:= postHttpRequest(BodyJSON);

    // Log errors
    PrintError(Result.ErrorMsg);

    // Save output
    //Note: the loading is happening in TItemLesson.StartMakeQuestionsAI, based on the Sw_LoadJsonSectionsFromFile constant
    if Result.Valid
    then SaveAiResponse(JsonShortName, Result.ExtractedJSONObj.ToString)    // Save JSON to disk
  FINALLY
    FreeAndNil(BodyJSON);     // BodyJSON owns the cloned pairs, so freeing it will free the cloned content
    FreeAndNil(LLMConfig);
    FreeAndNil(Contents);
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

  Result:= TContentFileParts.Create(OwnObjects);
  for var FilePart in InputFiles do
    if FilePart.FileUri > '' then
     begin
       VAR JSON:= makeFileDataPart(Extension2MimeType(FilePart.FileName), FilePart.FileUri);
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
  TextPartClone:= TextPart.Clone as TJSONObject;
 {The Clone is CORRECT and should be kept.

  1. Ownership conflict prevention: When TextPart is passed into makeContentsSingleTurn, the caller owns it.
     If you add it directly to Result (the JSON array), then Result would also claim ownership when it's freed.
  2. Double-free scenario: Without the Clone:
    - Caller creates TextPart
    - Function adds TextPart to Result
    - Caller frees TextPart (as they own it) ? First free
    - Later, Result is freed and tries to free TextPart ? Second free = CRASH
  3. Current correct flow:
    - Caller creates TextPart and passes it
    - Function clones it -> TextPartClone is a new independent object
    - TextPartClone gets added to Result -> Result owns the clone
    - Caller frees their original TextPart ? No problem
    - Result frees TextPartClone when destroyed ? No problem }

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



// adds new (text) turns to the Contents part of an JSONBody from API Call
// the input JSonObjects should be freed separately
function TAiClientEx.addTurns2Contents(CallJsonBody: TJSONObject; TextPart: TJSONObject; Role: TChatRole): Boolean;  // UNUSED! To be used in uPromts.pas
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


end.
