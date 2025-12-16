UNIT AiLLMGemini;

{-------------------------------------------------------------------------------------------------------------
   www.GabrielMoraru.com
   2025.07
--------------------------------------------------------------------------------------------------------------
   Gemini LLM Client

   Price per output:
     Gemini 2.5 Flash -> 400000 chars = $1
     Gemini 2.0 Flash -> 400000 chars = 16cent = 64 pages at 6k chars

     https://ai.google.dev/gemini-api/docs/pricing
     https://aistudio.google.com/usage?timeRange=last-28-days&tab=rate-limit&project=gen-lang-client-0659800905         // Rate limit & Billing
-------------------------------------------------------------------------------------------------------------}

INTERFACE
USES
  System.SysUtils, AiLLM;

TYPE
  TLLMGemini = class(TLLMObject)
   private
   public
     constructor Create; override;
     destructor Destroy; override;

     function ApiURL        : string; override;
     function StartUploadURL: string; override;
     procedure SetLowCreativity;
   end;


IMPLEMENTATION

USES
  LightCore;


CONST
  DEFAULT_API_BASE    = 'https://generativelanguage.googleapis.com/v1beta';
  DEFAULT_UPLOAD_BASE = 'https://generativelanguage.googleapis.com/upload/v1beta';
  DEFAULT_MODEL       = 'gemini-2.5-flash';


constructor TLLMGemini.Create;
begin
  // Gemini default settings.     Must be before Inherited because Inherited calls "Load"!
  Model       := DEFAULT_MODEL;
  ApiBase     := DEFAULT_API_BASE;
  UploadBase  := DEFAULT_UPLOAD_BASE;

  inherited Create;

  AvailableModels.Add('gemini-2.5-flash');   //ToDo -oCR: find list of all possible models
  AvailableModels.Add('gemini-2.5-pro');
  AvailableModels.Add('gemini-2.0-flash');   // This is available in the Free tier but it says "Limit reached"
  AvailableModels.Add('gemini-2.0-pro');     // This is not available at all in the Free tier

  HintTemp  := 'Controls the randomness of the generated text.'+ CRLF
             + 'A lower temperature (e.g., 0.2) results in more predictable, focused, and less creative outputs.'+ CRLF
             + 'A temperature of 0 means the model will always pick the most probable token, leading to highly deterministic and potentially repetitive responses.'+ CRLF
             + 'A higher temperature (e.g., 0.8) leads to more diverse, random, and potentially more creative outputs.';
  HintTopP  := 'Also known as "nucleus sampling", topP filters tokens based on their cumulative probability.'+ CRLF
             + '  It selects the smallest set of tokens whose cumulative probability exceeds the specified topP value (e.g., 0.95).'+ CRLF
             + '  This means the model considers only the most probable tokens, making the output less random than using temperature alone.';
  HintTopK  := 'This parameter limits the number of top probable tokens considered for selection at each step.'+ CRLF
             + 'For example, if topK is set to 64, the model will only consider the 64 most probable tokens at each step, ignoring the rest.';
  HintCandid:= 'This parameter determines how many different response candidates the model generates.'+ CRLF
             + 'For example, if candidateCount is 3, the model will produce three potential responses for a given prompt.';
  HintMaxTok:= 'This parameter limits the maximum number of tokens (approximately four characters each) in the generated output.'+ CRLF
             + 'Setting a lower maxTokens value can help control the length of the response.';
end;


destructor TLLMGemini.Destroy;
begin
  inherited;
end;


procedure TLLMGemini.SetLowCreativity;
begin
  Temperature := 0.0;
  TopP        := 0.0;   // This is ignored if Temperature is zero
  TopK        := 0;     // This is ignored if TopP is zero
  CandidateCnt:= 1;     // Correct for a single precise response
end;


function TLLMGemini.StartUploadURL: string;
begin
  Result:= UploadBase + '/files?key='+ ApiKey;
end;


function TLLMGemini.APIURL: string;
begin
  Result:= ApiBase+'/models/'+ Model+':generateContent?key='+ ApiKey
end;


end.

