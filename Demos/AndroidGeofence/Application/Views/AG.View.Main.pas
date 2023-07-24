unit AG.View.Main;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.Messaging,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Memo.Types, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo, FMX.Layouts,
  FMX.StdCtrls,
  DW.Geofence;

type
  TMainView = class(TForm)
    Memo1: TMemo;
    Layout1: TLayout;
    ToJsonButton: TButton;
    StartButton: TButton;
    StopButton: TButton;
    ClearButton: TButton;
    RemoveAppleButton: TButton;
    procedure LoadButtonClick(Sender: TObject);
    procedure ToJsonButtonClick(Sender: TObject);
    procedure StartButtonClick(Sender: TObject);
    procedure StopButtonClick(Sender: TObject);
    procedure ClearButtonClick(Sender: TObject);
    procedure RemoveAppleButtonClick(Sender: TObject);
  private
    FGeofence: TGeofenceManager;
    FNeedsRestart: Boolean;
    procedure AddRegions;
    procedure LoadJson;
    procedure GeofenceActionCompleteHandler(Sender: TObject; const AAction: Integer; const AResult: Integer; const AErrorMessage: string);
    procedure GeofencePermissionsResultHandler(Sender: TObject);
    procedure GeofenceShowBackgroundPermissionsHandler(Sender: TObject; const ACompletionHandler: TProc);
    procedure GeofenceTransitionHandler(Sender: TObject; const ATransition: TGeofenceTransition; const ARegionIds: TArray<string>);
    procedure UpdateButtons;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainView: TMainView;

implementation

{$R *.fmx}

uses
  System.Permissions,
  Androidapi.JNI.GraphicsContentViewText, Androidapi.Helpers, Androidapi.JNI.Net, Androidapi.JNI.Provider,
  FMX.Platform, FMX.DialogService.Async,
  DW.OSLog,
  DW.Json, DW.Consts.Android, DW.Android.Helpers;

const
  cGeofenceRadius = 100; // metres
  cGeofenceTransitionCaptions: array[TGeofenceTransition] of string = ('Arrived at', 'Departed from');

type
  TPermissionsHelper = record
  public
    class procedure LogPermissions(const APermissions: TArray<string>; const AGrantResults: TArray<TPermissionStatus>); static;
  end;

{ TPermissionsHelper }

class procedure TPermissionsHelper.LogPermissions(const APermissions: TArray<string>; const AGrantResults: TArray<TPermissionStatus>);
const
  cGrantedCaptions: array[TPermissionStatus] of string = ('Granted', 'Denied', 'Permanently Denied');
var
  I: Integer;
begin
  for I := 0 to Length(APermissions) - 1 do
    TOSLog.d('Permission: %s was %s', [APermissions[I], cGrantedCaptions[AGrantResults[I]]]);
end;

{ TMainView }

constructor TMainView.Create(AOwner: TComponent);
begin
  inherited;
  TAndroidHelperEx.RestartIfNotIgnoringBatteryOptimizations;
  FGeofence := TGeofenceManager.Create;
  FGeofence.OnGeofenceActionComplete := GeofenceActionCompleteHandler;
  FGeofence.OnGeofenceTransition := GeofenceTransitionHandler;
  FGeofence.OnPermissionsResult := GeofencePermissionsResultHandler;
  FGeofence.OnShowBackgroundPermissions := GeofenceShowBackgroundPermissionsHandler;
  AddRegions;
  UpdateButtons;
end;

destructor TMainView.Destroy;
begin
  FGeofence.Free;
  inherited;
end;

procedure TMainView.GeofenceActionCompleteHandler(Sender: TObject; const AAction, AResult: Integer; const AErrorMessage: string);
begin
  Memo1.Lines.Add(Format('Ação: %d, Resultado: %d, Menssagem: %s', [AAction, AResult, AErrorMessage]));
  if (AAction = 2) and FNeedsRestart then
  begin
    if AResult = 0 then
    begin
      Memo1.Lines.Add('Reiniciando..');
      FGeofence.Start;
    end
    else
      Memo1.Lines.Add('Stop failed, not restarting');
    FNeedsRestart := False;
  end;
  UpdateButtons;
end;

procedure TMainView.GeofencePermissionsResultHandler(Sender: TObject);
begin
  if not FGeofence.HasPermissions then
  begin
    TDialogServiceAsync.ShowMessage(
      'Location permissions are required in order for the app to work. The App Info screen will now be shown. Please:'#13#10#13#10 +
        '* Tap the "Permissions" item'#13#10'* In the "Denied" section, tap "Location"'#13#10'* Select the "Allow all the time" option'#13#10 +
        '* Tap the back arrow in the top left until it returns to this app',
      procedure(const AResult: TModalResult)
      begin
        FGeofence.ShowAppSettings;
      end
    );
  end;
end;

procedure TMainView.GeofenceTransitionHandler(Sender: TObject; const ATransition: TGeofenceTransition; const ARegionIds: TArray<string>);
begin
  Memo1.Lines.Add(Format('Localização Alterada - %s: %s', [cGeofenceTransitionCaptions[ATransition], string.Join(', ', ARegionIds)]));
end;

procedure TMainView.GeofenceShowBackgroundPermissionsHandler(Sender: TObject; const ACompletionHandler: TProc);
begin
  TDialogServiceAsync.ShowMessage(
    'ttivos® Campo requer permissões de localização em segundo plano para funcionar. ' +
      'Quando solicitado, toque em "Permitir em Configurações" e selecione a opção "Permitir o tempo todo"',
    procedure(const AResult: TModalResult)
    begin
      ACompletionHandler;
    end
  );
end;

procedure TMainView.ClearButtonClick(Sender: TObject);
begin
  Memo1.Text := '';
end;

procedure TMainView.LoadButtonClick(Sender: TObject);
begin
  LoadJson;
end;

procedure TMainView.LoadJson;
begin
  Memo1.Text := TJsonHelper.Tidy(FGeofence.Regions.ToJson);
end;

procedure TMainView.StartButtonClick(Sender: TObject);
begin
  Memo1.Text := '';
  FGeofence.Start;
end;

procedure TMainView.StopButtonClick(Sender: TObject);
begin
  FGeofence.Stop;
end;

procedure TMainView.RemoveAppleButtonClick(Sender: TObject);
begin
  FNeedsRestart := True;
  Memo1.Lines.Add('Removing Apple');
  FGeofence.Regions.RemoveRegion('Apple');
  FGeofence.Stop;
end;

procedure TMainView.ToJsonButtonClick(Sender: TObject);
begin
  LoadJson;
end;

procedure TMainView.UpdateButtons;
begin
  StartButton.Enabled := not FGeofence.IsMonitoring;
  StopButton.Enabled := not StartButton.Enabled;
end;

procedure TMainView.AddRegions;
begin
  // Make sure the first parameter in each region is a unique value
//  FGeofence.Regions.AddRegion('Embarcadero', 30.3976551, -97.7298056, cGeofenceRadius); // 1, 10801 N Mopac Expy #100, Austin, TX 78759, United States
//  FGeofence.Regions.AddRegion('Google', 37.4220656, -122.0840897, cGeofenceRadius); // 1600 Amphitheatre Pkwy, Mountain View, CA 94043, United States
//  FGeofence.Regions.AddRegion('Apple', 37.3318641, -122.0302537, cGeofenceRadius); // 1 Infinite Loop, Cupertino, CA 95014, USA
//  FGeofence.Regions.AddRegion('Microsoft', 47.6422308, -122.1369332, cGeofenceRadius); // One Microsoft Way, Redmond, WA 98052, United States
//  FGeofence.Regions.AddRegion('Home', -34.887860, 138.585340, cGeofenceRadius); // Redact this before committing // Your address


//  TMapttivos.AddRegion(LocationSensor, -22.218083711232325, -54.81320755646517, 30, 'Esquina_Presidente_Vargas');
//  TMapttivos.AddRegion(LocationSensor, -22.218105485291904, -54.81369010530414, 5, 'Frente_Predio');
//  TMapttivos.AddRegion(LocationSensor, -22.21822243, -54.8133471, 2, 'Dentro__Escritorio');
//  TMapttivos.AddRegion(LocationSensor, -22.215794129117445, -54.84023010264094, 500, 'Casa');

  FGeofence.Regions.AddRegion('EsquinaPV', -22.218083711232325, -54.81320755646517, 30);
  FGeofence.Regions.AddRegion('FrentePrédio', -22.218105485291904, -54.81369010530414, 5);
  FGeofence.Regions.AddRegion('DentroEscritório', -22.21822243, -54.8133471, 2);
  FGeofence.Regions.AddRegion('Casa', -22.215794129117445, -54.84023010264094, 500);


end;

end.
