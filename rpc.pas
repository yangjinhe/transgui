{*************************************************************************************
  This file is part of Transmission Remote GUI.
  Copyright (c) 2008-2019 by Yury Sidorov and Transmission Remote GUI working group.

  Transmission Remote GUI is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  Transmission Remote GUI is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Transmission Remote GUI; if not, write to the Free Software
  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

  In addition, as a special exception, the copyright holders give permission to 
  link the code of portions of this program with the
  OpenSSL library under certain conditions as described in each individual
  source file, and distribute linked combinations including the two.

  You must obey the GNU General Public License in all respects for all of the
  code used other than OpenSSL.  If you modify file(s) with this exception, you
  may extend this exception to your version of the file(s), but you are not
  obligated to do so.  If you do not wish to do so, delete this exception
  statement from your version.  If you delete this exception statement from all
  source files in the program, then also delete it here.
*************************************************************************************}
unit rpc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, httpsend, syncobjs, fpjson, jsonparser, ssl_openssl,
  ZStream, jsonscanner;

resourcestring
  sTransmissionAt = 'Transmission%s at %s:%s';

const
  DefaultRpcPath = '/transmission/rpc';

type
  TAdvInfoType = (aiNone, aiGeneral, aiFiles, aiPeers, aiTrackers, aiStats);
  TRefreshTypes = (rtTorrents, rtDetails, rtSession);
  TRefreshType = set of TRefreshTypes;

  TRpc = class;

  { TRpcThread }

  TRpcThread = class(TThread)
  private
    ResultData: TJSONData;
    FRpc: TRpc;

    function GetAdvInfo: TAdvInfoType;
    function GetCurTorrentId: cardinal;
    function GetRefreshInterval: TDateTime;
    function GetStatus: string;
    procedure SetStatus(const AValue: string);

    function GetTorrents: boolean;
    procedure GetPeers(TorrentId: integer);
    procedure GetFiles(TorrentId: integer);
    procedure GetTrackers(TorrentId: integer);
    procedure GetStats;
    procedure GetInfo(TorrentId: integer);
    procedure GetSessionInfo;

    procedure DoFillTorrentsList;
    procedure DoFillPeersList;
    procedure DoFillFilesList;
    procedure DoFillInfo;
    procedure DoFillTrackersList;
    procedure DoFillStats;
    procedure DoFillSessionInfo;
    procedure NotifyCheckStatus;
    procedure CheckStatusHandler(Data: PtrInt);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;

    property Status: string read GetStatus write SetStatus;
    property RefreshInterval: TDateTime read GetRefreshInterval;
    property CurTorrentId: cardinal read GetCurTorrentId;
    property AdvInfo: TAdvInfoType read GetAdvInfo;
  end;

  TRpc = class
  private
    FLock: TCriticalSection;
    FStatus: string;
    FInfoStatus: string;
    FConnected: boolean;
    FTorrentFields: string;
    FRPCVersion: integer;
    XTorrentSession: string;
    FMainThreadId: TThreadID;
    FRpcPath: string;

    function GetConnected: boolean;
    function GetConnecting: boolean;
    function GetInfoStatus: string;
    function GetStatus: string;
    function GetTorrentFields: string;
    procedure SetInfoStatus(const AValue: string);
    procedure SetStatus(const AValue: string);
    procedure SetTorrentFields(const AValue: string);
    procedure CreateHttp;
  public
    Http: THTTPSend;
    HttpLock: TCriticalSection;
    RpcThread: TRpcThread;
    Url: string;
    RefreshInterval: TDateTime;
    CurTorrentId: cardinal;
    AdvInfo: TAdvInfoType;
    RefreshNow: TRefreshType;
    RequestFullInfo: boolean;
    ReconnectAllowed: boolean;
    RequestStartTime: TDateTime;

    constructor Create;
    destructor Destroy; override;
    procedure InitSSL;

    procedure Lock;
    procedure Unlock;

    procedure Connect;
    procedure Disconnect;

    function SendRequest(req: TJSONObject; ReturnArguments: boolean = True; ATimeOut: integer = -1): TJSONObject;
    function RequestInfo(TorrentId: integer; const Fields: array of const; const ExtraFields: array of string): TJSONObject;
    function RequestInfo(TorrentId: integer; const Fields: array of const): TJSONObject;

    property Status: string read GetStatus write SetStatus;
    property InfoStatus: string read GetInfoStatus write SetInfoStatus;
    property Connected: boolean read GetConnected;
    property Connecting: boolean read GetConnecting;
    property TorrentFields: string read GetTorrentFields write SetTorrentFields;
    property RPCVersion: integer read FRPCVersion;
    property RpcPath: string read FRpcPath write FRpcPath;
  end;

var
  RemotePathDelimiter: char = '/';

implementation

uses Main, ssl_openssl_lib, synafpc, blcksock;

function TranslateTableToObjects(reply: TJSONObject) : TJSONObject;
var
  array_tor, fields, out_torrents : TJSONArray;
  object_tor : TJSONObject;
  i, j : integer;
begin
  fields:=reply.Arrays['torrents'].Arrays[0];
  out_torrents:=TJSONArray.Create;
  for i:=1 to reply.Arrays['torrents'].Count - 1 do
  begin
    array_tor:=reply.Arrays['torrents'].Arrays[i];
    object_tor:=TJSONObject.Create;
    for j:=0 to fields.Count - 1 do
      object_tor.Add(fields.Items[j].AsString, array_tor.Items[j].Clone);

    out_torrents.Add(object_tor);
  end;
  Result:=TJSONObject.Create(['torrents', out_torrents]);
  reply.Free;
end;

{ TRpcThread }

procedure TRpcThread.Execute;
var
  t, tt: TDateTime;
  i: integer;
  ai: TAdvInfoType;
begin
  try
    GetSessionInfo;
    NotifyCheckStatus;
    if not FRpc.FConnected then
      Terminate;

    t:=Now - 1;
    tt:=Now;
    while not Terminated do begin
      if Now - t >= RefreshInterval then begin
        FRpc.RefreshNow:=FRpc.RefreshNow + [rtTorrents, rtDetails];
        t:=Now;
      end;
      if Now - tt >= RefreshInterval*5 then begin
        Include(FRpc.RefreshNow, rtSession);
        tt:=Now;
      end;

      if Status = '' then
        if rtTorrents in FRpc.RefreshNow then begin
          GetTorrents;
          Exclude(FRpc.RefreshNow, rtTorrents);
          t:=Now;
        end
        else
          if rtDetails in FRpc.RefreshNow then begin
            i:=CurTorrentId;
            ai:=AdvInfo;
            if i <> 0 then begin
              case ai of
                aiGeneral:
                  GetInfo(i);
                aiPeers:
                  GetPeers(i);
                aiFiles:
                  GetFiles(i);
                aiTrackers:
                  GetTrackers(i);
              end;
            end;

            case ai of
              aiStats:
                GetStats;
            end;

            if (i = CurTorrentId) and (ai = AdvInfo) then
              Exclude(FRpc.RefreshNow, rtDetails);
          end
          else
            if rtSession in FRpc.RefreshNow then begin
              GetSessionInfo;
              Exclude(FRpc.RefreshNow, rtSession);
            end;

      if Status <> '' then begin
        NotifyCheckStatus;
        Sleep(100);
      end;

      if FRpc.RefreshNow = [] then
        Sleep(50);
    end;
  except
    Status:=Exception(ExceptObject).Message;
    FRpc.RpcThread:=nil;
    NotifyCheckStatus;
  end;
  FRpc.RpcThread:=nil;
  FRpc.FConnected:=False;
  FRpc.FRPCVersion:=0;
  Sleep(20);
end;

constructor TRpcThread.Create;
begin
  inherited Create(True);
end;

destructor TRpcThread.Destroy;
begin
  inherited Destroy;
end;

procedure TRpcThread.SetStatus(const AValue: string);
begin
  FRpc.Status:=AValue;
end;

procedure TRpcThread.DoFillTorrentsList;
begin
  MainForm.FillTorrentsList(ResultData as TJSONArray);
end;

procedure TRpcThread.DoFillPeersList;
begin
  MainForm.FillPeersList(ResultData as TJSONArray);
end;

procedure TRpcThread.DoFillFilesList;
var
  t: TJSONObject;
  dir: widestring;
begin
  if ResultData = nil then begin
    MainForm.ClearDetailsInfo;
    exit;
  end;
  t:=ResultData as TJSONObject;
  if RpcObj.RPCVersion >= 4 then
    dir:=widestring(t.Strings['downloadDir'])
  else
    dir:='';
  MainForm.FillFilesList(t.Integers['id'], t.Arrays['files'], t.Arrays['priorities'], t.Arrays['wanted'], dir);
end;

procedure TRpcThread.DoFillInfo;
begin
  MainForm.FillGeneralInfo(ResultData as TJSONObject);
end;

procedure TRpcThread.DoFillTrackersList;
begin
  MainForm.FillTrackersList(ResultData as TJSONObject);
end;

procedure TRpcThread.DoFillStats;
begin
  MainForm.FillStatistics(ResultData as TJSONObject);
end;

procedure TRpcThread.DoFillSessionInfo;
begin
  MainForm.FillSessionInfo(ResultData as TJSONObject);
end;

procedure TRpcThread.NotifyCheckStatus;
begin
  if not Terminated then
    Application.QueueAsyncCall(@CheckStatusHandler, 0);
end;

procedure TRpcThread.CheckStatusHandler(Data: PtrInt);
begin
  if csDestroying in MainForm.ComponentState then exit;
  MainForm.CheckStatus;
end;

procedure TRpcThread.GetSessionInfo;
var
  req, args, args2: TJSONObject;
  s: string;
begin
  req:=TJSONObject.Create;
  try
    req.Add('method', 'session-get');
    args:=FRpc.SendRequest(req);
    if args <> nil then
    try
      FRpc.FConnected:=True;
      if args.IndexOfName('rpc-version') >= 0 then
        FRpc.FRPCVersion := args.Integers['rpc-version']
      else
        FRpc.FRPCVersion := 0;
      if args.IndexOfName('version') >= 0 then
        s:=' ' + args.Strings['version']
      else
        s:='';
      FRpc.InfoStatus:=Format(sTransmissionAt, [s, FRpc.Http.TargetHost, FRpc.Http.TargetPort]);
      if FRpc.RPCVersion >= 15 then begin
        // Requesting free space in download dir
        req.Free;
        req:=TJSONObject.Create;
        req.Add('method', 'free-space');
        args2:=TJSONObject.Create;
        try
          args2.Add('path', args.Strings['download-dir']);
          req.Add('arguments', args2);
          args2:=FRpc.SendRequest(req);
          if args2 <> nil then
            args.Floats['download-dir-free-space']:=args2.Floats['size-bytes']
          else begin
            args.Floats['download-dir-free-space']:=-1;
            FRpc.Status:='';
          end;
        finally
          args2.Free;
        end;
      end;
      ResultData:=args;
      if not Terminated then
        Synchronize(@DoFillSessionInfo);
    finally
      args.Free;
    end
    else
      ASSERT(FRpc.Status <> '');
  finally
    req.Free;
  end;
end;

function TRpcThread.GetTorrents: boolean;
var
  args: TJSONObject;
  ExtraFields: array of string;
  sl: TStringList;
  i: integer;
begin
  Result:=False;
  sl:=TStringList.Create;
  try
    FRpc.Lock;
    try
      sl.CommaText:=FRpc.FTorrentFields;
    finally
      FRpc.Unlock;
    end;

    if FRpc.RPCVersion < 7 then begin
      i:=sl.IndexOf('trackers');
      if FRpc.RequestFullInfo then begin
        if i < 0 then
          sl.Add('trackers');
      end
      else
        if i >= 0 then
          sl.Delete(i);
    end;

    i:=sl.IndexOf('downloadDir');
    if FRpc.RequestFullInfo then begin
      if i < 0 then
        sl.Add('downloadDir');
    end
    else
      if i >= 0 then
        sl.Delete(i);

    SetLength(ExtraFields, sl.Count);
    for i:=0 to sl.Count - 1 do
      ExtraFields[i]:=sl[i];
  finally
    sl.Free;
  end;

  args:=FRpc.RequestInfo(0, ['id', 'name', 'status', 'errorString', 'announceResponse', 'recheckProgress',
                            'sizeWhenDone', 'leftUntilDone', 'rateDownload', 'rateUpload', 'trackerStats',
                            'metadataPercentComplete'], ExtraFields);
  try
    if (args <> nil) and not Terminated then begin
      FRpc.RequestFullInfo:=False;
      ResultData:=args.Arrays['torrents'];
      Synchronize(@DoFillTorrentsList);
      Result:=True;
    end;
  finally
    args.Free;
  end;
end;

procedure TRpcThread.GetPeers(TorrentId: integer);
var
  args: TJSONObject;
  t: TJSONArray;
begin
  args:=FRpc.RequestInfo(TorrentId, ['peers']);
  try
    if args <> nil then begin
      t:=args.Arrays['torrents'];
      if t.Count > 0 then
        ResultData:=t.Objects[0].Arrays['peers']
      else
        ResultData:=nil;
      if not Terminated then
        Synchronize(@DoFillPeersList);
    end;
  finally
    args.Free;
  end;
end;

procedure TRpcThread.GetFiles(TorrentId: integer);
var
  args: TJSONObject;
  t: TJSONArray;
begin
  args:=FRpc.RequestInfo(TorrentId, ['id', 'files','priorities','wanted','downloadDir']);
  try
    if args <> nil then begin
      t:=args.Arrays['torrents'];
      if t.Count > 0 then
        ResultData:=t.Objects[0]
      else
        ResultData:=nil;
      if not Terminated then
        Synchronize(@DoFillFilesList);
    end;
  finally
    args.Free;
  end;
end;

procedure TRpcThread.GetTrackers(TorrentId: integer);
var
  args: TJSONObject;
  t: TJSONArray;
begin
  args:=FRpc.RequestInfo(TorrentId, ['id','trackers','trackerStats', 'nextAnnounceTime']);
  try
    if args <> nil then begin
      t:=args.Arrays['torrents'];
      if t.Count > 0 then
        ResultData:=t.Objects[0]
      else
        ResultData:=nil;
      if not Terminated then
        Synchronize(@DoFillTrackersList);
    end;
  finally
    args.Free;
  end;
end;

procedure TRpcThread.GetStats;
var
  req, args: TJSONObject;
begin
  req:=TJSONObject.Create;
  try
    req.Add('method', 'session-stats');
    args:=FRpc.SendRequest(req);
    if args <> nil then
    try
      ResultData:=args;
      if not Terminated then
        Synchronize(@DoFillStats);
    finally
      args.Free;
    end;
  finally
    req.Free;
  end;
end;

procedure TRpcThread.GetInfo(TorrentId: integer);
var
  args: TJSONObject;
  t: TJSONArray;
begin
  args:=FRpc.RequestInfo(TorrentId, ['totalSize', 'sizeWhenDone', 'leftUntilDone', 'pieceCount', 'pieceSize', 'haveValid',
                                    'hashString', 'comment', 'downloadedEver', 'uploadedEver', 'corruptEver', 'errorString',
                                    'announceResponse', 'downloadLimit', 'downloadLimitMode', 'uploadLimit', 'uploadLimitMode',
                                    'maxConnectedPeers', 'nextAnnounceTime', 'dateCreated', 'creator', 'eta', 'peersSendingToUs',
                                    'seeders','peersGettingFromUs','leechers', 'uploadRatio', 'addedDate', 'doneDate',
                                    'activityDate', 'downloadLimited', 'uploadLimited', 'downloadDir', 'id', 'pieces',
                                    'trackerStats', 'secondsDownloading', 'secondsSeeding', 'magnetLink', 'isPrivate', 'labels']);
  try
    if args <> nil then begin
      t:=args.Arrays['torrents'];
      if t.Count > 0 then
        ResultData:=t.Objects[0]
      else
        ResultData:=nil;
      if not Terminated then
        Synchronize(@DoFillInfo);
    end;
  finally
    args.Free;
  end;
end;

function TRpcThread.GetAdvInfo: TAdvInfoType;
begin
  FRpc.Lock;
  try
    Result:=FRpc.AdvInfo;
  finally
    FRpc.Unlock;
  end;
end;

function TRpcThread.GetCurTorrentId: cardinal;
begin
  FRpc.Lock;
  try
    Result:=FRpc.CurTorrentId;
  finally
    FRpc.Unlock;
  end;
end;

function TRpcThread.GetRefreshInterval: TDateTime;
begin
  FRpc.Lock;
  try
    Result:=FRpc.RefreshInterval;
  finally
    FRpc.Unlock;
  end;
end;

function TRpcThread.GetStatus: string;
begin
  Result:=FRpc.Status;
end;

{ TRpc }

constructor TRpc.Create;
begin
  inherited;
  FMainThreadId:=GetCurrentThreadId;
  FLock:=TCriticalSection.Create;
  HttpLock:=TCriticalSection.Create;
  RefreshNow:=[];
  CreateHttp;
end;

destructor TRpc.Destroy;
begin
  Http.Free;
  HttpLock.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TRpc.InitSSL;
{$ifdef unix}
{$ifndef darwin}
  procedure CheckOpenSSL;
  const
  OpenSSLVersions: array[1..4] of string =
  ('0.9.8', '1.0.0', '1.0.2', '1.1.0');
  var
    hLib1, hLib2: TLibHandle;
    i: integer;
  begin
    for i:=Low(OpenSSLVersions) to High(OpenSSLVersions) do begin
      hlib1:=LoadLibrary(PChar('libssl.so.' + OpenSSLVersions[i]));
      hlib2:=LoadLibrary(PChar('libcrypto.so.' + OpenSSLVersions[i]));
      if hLib2 <> 0 then
        FreeLibrary(hLib2);
      if hLib1 <> 0 then
        FreeLibrary(hLib1);
      if (hLib1 <> 0) and (hLib2 <> 0) then begin
        DLLSSLName:='libssl.so.' + OpenSSLVersions[i];
        DLLUtilName:='libcrypto.so.' + OpenSSLVersions[i];
        break;
      end;
    end;
  end;
{$endif darwin}
{$endif unix}
begin
  if IsSSLloaded then exit;
{$ifdef unix}
{$ifndef darwin}
  CheckOpenSSL;
{$endif darwin}
{$endif unix}
  if InitSSLInterface then
    SSLImplementation := TSSLOpenSSL;
  CreateHttp;
end;

type TGzipDecompressionStream=class(TDecompressionStream)
public
  constructor create(Asource:TStream);
end;

constructor TGzipDecompressionStream.create(Asource:TStream);
var gzHeader:array[1..10] of byte;
begin
  {
    paszlib is based on a relatively old zlib version that didn't implement
    reading the gzip header. we "implement" this ourselves by skipping the first
    10 bytes which is just enough for the data Transmission sends.
  }
  inherited create(Asource, True);
  Asource.Read(gzHeader,sizeof(gzHeader));
end;

function DecompressGzipContent(source: TStream): TMemoryStream;
var
  buf : array[1..16384] of byte;
  numRead : integer;
  decomp : TGzipDecompressionStream;
begin
  decomp:=TGzipDecompressionStream.create(source);
  Result:=TMemoryStream.create;
  repeat
    numRead:=decomp.read(buf,sizeof(buf));
    Result.Write(buf,numRead);
  until numRead < sizeof(buf);
  Result.Position:=0;
  decomp.Free;
end;

function CreateJsonParser(serverResp : THTTPSend): TJSONParser;
var decompressed : TMemoryStream;
begin
  if serverResp.Headers.IndexOf('Content-Encoding: gzip') <> -1 then
  begin
    { need to fully decompress as the parser relies on a working Seek() }
    decompressed:=DecompressGzipContent(serverResp.Document);
    Result:=TJSONParser.Create(decompressed, [joUTF8]);
    decompressed.Free;
  end
  else
  begin
    Result:=TJSONParser.Create(serverResp.Document, [joUTF8]);
  end;
end;

function TRpc.SendRequest(req: TJSONObject; ReturnArguments: boolean; ATimeOut: integer): TJSONObject;
var
  obj: TJSONData;
  res: TJSONObject;
  jp: TJSONParser;
  s: string;
  i, j, OldTimeOut, RetryCnt: integer;
  locked, r: boolean;
begin
  if FRpcPath = '' then
    FRpcPath:=DefaultRpcPath;
  Status:='';
  Result:=nil;
  RetryCnt:=2;
  i:=0;
  repeat
    Inc(i);
    HttpLock.Enter;
    locked:=True;
    try
      OldTimeOut:=Http.Timeout;
      RequestStartTime:=Now;
      Http.Document.Clear;
      s:=req.AsJSON;
      Http.Document.Write(PChar(s)^, Length(s));
      s:='';
      Http.Headers.Clear;
      Http.Headers.Add('Accept-Encoding: gzip');
      Http.MimeType:='application/json';
      if XTorrentSession <> '' then
        Http.Headers.Add(XTorrentSession);
      if ATimeOut >= 0 then
        Http.Timeout:=ATimeOut;
      try
        r:=Http.HTTPMethod('POST', Url + FRpcPath);
      finally
        Http.Timeout:=OldTimeOut;
      end;
      if not r then begin
        if FMainThreadId <> GetCurrentThreadId then
          ReconnectAllowed:=True;
        Status:=Http.Sock.LastErrorDesc;
        break;
      end
      else begin
        if Http.ResultCode = 409 then begin
          XTorrentSession:='';
          for j:=0 to Http.Headers.Count - 1 do
            if Pos('x-transmission-session-id:', AnsiLowerCase(Http.Headers[j])) > 0 then begin
              XTorrentSession:=Http.Headers[j];
              break;
            end;
          if XTorrentSession <> '' then begin
            if i = RetryCnt then begin
              if FMainThreadId <> GetCurrentThreadId then
                ReconnectAllowed:=True;
              Status:='Session ID error.';
            end;
            continue;
          end;
        end;

        if Http.ResultCode = 301 then begin
          s:=Trim(Http.Headers.Values['Location']);
          if (s <> '') and (i = 1) then begin
            j:=Length(s);
            if Copy(s, j - 4, MaxInt) = '/web/' then
              SetLength(s, j - 4)
            else
              if Copy(s, j - 3, MaxInt) = '/web' then
                SetLength(s, j - 3);
            FRpcPath:=s + 'rpc';
            Inc(RetryCnt);
            continue;
          end;
        end;

        if Http.ResultCode <> 200 then begin
          if Http.Headers.Count > 0 then begin
            SetString(s, Http.Document.Memory, Http.Document.Size);
            j:=Pos('<body>', LowerCase(s));
            if j > 0 then
              System.Delete(s, 1, j - 1);
            s:=StringReplace(s, #13#10, '', [rfReplaceAll]);
            s:=StringReplace(s, #13, '', [rfReplaceAll]);
            s:=StringReplace(s, #10, '', [rfReplaceAll]);
            s:=StringReplace(s, #9, ' ', [rfReplaceAll]);
            s:=StringReplace(s, '&quot;', '"', [rfReplaceAll, rfIgnoreCase]);
            s:=StringReplace(s, '<br>', LineEnding, [rfReplaceAll, rfIgnoreCase]);
            s:=StringReplace(s, '</p>', LineEnding, [rfReplaceAll, rfIgnoreCase]);
            s:=StringReplace(s, '</h1>', LineEnding, [rfReplaceAll, rfIgnoreCase]);
            s:=StringReplace(s, '<li>', LineEnding+'* ', [rfReplaceAll, rfIgnoreCase]);
            j:=1;
            while j <= Length(s) do begin
              if s[j] = '<' then begin
                while (j <= Length(s)) and (s[j] <> '>') do
                  System.Delete(s, j, 1);
                System.Delete(s, j, 1);
              end
              else
                Inc(j);
            end;
            while Pos('  ', s) > 0 do
              s:=StringReplace(s, '  ', ' ', [rfReplaceAll]);
            while Pos(LineEnding + ' ', s) > 0 do
              s:=StringReplace(s, LineEnding + ' ', LineEnding, [rfReplaceAll]);
            s:=Trim(s);
          end
          else
            s:='';
          if s = '' then begin
            s:=Http.ResultString;
            if s = '' then
              if Http.ResultCode = 0 then
                s:='Invalid server response.'
              else
                s:=Format('HTTP error: %d', [Http.ResultCode]);
          end;
          Status:=s;
          break;
        end;
        Http.Document.Position:=0;
        jp:=CreateJsonParser(Http);
        HttpLock.Leave;
        locked:=False;
        RequestStartTime:=0;
        try
          try
            obj:=jp.Parse;
            Http.Document.Clear;
          finally
            jp.Free;
          end;
        except
          on E: Exception do
            begin
              Status:=e.Message;
              break;
            end;
        end;
        try
          if obj is TJSONObject then begin
            res:=obj as TJSONObject;
            s:=res.Strings['result'];
            if AnsiCompareText(s, 'success') <> 0 then begin
              if Trim(s) = '' then
                s:='Unknown error.';
              Status:=s;
            end
            else begin
              if ReturnArguments then begin
                Result:=res.Objects['arguments'];
                if Result = nil then
                  Status:='Arguments object not found.'
                else begin
//                res.Extract(Result); // lazarus 1.2.6 ok
                  res.Extract(res.IndexOf(Result)); // fix Tample :) lazarus 1.4.0 and high!
                  FreeAndNil(obj);
                end;
              end
              else
                Result:=res;
              if Result <> nil then
                obj:=nil;
            end;
            break;
          end
          else begin
            Status:='Invalid server response.';
            break;
          end;
        finally
          obj.Free;
        end;
      end;
    finally
      RequestStartTime:=0;
      if locked then
        HttpLock.Leave;
    end;
  until i >= RetryCnt;
end;

procedure DeleteIfRpcLessThan(Fields: TStringList; Field: string; RpcVer: integer; NeededRpcVer: integer);
var
  idx: integer;
begin
  idx := Fields.IndexOf(Field);
  if (idx <> -1) and (RpcVer < NeededRpcVer) then
    Fields.Delete(idx);
end;

function TRpc.RequestInfo(TorrentId: integer; const Fields: array of const; const ExtraFields: array of string): TJSONObject;
var
  req, args: TJSONObject;
  _fields: TJSONArray;
  i: integer;
  sl: TStringList;
begin
  Result:=nil;
  req:=TJSONObject.Create;
  sl:=TStringList.Create;
  try
    req.Add('method', 'torrent-get');
    args:=TJSONObject.Create;
    if TorrentId <> 0 then
      args.Add('ids', TJSONArray.Create([TorrentId]));
    _fields:=TJSONArray.Create;
    for i:=Low(Fields) to High(Fields) do
      if (Fields[i].VType=vtAnsiString) then
         sl.Add(String(Fields[i].VAnsiString));
    sl.AddStrings(ExtraFields);
    sl.Sort;

    DeleteIfRpcLessThan(sl, 'labels', FRPCVersion, 16);

    for i:=sl.Count-2 downto 0 do
      if (sl[i]=sl[i+1]) then
        sl.Delete(i+1);
    for i:=0 to sl.Count-1 do
      _fields.Add(sl[i]);
    args.Add('fields', _fields);
    if FRPCVersion >= 16 then
      args.Add('format', 'table');

    req.Add('arguments', args);
    if FRPCVersion >= 16 then
      Result:=TranslateTableToObjects(SendRequest(req))
    else
      Result:=SendRequest(req);
  finally
    sl.Free;
    req.Free;
  end;
end;

function TRpc.RequestInfo(TorrentId: integer; const Fields: array of const): TJSONObject;
begin
  Result:=RequestInfo(TorrentId, Fields, []);
end;


function TRpc.GetStatus: string;
begin
  Lock;
  try
    Result:=FStatus;
    UniqueString(Result);
  finally
    Unlock;
  end;
end;

function TRpc.GetTorrentFields: string;
begin
  Lock;
  try
    Result:=FTorrentFields;
    UniqueString(Result);
  finally
    Unlock;
  end;
end;

procedure TRpc.SetInfoStatus(const AValue: string);
begin
  Lock;
  try
    FInfoStatus:=AValue;
    UniqueString(FStatus);
  finally
    Unlock;
  end;
end;

function TRpc.GetConnected: boolean;
begin
  Result:=Assigned(RpcThread) and FConnected;
end;

function TRpc.GetConnecting: boolean;
begin
  Result:=not FConnected and Assigned(RpcThread);
end;

function TRpc.GetInfoStatus: string;
begin
  Lock;
  try
    Result:=FInfoStatus;
    UniqueString(Result);
  finally
    Unlock;
  end;
end;

procedure TRpc.SetStatus(const AValue: string);
begin
  Lock;
  try
    FStatus:=AValue;
    UniqueString(FStatus);
  finally
    Unlock;
  end;
end;

procedure TRpc.SetTorrentFields(const AValue: string);
begin
  Lock;
  try
    FTorrentFields:=AValue;
    UniqueString(FTorrentFields);
  finally
    Unlock;
  end;
end;

procedure TRpc.CreateHttp;
var
  i : integer;
begin
  Http.Free;
  Http:=THTTPSend.Create;
  Http.Protocol:='1.1';

  i := Ini.ReadInteger('NetWork', 'HttpTimeout', 30);
  if (i < 2) or (i > 999) then i:= 30; // default
  Ini.WriteInteger('NetWork', 'HttpTimeout', i);
  Http.Timeout:= i * 1000;

  i := Ini.ReadInteger('NetWork', 'ConnectTimeout', 0);
  if (i < 0) or (i > 999) then i:= 0; // default
  Ini.WriteInteger('NetWork', 'ConnectTimeout', i);
  Http.FSock.ConnectionTimeout := i * 1000;

  Http.Headers.NameValueSeparator:=':';
end;

procedure TRpc.Lock;
begin
  FLock.Enter;
end;

procedure TRpc.Unlock;
begin
  FLock.Leave;
end;

procedure TRpc.Connect;
begin
  CurTorrentId:=0;
  XTorrentSession:='';
  RequestFullInfo:=True;
  ReconnectAllowed:=False;
  RefreshNow:=[];
  RpcThread:=TRpcThread.Create;
  with RpcThread do begin
    FreeOnTerminate:=True;
    FRpc:=Self;
    Suspended:=False;
  end;
end;

procedure TRpc.Disconnect;
begin
  if Assigned(RpcThread) then begin
    RpcThread.Terminate;
    while Assigned(RpcThread) do begin
      Application.ProcessMessages;
      try
        Http.Sock.CloseSocket;
      except
      end;
      Sleep(20);
    end;
  end;
  Status:='';
  RequestStartTime:=0;
  FRpcPath:='';
end;

end.

