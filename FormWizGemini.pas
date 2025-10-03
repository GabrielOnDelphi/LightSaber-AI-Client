unit FormWizGemini;

INTERFACE

USES
  System.SysUtils, System.Types, System.Classes, system.UITypes,
  FMX.Types, FMX.Dialogs, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Controls.Presentation, FMX.Edit, FMX.SpinBox, FMX.ListBox, FMX.Layouts, FMX.EditBox,
  AiLLM, AiClient, LightFmx.Common.AppData.Form, LightFmx.Common.AppData;

TYPE
  TfrmGemini = class(TLightForm)
    btnCancel      : TButton;
    btnOK          : TButton;
    cmbModel       : TComboBox;
    edtApiBase     : TEdit;
    edtApiKey      : TEdit;
    edtUploadBase  : TEdit;
    Label1         : TLabel;
    Label2         : TLabel;
    Label3         : TLabel;
    Label4         : TLabel;
    layBottom      : TLayout;
    lblInfo        : TLabel;
    lblMaxTokens   : TLabel;
    lblTemperature : TLabel;
    lblTopK        : TLabel;
    lblTopP        : TLabel;
    spnMaxTokens   : TSpinBox;
    spnTemperature : TSpinBox;
    spnTopK        : TSpinBox;
    spnTopP        : TSpinBox;
    procedure btnCancelClick         (Sender: TObject);
    procedure btnOKClick             (Sender: TObject);
    procedure FormClose              (Sender: TObject; var Action: TCloseAction);
    procedure spnMaxTokensCanFocus   (Sender: TObject; var ACanFocus: Boolean);
    procedure spnTemperatureCanFocus (Sender: TObject; var ACanFocus: Boolean);
    procedure spnTopKCanFocus        (Sender: TObject; var ACanFocus: Boolean);
    procedure spnTopPCanFocus        (Sender: TObject; var ACanFocus: Boolean);
  private
    Gemini: TAiClient;
    procedure Gui2Obj;
    procedure Obj2Gui(aGemini: TAiClient);
  public
    class procedure ShowFormModal(aGemini: TAiClient);
  end;


IMPLEMENTATION {$R *.fmx}



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
  Action := TCloseAction.caFree;
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
  for ModelName in Gemini.LLM.AvailableModels do
    cmbModel.Items.Add(ModelName);

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


end.
