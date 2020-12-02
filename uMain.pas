unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls, Data.DB,
  System.ImageList, Vcl.ImgList, Vcl.Grids, Vcl.DBGrids, Datasnap.DBClient,
  Vcl.ComCtrls, Vcl.Buttons, Winapi.ShellAPI;

type TRecordType = (
  rtData = 0,
  rtEndOfFile,
  rtExtendedSegmentAddress,
  rtStartSegmentAddress,
  rtExtendedLinearAddress,
  rtStartLinearAddress
);

function RecordTypeToString(RecordType: TRecordType): string;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    edtHexFile: TButtonedEdit;
    Label1: TLabel;
    dsData: TClientDataSet;
    ds_Data: TDataSource;
    grdData: TDBGrid;
    ilButtons: TImageList;
    dlgOpen: TFileOpenDialog;
    pgBar: TProgressBar;
    btnEditor: TSpeedButton;
    procedure edtHexFileRightButtonClick(Sender: TObject);
    procedure grdDataTitleClick(Column: TColumn);
    procedure edtHexFileLeftButtonClick(Sender: TObject);
    procedure dsDataAfterOpen(DataSet: TDataSet);
    procedure btnEditorClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    function GetByte(Value: String; Index: Integer): UInt8;
    function GetWord(Value: string; Index: Integer): UInt16;
    function GetSData(Value: string): string;
    function CheckChecksum(Value: string): Boolean;
    procedure FormatHexValue8(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure FormatHexValue16(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure FormatHexString(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure FormatChksum(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure FormatType(Sender: TField; var Text: string; DisplayText: Boolean);
  protected
    procedure WMDropFiles(var Msg: TMessage); message WM_DROPFILES;
  public
    procedure CreateDataSet;
    procedure LoadFile(FileName: string);
  end;

var
  frmMain: TfrmMain;

implementation

const
  FLD_LINE        = 'Line';
  FLD_DATALEN     = 'DataLen';
  FLD_ADDRESS     = 'Address';
  FLD_RECORD_TYPE = 'RecordType';
  FLD_DATA        = 'Data';
  FLD_CHKSUM      = 'Checksum';
  FLD_SDATA     = 'SData';

{$R *.dfm}

function RecordTypeToString(RecordType: TRecordType): string;
begin
  case RecordType of
    rtData:                   Result := 'Data';
    rtEndOfFile:              Result := 'End Of File';
    rtExtendedSegmentAddress: Result := 'Extended Segment Address';
    rtStartSegmentAddress:    Result := 'Start Segment Address';
    rtExtendedLinearAddress:  Result := 'Extended Linear Address';
    rtStartLinearAddress:     Result := 'Start Linear Address';
  else
    Result := '0x' + IntToHex(Ord(RecordType), 2);
  end;
end;

procedure TfrmMain.btnEditorClick(Sender: TObject);
begin
  if (edtHexFile.Text <> '') and FileExists(edtHexFile.Text) then
    ShellExecute(Handle, 'open', PChar(edtHexFile.Text), nil, nil, SW_SHOWNORMAL);
end;

function TfrmMain.CheckChecksum(Value: string): Boolean;
var
  s: string;
  i: Integer;
  b: uint8;
begin
  s := Copy(Value, Low(string) + 1, Length(Value));
  b := 0;
  for i := 0 to (Length(s) div 2) - 1 do
    b := b + Byte(StrToInt('$' + Copy(s, Low(string) + 2 * i, 2)));
  Result := b = 0;
end;

procedure TfrmMain.CreateDataSet;
var
  i: Integer;
begin
  With dsData do
  begin
    Close;
    FieldDefs.ClearAndResetID;
    FieldDefs.Add(FLD_LINE, ftInteger);
    FieldDefs.Add(FLD_DATALEN, ftInteger);
    FieldDefs.Add(FLD_ADDRESS, ftInteger);
    FieldDefs.Add(FLD_RECORD_TYPE, ftInteger);
    FieldDefs.Add(FLD_DATA, ftString, 255*3-1);  // Max dat len * 3 (2 chars for byte + space) -1 for last space
    FieldDefs.Add(FLD_CHKSUM, ftBoolean);
    FieldDefs.Add(FLD_SDATA, ftString, 255);
    // Create indexes
    IndexDefs.ClearAndResetID;
    for i := 0 to FieldDefs.Count - 1 do
      IndexDefs.Add('idx' + IntToStr(i), FieldDefs[i].Name, [TIndexOption.ixCaseInsensitive]);
    IndexName := 'idx0';
    CreateDataSet;
    LogChanges := False;
    Open;
  end;
end;

procedure TfrmMain.dsDataAfterOpen(DataSet: TDataSet);
var
  f: TField;
begin
  f := DataSet.FindField(FLD_DATALEN);
  if f <> nil then
    f.OnGetText := FormatHexValue8;

  f := DataSet.FindField(FLD_ADDRESS);
  if f <> nil then
    f.OnGetText := FormatHexValue16;

  f := DataSet.FindField(FLD_DATA);
  if f <> nil then
    f.OnGetText := FormatHexString;

  f := DataSet.FindField(FLD_CHKSUM);
  if f <> nil then
    f.OnGetText := FormatChksum;

  f := DataSet.FindField(FLD_RECORD_TYPE);
  if f <> nil then
  begin
    f.OnGetText := FormatType;
    f.Alignment := TAlignment.taLeftJustify;
  end;
end;

procedure TfrmMain.edtHexFileLeftButtonClick(Sender: TObject);
begin
  if (edtHexFile.Text <> '') and FileExists(edtHexFile.Text) then
  begin
    CreateDataSet;
    LoadFile(dlgopen.FileName);
    grdData.SetFocus;
  end;
end;

procedure TfrmMain.edtHexFileRightButtonClick(Sender: TObject);
begin
  if dlgOpen.Execute then
  begin
    edtHexFile.Text := dlgOpen.FileName;
    CreateDataSet;
    LoadFile(dlgopen.FileName);
    grdData.SetFocus;
  end;
end;

procedure TfrmMain.FormatChksum(Sender: TField; var Text: string;
  DisplayText: Boolean);
begin
  DisplayText := not Sender.IsNull;
  if DisplayText then
    if Sender.AsBoolean then
      Text := 'OK'
    else
      Text := 'BAD';
end;

procedure TfrmMain.FormatHexString(Sender: TField; var Text: string;
  DisplayText: Boolean);
var
  i, max: Integer;
  s: string;
begin
  DisplayText := not Sender.IsNull and (Length(Sender.AsString) > 0);
  if not DisplayText then
    Exit;

  s := Sender.AsString;
  Text := '0x  ';
  max := (Length(s) div 2) - 1;
  for i := 0 to max do
  begin
    Text := Text + Copy(s, Low(string) + 2 * i, 2);
    if i < max then
      Text := Text + ' ';
  end;
end;

procedure TfrmMain.FormatHexValue16(Sender: TField; var Text: string;
  DisplayText: Boolean);
begin
  DisplayText := not Sender.IsNull;
  if DisplayText then
    Text := '0x' + IntToHex(Sender.AsInteger, 4);
end;

procedure TfrmMain.FormatHexValue8(Sender: TField; var Text: string;
  DisplayText: Boolean);
begin
  DisplayText := not Sender.IsNull;
  if DisplayText then
    Text := '0x' + IntToHex(Sender.AsInteger, 2);
end;

procedure TfrmMain.FormatType(Sender: TField; var Text: string;
  DisplayText: Boolean);
begin
  DisplayText := not Sender.IsNull;
  if DisplayText then
    Text := RecordTypeToString(TRecordType(Sender.AsInteger));
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  DragAcceptFiles(Self.Handle, True);
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  DragAcceptFiles(Self.Handle, False);
end;

procedure TfrmMain.FormShow(Sender: TObject);
var
  i: Integer;
begin
  for i := 1 to ParamCount do
    if FileExists(ParamStr(i)) and (LowerCase(ExtractFileExt(ParamStr(i))) = '.hex') then
      try
        edtHexFile.Text := ParamStr(i);
        CreateDataSet;
        LoadFile(ParamStr(i));
        grdData.SetFocus;
        Break;
      except
      end;
end;

function TfrmMain.GetByte(Value: String; Index: Integer): UInt8;
begin
  Result := StrToInt('$' + Copy(Value, Index, 2));
end;

function TfrmMain.GetSData(Value: string): string;
var
  i, max: Integer;
  c: Char;
begin
  Result := '';
  if Value <> '' then
  begin
    max := (Length(Value) div 2) - 1;
    for i := 0 to max do
    begin
      c := Char(StrToInt('$' + Copy(Value, Low(string) + 2 * i, 2)));
      if CharInSet(c, ['a'..'z',
                      'A'..'Z',
                      '0'..'9',
                      '!', '@', '#', '$', '%',
                      '^', '&', '*', '(', ')',
                      '{', '}', '[', ']', ':',
                      ';', '"', '\', '|', '/',
                      '?', '.', '>', ',', '<',
                      '\', '|', '`', '~', '''']) then
        Result := Result + c
      else
        Result := Result + '.';
    end;
  end;
end;

function TfrmMain.GetWord(Value: string; Index: Integer): UInt16;
begin
  Result := StrToInt('$' + Copy(Value, Index, 4));
end;

procedure TfrmMain.grdDataTitleClick(Column: TColumn);
begin
  dsData.IndexName := 'idx' + InttoStr(Column.Index);
end;

procedure TfrmMain.LoadFile(FileName: string);
const START_STRING_INDEX = Low(string);
var
  sl: TStringList;
  i: Integer;
  s: string;
begin
  Screen.Cursor := crHourGlass;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FileName);
    pgBar.Max := sl.Count;
    dsData.DisableControls;
    try
      for i := 0 to sl.Count - 1 do
      begin
        s := Trim(sl[i]);
        if s <> '' then // Because we don't want records in dataset for empty lines
          if (Length(s) > 10) and (s[START_STRING_INDEX] = ':') then
          begin
            dsData.Insert;
            dsData.FieldByName(FLD_LINE).AsInteger        := i + 1;
            dsData.FieldByName(FLD_DATALEN).AsInteger     := GetByte(s, START_STRING_INDEX + 1);
            dsData.FieldByName(FLD_ADDRESS).AsInteger     := Getword(s, START_STRING_INDEX + 3);
            dsData.FieldByName(FLD_RECORD_TYPE).AsInteger := GetByte(s, START_STRING_INDEX + 7);
            if TRecordType(dsData.FieldByName(FLD_RECORD_TYPE).AsInteger) <> TRecordType.rtData then
              dsData.FieldByName(FLD_ADDRESS).Clear;
            if dsData.FieldByName(FLD_DATALEN).AsInteger > 0 then
              dsData.FieldByName(FLD_DATA).AsString       := Copy(s, START_STRING_INDEX + 9, Length(s) - 11)
            else
              dsData.FieldByName(FLD_DATA).Clear;
            dsData.FieldByName(FLD_CHKSUM).AsBoolean      := CheckChecksum(s);
            if TRecordType(dsData.FieldByName(FLD_RECORD_TYPE).AsInteger) <> TRecordType.rtData then
              dsData.FieldByName(FLD_SDATA).Clear
            else
              dsData.FieldByName(FLD_SDATA).AsString      := GetSData(Copy(s, START_STRING_INDEX + 9, Length(s) - 11));
          end else
          begin
            dsData.Insert;
            dsData.FieldByName(FLD_LINE).AsInteger := i + 1;
            dsData.FieldByName(FLD_DATALEN).Clear;
            dsData.FieldByName(FLD_ADDRESS).Clear;
            dsData.FieldByName(FLD_RECORD_TYPE).Clear;
            dsData.FieldByName(FLD_DATA).AsString := '<ERROR LINE>';
            dsData.FieldByName(FLD_CHKSUM).Clear;
            dsData.FieldByName(FLD_SDATA).Clear;
            dsData.Post;
          end;
        pgBar.StepIt;
      end;
    finally
      pgBar.Position := 0;
      dsData.First;
      dsData.EnableControls;
    end;
  finally
    sl.Free;
    Screen.Cursor := crDefault;
  end;
end;

procedure TfrmMain.WMDropFiles(var Msg: TMessage);
var
  hDrop: THandle;
  FileCount: Integer;
  NameLen: Integer;
  i: Integer;
  s: string;
begin
  hDrop := Msg.wParam;
  FileCount := DragQueryFile(hDrop , $FFFFFFFF, nil, 0);

  for i := 0 to FileCount - 1 do begin
    NameLen := DragQueryFile(hDrop, i, nil, 0) + 1;
    SetLength(s, NameLen);
    DragQueryFile(hDrop, i, Pointer(s), NameLen);
    s := Trim(s);

    if FileExists(s) and (LowerCase(ExtractFileExt(s)) = '.hex') then
      try
        edtHexFile.Text := s;
        CreateDataSet;
        LoadFile(s);
        grdData.SetFocus;
        Break;
      except
      end;
  end;

  DragFinish(hDrop);
end;

end.
