UNIT AiLLM;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   General AI client
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES
  System.SysUtils, System.Classes,
  LightCore.StreamBuff2, LightCore.AppData, LightCore.TextFile;

TYPE
  TLLMObject = class
   private
    CONST StreamSignature: AnsiString= 'TLLMObject';
    procedure Load(Stream: TCubicBuffStream2);    overload;
    procedure Save(Stream: TCubicBuffStream2);    overload;
   public
    ApiKey      : string;
    Model       : string;
    ApiBase     : string;
    UploadBase  : string;
    AvailableModels: TStringList;

    Temperature : Double;
    TopP        : Double;
    TopK        : Integer;
    MaxTokens   : Integer;
    CandidateCnt: Integer;

    HintTemp  : string;
    HintTopP  : string;
    HintTopK  : string;
    HintCandid: string;
    HintMaxTok: string;

    function StartUploadURL: string; virtual; abstract;
    function ApiURL        : string; virtual; abstract;

    procedure Load(FileName: string);  overload;
    procedure Save(FileName: string);  overload;
    constructor Create; virtual;
    destructor Destroy; override;
   end;


IMPLEMENTATION



constructor TLLMObject.Create;
begin
  inherited Create;
  Temperature := 0.1;
  TopP        := 0.95;
  TopK        := 0;
  MaxTokens   := 40000;
  CandidateCnt:= 1;      // 1–8 (default 1)
  AvailableModels:= TStringList.Create;
  Load(AppDataCore.AppDataFolder(True)+ 'LLM_Data.bin');

  // Read secret API key (for lazy people)
  if (ApiKey = '')
  AND FileExists(AppDataCore.ExeFolder+ 'SecretKey.INI')
  then ApiKey:= StringFromFile(AppDataCore.ExeFolder+ 'SecretKey.INI');
end;

 
destructor TLLMObject.Destroy;
begin
  Save(AppDataCore.AppDataFolder(True)+ 'LLM_Data.bin');
  FreeAndNil(AvailableModels);
  inherited;
end;





{-------------------------------------------------------------------------------------------------------------
   LOAD/SAVE
-------------------------------------------------------------------------------------------------------------}
procedure TLLMObject.Load(FileName: string);
begin
  if NOT FileExists(FileName) then EXIT;
  VAR Stream:= TCubicBuffStream2.CreateRead(FileName);
  TRY
    Load(Stream);
  FINALLY
    FreeAndNil(Stream);
  END;
end;


procedure TLLMObject.Save(FileName: string);
begin
  VAR Stream:= TCubicBuffStream2.CreateWrite(FileName);
  TRY
    Save(Stream);
  FINALLY
    FreeAndNil(Stream);
  END;
end;



procedure TLLMObject.Load(Stream: TCubicBuffStream2);
begin
  Stream.ReadHeader(StreamSignature, 1);
  ApiKey     := Stream.ReadString;
  Model      := Stream.ReadString;
  ApiBase    := Stream.ReadString;
  UploadBase := Stream.ReadString;
  Temperature:= Stream.ReadDouble;
  TopP       := Stream.ReadDouble;
  TopK       := Stream.ReadInteger;
  MaxTokens  := Stream.ReadInteger;
  Stream.ReadPaddingDef;
end;


procedure TLLMObject.Save(Stream: TCubicBuffStream2);
begin
  Stream.WriteHeader(StreamSignature, 1);  // Header & version number
  Stream.WriteString (ApiKey     );
  Stream.WriteString (Model      );
  Stream.WriteString (ApiBase    );
  Stream.WriteString (UploadBase );
  Stream.WriteDouble (Temperature);
  Stream.WriteDouble (TopP       );
  Stream.WriteInteger(TopK       );
  Stream.WriteInteger(MaxTokens  );
  Stream.WritePaddingDef;
end;


end.
