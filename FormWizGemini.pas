unit FormWizGemini;

INTERFACE

USES
  System.SysUtils, System.Classes, system.UITypes,
  FMX.Types, FMX.Dialogs, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.SpinBox, FMX.ListBox, FMX.Layouts, FMX.EditBox,
  AiLLM, AiClient, LightFmx.Common.AppData.Form, LightFmx.Common.AppData, FMX.Controls,
  FMX.Controls.Presentation, FMX.TabControl;

TYPE
  TfrmGemini = class(TLightForm)
    btnCancel      : TButton;
    btnOK          : TButton;
    layBottom      : TLayout;
    lblInfo        : TLabel;
    TabControl: TTabControl;
    TabItem1: TTabItem;
    TabItem2: TTabItem;
    Layout5: TLayout;
    edtApiKey: TEdit;
    Label1: TLabel;
    Layout7: TLayout;
    cmbModel: TComboBox;
    Label2: TLabel;
    Layout6: TLayout;
    lblApiBase: TLabel;
    edtApiBase: TEdit;
    Layout8: TLayout;
    Label3: TLabel;
    edtUploadBase: TEdit;
    layThinking: TLayout;
    chkThinking: TCheckBox;
    Layout1: TLayout;
    lblTemperature: TLabel;
    spnTemperature: TSpinBox;
    Layout4: TLayout;
    lblMaxTokens: TLabel;
    spnMaxTokens: TSpinBox;
    Layout3: TLayout;
    spnTopK: TSpinBox;
    lblTopK: TLabel;
    Layout2: TLayout;
    spnTopP: TSpinBox;
    lblTopP: TLabel;
    btnTest: TButton;
    tabInfo: TTabItem;
    Layout9: TLayout;
    lblTokens: TLabel;
    procedure btnCancelClick         (Sender: TObject);
    procedure btnOKClick             (Sender: TObject);
    procedure FormClose              (Sender: TObject; var Action: TCloseAction);
    procedure spnMaxTokensCanFocus   (Sender: TObject; var ACanFocus: Boolean);
    procedure spnTemperatureCanFocus (Sender: TObject; var ACanFocus: Boolean);
    procedure spnTopKCanFocus        (Sender: TObject; var ACanFocus: Boolean);
    procedure spnTopPCanFocus        (Sender: TObject; var ACanFocus: Boolean);
    procedure chkThinkingCanFocus    (Sender: TObject; var ACanFocus: Boolean);
    procedure btnTestClick(Sender: TObject);
  private
    Gemini: TAiClient;
    procedure Gui2Obj;
    procedure Obj2Gui(aGemini: TAiClient);
  public
    class procedure ShowFormModal(aGemini: TAiClient);
  end;


IMPLEMENTATION {$R *.fmx}
USES LightCore;


class procedure TfrmGemini.ShowFormModal(aGemini: TAiClient);
VAR frmGemini: TfrmGemini;
begin
  AppData.CreateForm(TfrmGemini, frmGemini);
  frmGemini.Obj2Gui(aGemini);
  AppData.ShowModal(frmGemini);
end;


procedure TfrmGemini.btnCancelClick(Sender: TObject);
begin
  Close;
end;


procedure TfrmGemini.btnOKClick(Sender: TObject);
begin
  Gui2Obj;
  Close;
end;


procedure TfrmGemini.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action:= TCloseAction.caFree;
end;


procedure TfrmGemini.btnTestClick(Sender: TObject);
VAR AIResponse: TAIResponse;
begin
  Gui2Obj;
  AIResponse:= Gemini.TestConnection;
  if AIResponse.ErrorMsg = ''
  then ShowMessage('Connection to the AI: OK')
  else ShowMessage(AIResponse.ErrorMsg);
  FreeAndNil(AIResponse);
end;


{-------------------------------------------------------------------------------------------------------------
   DATA TRANSFER
-------------------------------------------------------------------------------------------------------------}
procedure TfrmGemini.Obj2Gui(aGemini: TAiClient);
VAR ModelName: string;
    iModelIndex: Integer;
begin
  Gemini:= aGemini;

  // Populating models
  cmbModel.Items.Clear;
  for ModelName in Gemini.LLM.AvailableModels
    do cmbModel.Items.Add(ModelName);

  // Select the current model
  iModelIndex := cmbModel.Items.IndexOf(Gemini.LLM.Model);
  if iModelIndex >= 0
  then cmbModel.ItemIndex:= iModelIndex
  else
    begin
      cmbModel.Items.Insert(0, Gemini.LLM.Model); // If the current model isn't in the list, add it
      cmbModel.ItemIndex := 0;                    // ...and select it
    end;

  edtApiKey.Text       := Gemini.LLM.ApiKey;
  edtApiBase.Text      := Gemini.LLM.ApiBase;
  edtUploadBase.Text   := Gemini.LLM.UploadBase;
  spnTemperature.Value := Gemini.LLM.Temperature;
  spnTopP.Value        := Gemini.LLM.TopP;
  spnTopK.Value        := Gemini.LLM.TopK;
  spnMaxTokens.Value   := Gemini.LLM.MaxTokens;
  chkThinking.IsChecked:= Gemini.LLM.ThinkingEnabled;

  // Show total tokens used
  lblTokens.Text:= 'Tokens used: ' + Real2Str(Gemini.TokensTotal / 1000, 1) + 'K';
end;


procedure TfrmGemini.Gui2Obj;
begin
  Gemini.LLM.ApiKey      := edtApiKey.Text;
  Gemini.LLM.ApiBase     := edtApiBase.Text;
  Gemini.LLM.UploadBase  := edtUploadBase.Text;
  Gemini.LLM.Temperature := spnTemperature.Value;
  Gemini.LLM.TopP        := spnTopP.Value;
  Gemini.LLM.TopK        := Round(spnTopK.Value);
  Gemini.LLM.MaxTokens   := Round(spnMaxTokens.Value);
  Gemini.LLM.ThinkingEnabled:= chkThinking.IsChecked;

  if cmbModel.ItemIndex >= 0
  then Gemini.LLM.Model:= cmbModel.Items[cmbModel.ItemIndex];
end;





{-------------------------------------------------------------------------------------------------------------
   HINTS
-------------------------------------------------------------------------------------------------------------}
procedure TfrmGemini.spnMaxTokensCanFocus(Sender: TObject; var ACanFocus: Boolean);
begin
  lblInfo.Text:= Gemini.LLM.HintMaxTok;
end;

procedure TfrmGemini.spnTemperatureCanFocus(Sender: TObject; var ACanFocus: Boolean);
begin
  lblInfo.Text:= Gemini.LLM.HintTemp;
end;

procedure TfrmGemini.spnTopKCanFocus(Sender: TObject; var ACanFocus: Boolean);
begin
  lblInfo.Text:= Gemini.LLM.HintTopK;
end;

procedure TfrmGemini.spnTopPCanFocus(Sender: TObject; var ACanFocus: Boolean);
begin
  lblInfo.Text:= Gemini.LLM.HintTopP;
end;

procedure TfrmGemini.chkThinkingCanFocus(Sender: TObject; var ACanFocus: Boolean);
begin
  lblInfo.Text:= 'When enabled, Gemini 2.5+ uses additional reasoning steps before answering.'+ CRLF
               + 'Improves quality but increases token usage and response time.';
end;



end.
