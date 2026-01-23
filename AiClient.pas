UNIT AiClient;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   Makes a Post Http Request to a LLM.
   The actual LLM is represented by the TLLMObject.
   (Low level code)

   ToDo 6: In case of TimeOuts: Implement retry logic with exponential backoff for transient failures. OR use generateContentStream instead of generateContent for large responses  OR  Consider breaking down very large prompts into smaller chunks
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES
  System.SysUtils, System.Classes, System.Net.HttpClient, System.Net.HttpClientComponent, System.StrUtils,
  System.JSON, System.Generics.Collections, System.Rtti, System.IOUtils, System.TypInfo,
  LightCore.StreamBuff, AiHistory, AiLLM;

TYPE
  // Record to hold the structured response from the Gemini API
  TAIResponse = class
   private
     FHttpStatus: Integer;
     FSafetyRatings: TJSONArray;   // Raw JSON array for safety ratings
     FExtractedJSONObj: TJSONObject;
   public
     // Tokens for this specific prompt
     TokensPrompt   : Integer;      // The number of tokens in your request (contents).
     TokensCandidate: Integer;      // The number of tokens in the model's response (candidates).
     TokensTotal    : Integer;      // The sum of both, representing the total tokens used for the API call.
     ErrorMsg: string;              // Detailed error for logging. Empty for 'ok'
     property ExtractedJSONObj: TJSONObject read FExtractedJSONObj;
     destructor Destroy; override;
     function Valid: Boolean;
  end;


  // Client for interacting with AI APIs
  TAiClient = class
  private
    CONST ClassSignature: AnsiString= 'TAiClient';
    function  finishReason2String(FinishReason: string): string;
    function  getHttpErrorMessage(StatusCode: Integer): string;
    function  detectErrorType(Response: string): string;
    procedure uploadFile(InputPart: TChatPart);

    procedure Load(Stream: TLightStream);   overload;
    procedure Save(Stream: TLightStream);   overload;
  protected
    function postHttpRequest(BodyJSON: TJSONObject): TAIResponse; // Optional: Max tokens in response
    function makeGenerationConfig(const FilePath: String): TJSONPair;
  public
    LLM: TLLMObject;
    TokensTotal: Integer;    // Total used tokens for ALL prompts
    Timeout: Integer;        // HTTP timeout in milliseconds (connection and response)

    constructor Create; virtual;
    destructor  Destroy; override;
    function TestConnection: TAIResponse;

    procedure UploadFiles(InputFiles: TChatParts);
    procedure Load(FileName: string);  overload;
    procedure Save(FileName: string);  overload;
  end;



IMPLEMENTATION
USES
  JsonUtils, AiLLMGemini, AiUtils, LightCore.AppData;



{-------------------------------------------------------------------------------------------------------------
   TAIResponse
-------------------------------------------------------------------------------------------------------------}
destructor TAIResponse.Destroy;
begin
  FreeAndNil(FSafetyRatings);
  FreeAndNil(FExtractedJSONObj);
  inherited;
end;


function TAIResponse.Valid: Boolean;
begin
  Result:= (ErrorMsg = '') AND Assigned(ExtractedJSONObj) AND (ExtractedJSONObj.Count > 0);
end;



{-------------------------------------------------------------------------------------------------------------
   TAiClient
-------------------------------------------------------------------------------------------------------------}
constructor TAiClient.Create;
begin
  inherited Create;
  LLM:= TLLMGemini.Create;  //ToDo 5: Let the user choose the LLM.
  Timeout:= 300000;         // Default: 300 seconds (5 min) to match Gemini server-side limit
  Load(AppDataCore.AppDataFolder+ 'AiClient.bin');
end;


destructor TAiClient.Destroy;
begin
  Save(AppDataCore.AppDataFolder+ 'AiClient.bin');
  FreeAndNil(LLM);
  inherited;
end;






{-------------------------------------------------------------------------------------------------------------
   ERROR HANDLING HELPERS
-------------------------------------------------------------------------------------------------------------}

function TAiClient.getHttpErrorMessage(StatusCode: Integer): string;  //ToDo 4: these errors are specific to Gemini. Move them these
begin
  case StatusCode of
    400: Result := 'Bad request - please check your input parameters';
    401: Result := 'Unauthorized - please check your API key';
    403: Result := 'Forbidden - your API key may not have sufficient permissions';
    404: Result := 'Not found - the requested resource does not exist';
    429: Result := 'Quota limit exceeded - please try again later';
    500: Result := 'Internal server error - please try again';
    502,
    503: Result := 'Service temporarily unavailable - please try again later';
    else Result := Format('HTTP error %d occurred', [StatusCode]);
  end;
end;


function TAiClient.detectErrorType(Response: string): string;
begin
  // Prioritize specific, content-based errors first
  if ContainsText(Response, 'safety')  or ContainsText(Response, 'blocked')    then Result := 'Safety Error' else
  if ContainsText(Response, 'parse')   or ContainsText(Response, 'json')       then Result := 'Parsing Error' else
  if ContainsText(Response, 'network') or ContainsText(Response, 'connection') then Result := 'Network Error';
end;


{-------------------------------------------------------------------------------------------------------------
   UPLOAD FILE(S)
-------------------------------------------------------------------------------------------------------------}

// Uploads all files
procedure TAiClient.UploadFiles(InputFiles: TChatParts);
VAR InputPart: TChatPart;
begin
  for VAR i:= 0 to InputFiles.Count-1 do
    begin
      InputPart:= InputFiles[i];
      if TFile.Exists(InputPart.FileName)
      then uploadFile(InputPart)                           // UPLOAD
      else AppDataCore.RamLog.AddWarn('File not found: '+ InputPart.FileName);
    end;
end;


// Uploads a single file to the AI Files API, returning its URI
procedure TAiClient.uploadFile(InputPart: TChatPart);
var
  HttpClient : TNetHTTPClient;
  Request    : TNetHTTPRequest;
  Response   : IHTTPResponse;
  SessionURL : string;
  BodyStream : TStringStream;
  FileData   : TBytes;
  DataStream : TBytesStream;
  JSONResp   : TJSONObject;
  FileObj    : TJSONValue;
begin
  JSONResp   := NIL;
  DataStream := NIL;
  Request    := NIL;
  HttpClient := NIL;

  try
    HttpClient := TNetHTTPClient.Create(nil);
    HttpClient.ConnectionTimeout:= Timeout;
    HttpClient.ResponseTimeout:= Timeout;
	
    Request    := TNetHTTPRequest.Create(nil);
    Request.Client:= HttpClient;

    //------------------------------------------------
    //  Step 1: Initiate resumable Upload Session
    //------------------------------------------------

    // Generate a unique display name for the uploaded file
    VAR DisplayName:= ExtractFileName(InputPart.FileName) + '-' + Copy(GUIDToString(TGUID.NewGuid),2,20);
    VAR StreamName:= '{"file":{"display_name":"'+DisplayName+'"}}';

    BodyStream := TStringStream.Create(StreamName, TEncoding.UTF8);     // JSON body for initiating the upload
    try
      // Set headers required for starting a resumable upload
      Request.CustomHeaders['X-Goog-Upload-Protocol']              := 'resumable';
      Request.CustomHeaders['X-Goog-Upload-Command']               := 'start';
      Request.CustomHeaders['X-Goog-Upload-Header-Content-Length'] := IntToStr(TFile.GetSize(InputPart.FileName));
      Request.CustomHeaders['X-Goog-Upload-Header-Content-Type']   := Extension2MimeType(InputPart.FileName);
      Request.CustomHeaders['Content-Type']                        := 'application/json';

      Response:= Request.Post(LLM.StartUploadURL, BodyStream);
    finally
      FreeAndNil(BodyStream);
    end;

    if Response = NIL then
      begin
        AppDataCore.RamLog.AddError('No POST response for upload!');
        EXIT;
      end;
    if Response.StatusCode <> 200 then
      begin
        AppDataCore.RamLog.AddError('Failed to upload file data. Status: '+ IntToStr(Response.StatusCode)+'. Body: '+ Response.ContentAsString);
        EXIT;
      end;

    // Session URL
    SessionURL:= Response.GetHeaderValue('X-Goog-Upload-Url');
    if SessionURL = '' then
    begin
      AppDataCore.RamLog.AddError('Failed to get X-Goog-Upload-Url from start response.');
      Exit;
    end else AppDataCore.RamLog.AddVerb('Upload session initiated. URL: '+ SessionURL);

    //------------------------------------------------
    //  Step 2: Upload File Data and Finalize
    //------------------------------------------------
    FileData   := TFile.ReadAllBytes(InputPart.FileName);   //ToDo 1: CRITICAL: we don't read from disk. The input file is now embedded into our stream! The question is, where do we actually load the content of the input file (png/pdf) into our stream? In LessonWizzardSetup?
    DataStream := TBytesStream.Create(FileData);

    // No need to clear CustomHeaders here; new values will override or add.
    Request.CustomHeaders['X-Goog-Upload-Offset']  := '0';                          // Starting from offset 0 for the whole file
    Request.CustomHeaders['X-Goog-Upload-Command'] := 'upload, finalize';           // Upload and finalize in one go
    Request.CustomHeaders['Content-Type']          := Extension2MimeType(InputPart.FileName); // Content type of the file data
    // Note: TNetHTTPRequest automatically sets Content-Length from the stream size for POST requests

    Response:= Request.Post(SessionURL, DataStream);
    if Response = NIL then
      begin
        AppDataCore.RamLog.AddError('No POST response from AI!');
        EXIT;
      end;
    if Response.StatusCode <> 200 then
      begin
        AppDataCore.RamLog.AddError('Failed to upload file data. Status: '+ IntToStr(Response.StatusCode)+'. Body: '+ Response.ContentAsString);
        EXIT;
      end;

    // Extract the file URI from the response
    JSONResp:= TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
    if JSONResp.TryGetValue('file', FileObj) and (FileObj is TJSONObject)
    then
      begin
        InputPart.FileUri:= (FileObj as TJSONObject).GetValue<string>('uri');   //ToDo 5 -oCR: C2C: When do we release the files from the server??? Are they self-deleted?
        AppDataCore.RamLog.AddVerb('File uploaded successfully. URI: '+ InputPart.FileUri);
      end
    else
      AppDataCore.RamLog.AddError('File URI not found in upload response: '+ Response.ContentAsString);

  finally
    // Release Response interface BEFORE destroying HttpClient to avoid use-after-free
    Response := nil;
    FreeAndNil(JSONResp);
    FreeAndNil(DataStream);
    FreeAndNil(Request);
    FreeAndNil(HttpClient);
  end;
end;


// Primary function to send chat history and parameters to the Gemini generateContent API
function TAiClient.postHttpRequest(BodyJSON: TJSONObject): TAIResponse;
VAR
  FinishReason: string;
  ExtractedText: string;
  ContentJson: TJSONArray;
  Candidates : TJSONArray;
  SafetyArr  : TJSONArray;
  RespJSON   : TJSONObject;
  Candidate  : TJSONObject;
  ContentObj : TJSONObject;
  Part0      : TJSONObject;
  HttpClient : TNetHTTPClient;
  Request    : TNetHTTPRequest;
  HttpResponse: IHTTPResponse;
  RequestBody: TStringStream;
  UsageMetadata: TJSONObject;
begin
  HttpClient := NIL;
  Request    := NIL;
  RespJSON   := NIL;
  RequestBody:= NIL;
  AppDataCore.RamLog.AddVerb('Sending request to LLM: '+ BodyJSON.ToString);

  Result:= TAIResponse.Create; // Initialize with default values
  Result.ErrorMsg:= '';

  try
    HttpClient    := TNetHTTPClient.Create(nil);      // Freed by: Finally
    HttpClient.ConnectionTimeout:= Timeout;
    HttpClient.ResponseTimeout:= Timeout;
    Request       := TNetHTTPRequest.Create(nil);     // Freed by: Finally
    RequestBody:= TStringStream.Create(BodyJSON.ToString, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      Result.ErrorMsg := 'Failed to initialize HTTP client: ' + E.Message;
      // If creation fails, we must ensure we don't leak partial creations in the Finally block
      // But FreeAndNil is safe on nil, so we proceed to Finally.
    end;
  end;

  // 2. EXECUTE AND PROCESS (Protected by Finally)
  try
    if Result.ErrorMsg <> '' then Exit; // Creation failed, exit (Finally will run)

    Request.Client:= HttpClient;
    Request.CustomHeaders['Content-Type'] := 'application/json';

    // Construct URL using LLM properties
    TRY
      HttpResponse:= Request.Post(LLM.ApiURL, RequestBody);
    EXCEPT
      on E: Exception do
      begin
        Result.ErrorMsg:= 'Post request failed: ' + E.Message;
        Exit;
      end;
    END;

    if NOT Assigned(HttpResponse) then
      begin
        Result.ErrorMsg := 'No HTTP response received. Please check your internet connection. Timeout: ' +IntToStr(Timeout);
        Exit;
      end;

    Result.FHttpStatus := HttpResponse.StatusCode;

    if HttpResponse.StatusCode <> 200 then
      begin
        Result.ErrorMsg:= 'AI response status: '+IntToStr(HttpResponse.StatusCode)+' ('+getHttpErrorMessage(HttpResponse.StatusCode)+') - ' + detectErrorType(HttpResponse.ContentAsString)+ '. ' + HttpResponse.ContentAsString;
        Result.ErrorMsg:= StringReplace(Result.ErrorMsg, '\n', sLineBreak, [rfReplaceAll]);
        Exit;
      end;

    // Parse JSON response
    try
      RespJSON := TJSONObject.ParseJSONValue(HttpResponse.ContentAsString) as TJSONObject;
    except
      on E: Exception do
      begin
        Result.ErrorMsg:= 'JSON parsing failed: ' + E.Message;
        Exit;
      end;
    end;

    if not Assigned(RespJSON) then
      begin
        Result.ErrorMsg := 'Invalid JSON response received.';
        Exit;
      end;

    // Process the token usage, candidates, etc
    if RespJSON.TryGetValue<TJSONObject>('usageMetadata', UsageMetadata) then
      begin
        Result.TokensPrompt     := UsageMetadata.GetValue<Integer>('promptTokenCount', 0);
        Result.TokensCandidate  := UsageMetadata.GetValue<Integer>('candidatesTokenCount', 0);
        Result.TokensTotal      := UsageMetadata.GetValue<Integer>('totalTokenCount', 0);
        TokensTotal             := TokensTotal + Result.TokensTotal;
      end;

    // Extract information from the response
    if not RespJSON.TryGetValue<TJSONArray>('candidates', Candidates) or (Candidates.Count = 0) then
      begin
        Result.ErrorMsg:= 'No candidates found in response: ' + HttpResponse.ContentAsString;
        Exit;
      end;

    Candidate := Candidates.Items[0] as TJSONObject; // Take the first candidate

    // Check for safety or other finish reasons that indicate problems
    FinishReason:= Candidate.GetValue<string>('finishReason', 'FinishReason field not found!');
    if (FinishReason <> '') AND (FinishReason <> 'STOP') then {STOP is normal thought termination. Idiotic name.}
      begin
        if SameText(FinishReason, 'SAFETY')
        then Result.ErrorMsg := 'Content blocked by safety filters!'
        else Result.ErrorMsg := FinishReason2String(FinishReason) + ' FinishReason: ' + FinishReason;
        Exit;
      end;

    // SafetyRatings might be missing, so use GetValue with a default
    if Candidate.TryGetValue<TJSONArray>('safetyRatings', SafetyArr)
    then Result.FSafetyRatings := SafetyArr.Clone as TJSONArray
    else Result.FSafetyRatings := TJSONArray.Create;

    // Extract the text content
    if Candidate.TryGetValue<TJSONObject>('content', ContentObj)
    AND ContentObj.TryGetValue<TJSONArray>('parts', ContentJson)
    AND (ContentJson.Count > 0) then
      begin
        Part0:= ContentJson.Items[0] as TJSONObject;
        ExtractedText := Part0.GetValue<string>('text', '');    // The AI API returns the text content directly, not a nested JSON object, so, the 'text' key contains a string, not a TJSONObject.
        try
          Result.FExtractedJSONObj:= TJSONObject.ParseJSONValue(ExtractedText) as TJSONObject;
        except
          on E: EJSONParseException do
          begin
            Result.FExtractedJSONObj:= NIL; // Or handle as you see fit
            Result.ErrorMsg:= 'Failed to process server response content (Part0).' + E.Message;
            EXIT;
          end;
        end;
      end
    else
      begin
        Result.ErrorMsg:= 'No content found in candidate response';
        Exit;
      end;
  finally
    // This block is guaranteed to run, even if we called Exit above.
    // IMPORTANT: Release HttpResponse interface BEFORE destroying HttpClient.
    // The response may hold internal references to objects owned by the client.
    // Failing to do this can cause use-after-free during exception unwinding.
    HttpResponse := nil;
    FreeAndNil(RespJSON);
    FreeAndNil(RequestBody);
    FreeAndNil(Request);
    FreeAndNil(HttpClient);
  end
end;  



{-------------------------------------------------------------------------------------------------------------
   UTILS
-------------------------------------------------------------------------------------------------------------}

function TAiClient.finishReason2String(FinishReason: string): string;
begin
  if SameText(FinishReason, 'STOP') then                      result:= 'The model''s output reached a natural conclusion or a user-provided stop sequence.' else
  if SameText(FinishReason, 'MAX_TOKENS') then                result:= 'The model stopped generating because it reached the maximum number of tokens specified for the response' else
  if SameText(FinishReason, 'SAFETY') then                    result:= 'The generation was stopped because the response was flagged for violating safety policies.' else
  if SameText(FinishReason, 'RECITATION') then                result:= 'The generation was stopped because the response was flagged for unauthorized citations.' else
  if SameText(FinishReason, 'PROHIBITED_CONTENT')then         result:= 'The generation was stopped because the response was flagged for containing prohibited content.' else
  if SameText(FinishReason, 'BLOCKLIST') then                 result:= 'The generation was stopped because the response contained terms from a terminology blocklist.' else
  if SameText(FinishReason, 'SPII') then                      result:= 'The generation was stopped because the response was flagged for containing Sensitive Personally Identifiable Information.' else
  if SameText(FinishReason, 'OTHER') then                     result:= 'Other reasons that stopped the token generation.' else
  if SameText(FinishReason, 'FINISH_REASON_UNSPECIFIED') then result:= 'The reason for the stop is not specified.'
  else
    Result:= 'Unknown FinishReason';
end;



{-------------------------------------------------------------------------------------------------------------
   SAVE / LOAD
-------------------------------------------------------------------------------------------------------------}

procedure TAiClient.Load(FileName: string);
begin
  if NOT FileExists(FileName) then EXIT;  // The file does not exist on first run

  VAR Stream:= TLightStream.CreateRead(FileName);
  TRY
    Load(Stream);
  FINALLY
    FreeAndNil(Stream);
  END;
end;


procedure TAiClient.Save(FileName: string);
begin
  VAR Stream:= TLightStream.CreateWrite(FileName);
  TRY
    Save(Stream);   
  FINALLY
    FreeAndNil(Stream);
  END;
end;


procedure TAiClient.Load(Stream: TLightStream);
begin
  if NOT Stream.ReadHeader(ClassSignature, 2) then EXIT;
  TokensTotal:= Stream.ReadInteger;
  Stream.ReadPadding(12);
end;


procedure TAiClient.Save(Stream: TLightStream);
begin
  Stream.WriteHeader(ClassSignature, 2);
  Stream.WriteInteger(TokensTotal);
  Stream.WritePadding(12);
end;






{-------------------------------------------------------------------------------------------------------------
   JSON GenConfig
-------------------------------------------------------------------------------------------------------------}

function TAiClient.makeGenerationConfig(CONST FilePath: String): TJSONPair;
VAR
  ResponseSchema: TJSONObject;
  GenerationConfigObj: TJSONObject;
  ThinkingConfig25: TJSONObject;
CONST
  ResponseMimeType = 'application/json';
begin
  GenerationConfigObj:= nil;

  TRY
    // This is only for Gemini 2.5
    ThinkingConfig25 := TJSONObject.Create;
    ThinkingConfig25.AddPair('thinkingBudget', 0);
    ThinkingConfig25.AddPair('includeThoughts', FALSE);

    // This is for both Gemini 2.0 and 2.5
    GenerationConfigObj := TJSONObject.Create;
    GenerationConfigObj.AddPair('responseMimeType', ResponseMimeType);
    GenerationConfigObj.AddPair('candidateCount',   LLM.CandidateCnt);
    GenerationConfigObj.AddPair('maxOutputTokens',  LLM.MaxTokens);
    GenerationConfigObj.AddPair('temperature',      LLM.Temperature);
    GenerationConfigObj.AddPair('topP',             LLM.TopP);
    GenerationConfigObj.AddPair('topK',             LLM.TopK);
    GenerationConfigObj.AddPair('thinkingConfig',   ThinkingConfig25);
    // Note: ThinkingConfig25 is now owned by GenerationConfigObj - do NOT free it separately

    // File path is empty when we just ping the AI to see if the connection is fine
    if FilePath <> '' then
      begin
        ResponseSchema:= File2Json(FilePath);
        GenerationConfigObj.AddPair('responseSchema', ResponseSchema);
        // Note: ResponseSchema is now owned by GenerationConfigObj - do NOT free it separately
      end;

    Result:= TJSONPair.Create('generationConfig', GenerationConfigObj);
  EXCEPT
    // Only free GenerationConfigObj - it owns all its children (including ThinkingConfig25, ResponseSchema)
    FreeAndNil(GenerationConfigObj);
    RAISE;
  END;
end;


function TAiClient.TestConnection: TAIResponse;
var
  BodyJSON: TJSONObject;
  ContentsArray: TJSONArray;
  ContentObject: TJSONObject;
  PartsArray: TJSONArray;
  TextPart: TJSONObject;
begin
  BodyJSON:= nil;
  Result:= nil;
  try
    try
      // 1. Create the innermost part: {"text": "test"}
      TextPart := TJSONObject.Create;
      TextPart.AddPair('text', 'Hello AI!');

      // 2. Create the parts array: [{"text": "test"}]
      PartsArray := TJSONArray.Create;
      PartsArray.AddElement(TextPart); // PartsArray now owns TextPart

      // 3. Create the content object: {"role": "user", "parts": [...]}
      ContentObject := TJSONObject.Create;
      ContentObject.AddPair('role', 'user');
      ContentObject.AddPair('parts', PartsArray); // ContentObject now owns PartsArray

      // 4. Create the contents array: [ { ... } ]
      ContentsArray := TJSONArray.Create;
      ContentsArray.AddElement(ContentObject); // ContentsArray now owns ContentObject

      // 5. Create the Body: {"contents": [ ... ] }
      BodyJSON := TJSONObject.Create;
      BodyJSON.AddPair('contents', ContentsArray); // BodyJSON now owns ContentsArray

      // 6. Send Request
      Result:= postHttpRequest(BodyJSON);

    except
      on E: Exception do
      begin
        if Result = NIL
        then Result:= TAIResponse.Create;
        Result.ErrorMsg:= 'Exception during connection test setup: ' + E.Message;
      end;
    end;
    
  finally
    FreeAndNil(BodyJSON); // BodyJSON owns all the child objects (Arrays, Parts, etc.), so freeing it frees everything.
  end;
end;


end.
