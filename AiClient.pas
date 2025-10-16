UNIT AiClient;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   Makes a Post Http Request to a LLM.
   The actual LLM is represented by the TLLMObject.
   (Low level code)
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

     // Tokens for this specific prompt
     TokensPrompt   : Integer;      // The number of tokens in your request (contents). Unused.
     TokensCandidate: Integer;      // The number of tokens in the model's response (candidates). Unused.
     TokensTotal    : Integer;      // The sum of both, representing the total tokens used for the API call.
   public
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
    procedure uploadFile(InputFile: TChatPart);

    procedure Load(Stream: TLightStream);   overload;
    procedure Save(Stream: TLightStream);   overload;
  protected
    function  postHttpRequest(BodyJSON: TJSONObject): TAIResponse; // Optional: Max tokens in response
  public
    LLM: TLLMObject;
    TokensTotal: Integer;    // Total used tokens for ALL prompts

    constructor Create; virtual;
    destructor  Destroy; override;

    procedure UploadFiles(InputFiles: TChatParts);
    procedure Load(FileName: string);  overload;
    procedure Save(FileName: string);  overload;
  end;



IMPLEMENTATION
USES
  AiLLMGemini, AiUtils, LightCore.AppData;



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
VAR InputFile: TChatPart;
begin
  for VAR i:= 0 to InputFiles.Count-1 do
    begin
      InputFile:= InputFiles[i];
      if TFile.Exists(InputFile.Path)
      then uploadFile(InputFile)                           // UPLOAD
      else AppDataCore.RamLog.AddWarn('File not found: '+ InputFile.Path);
    end;
end;


// Uploads a single file to the AI Files API, returning its URI
procedure TAiClient.uploadFile(InputFile: TChatPart);
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
    Request    := TNetHTTPRequest.Create(nil);
    Request.Client:= HttpClient;

    //------------------------------------------------
    //  Step 1: Initiate resumable Upload Session
    //------------------------------------------------

    // Generate a unique display name for the uploaded file
    VAR DisplayName:= ExtractFileName(InputFile.Path) + '-' + Copy(GUIDToString(TGUID.NewGuid),2,20);
    VAR StreamName:= '{"file":{"display_name":"'+DisplayName+'"}}';

    BodyStream := TStringStream.Create(StreamName, TEncoding.UTF8);     // JSON body for initiating the upload
    try
      // Set headers required for starting a resumable upload
      Request.CustomHeaders['X-Goog-Upload-Protocol']              := 'resumable';
      Request.CustomHeaders['X-Goog-Upload-Command']               := 'start';
      Request.CustomHeaders['X-Goog-Upload-Header-Content-Length'] := IntToStr(TFile.GetSize(InputFile.Path));
      Request.CustomHeaders['X-Goog-Upload-Header-Content-Type']   := Extension2MimeType(InputFile.Path);
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
    FileData   := TFile.ReadAllBytes(InputFile.Path);
    DataStream := TBytesStream.Create(FileData);

    // No need to clear CustomHeaders here; new values will override or add.
    Request.CustomHeaders['X-Goog-Upload-Offset']  := '0';                          // Starting from offset 0 for the whole file
    Request.CustomHeaders['X-Goog-Upload-Command'] := 'upload, finalize';           // Upload and finalize in one go
    Request.CustomHeaders['Content-Type']          := Extension2MimeType(InputFile.Path); // Content type of the file data
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
        InputFile.FileUri:= (FileObj as TJSONObject).GetValue<string>('uri');   //ToDo 5 -oCR: C2C: When do we release the files from the server??? Are they self-deleted?
        AppDataCore.RamLog.AddVerb('File uploaded successfully. URI: '+ InputFile.FileUri);
      end
    else
      AppDataCore.RamLog.AddError('File URI not found in upload response: '+ Response.ContentAsString);

  finally
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
    Request       := TNetHTTPRequest.Create(nil);     // Freed by: Finally
    Request.Client:= HttpClient;

    // No need to clear CustomHeaders here; setting Content-Type is sufficient.
    Request.CustomHeaders['Content-Type'] := 'application/json';
    RequestBody:= TStringStream.Create(BodyJSON.ToString, TEncoding.UTF8);

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
      Result.ErrorMsg := 'No HTTP response received. Please check your internet connection.';
      Exit;
    end;

    Result.FHttpStatus := HttpResponse.StatusCode;

    if HttpResponse.StatusCode <> 200 then
    begin
      Result.ErrorMsg:= 'AI response status: '+IntToStr(HttpResponse.StatusCode)+'('+getHttpErrorMessage(HttpResponse.StatusCode)+') - ' + detectErrorType(HttpResponse.ContentAsString)+ '. ' + HttpResponse.ContentAsString;
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

    // Extract token usage information
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
        Result.ErrorMsg := 'No content found in candidate response';
        Exit;
      end;

  except
    on E: Exception do
      Result.ErrorMsg := 'Unexpected error in GetResponse: ' + E.Message;
  end;

  // Cleanup
  FreeAndNil(RequestBody);
  FreeAndNil(Request);
  FreeAndNil(HttpClient);
  FreeAndNil(RespJSON);
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
  if NOT FileExists(FileName) then EXIT;

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
  Stream.ReadHeader(ClassSignature, 1);
  TokensTotal:= Stream.ReadInteger;
  Stream.ReadPaddingE(12);
end;


procedure TAiClient.Save(Stream: TLightStream);
begin
  Stream.WriteHeader(ClassSignature, 1);
  Stream.WriteInteger(TokensTotal);
  Stream.WritePadding(12);
end;


end.
