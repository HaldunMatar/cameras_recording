import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart';

class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._() { _rebuildDio(); }

  // ── Server config ─────────────────────────────────────────────────────────
  String _ip   = '';
  String _port = '8765';

  String get ip      => _ip;
  String get port    => _port;
  String get baseUrl => 'http://$_ip:$_port';
  String get wsUrl   => 'ws://$_ip:$_port/ws';
  bool get configured => _ip.isNotEmpty;

  // ── SCP config ────────────────────────────────────────────────────────────
  String scpUser      = '';   // e.g. mini
  String scpRemoteDir = '';   // e.g. /home/mini/cam_recorder/recordings
  String scpLocalDir  = '';   // e.g. /Users/haldun/videos

  /// Build the scp command for a given filename.
  /// Returns null if any required field is empty.
  String? scpCommand(String filename) {
    if (scpUser.isEmpty || _ip.isEmpty || scpRemoteDir.isEmpty || scpLocalDir.isEmpty) {
      return null;
    }
    final remote = scpRemoteDir.endsWith('/')
        ? '$scpRemoteDir$filename'
        : '$scpRemoteDir/$filename';
    return 'scp -r ${scpUser}@$_ip:$remote $scpLocalDir';
  }

  Future<void> loadConfig() async {
    final p = await SharedPreferences.getInstance();
    _ip          = p.getString('srv_ip')       ?? '';
    _port        = p.getString('srv_port')      ?? '8765';
    scpUser      = p.getString('scp_user')      ?? '';
    scpRemoteDir = p.getString('scp_remote_dir') ?? '';
    scpLocalDir  = p.getString('scp_local_dir')  ?? '';
    _rebuildDio();
  }

  Future<void> saveConfig(String ip, String port) async {
    _ip   = ip;
    _port = port.isEmpty ? '8765' : port;
    final p = await SharedPreferences.getInstance();
    await p.setString('srv_ip',   _ip);
    await p.setString('srv_port', _port);
    _rebuildDio();
    reconnectWS();
  }

  Future<void> saveScpConfig({
    required String user,
    required String remoteDir,
    required String localDir,
  }) async {
    scpUser      = user;
    scpRemoteDir = remoteDir;
    scpLocalDir  = localDir;
    final p = await SharedPreferences.getInstance();
    await p.setString('scp_user',       user);
    await p.setString('scp_remote_dir', remoteDir);
    await p.setString('scp_local_dir',  localDir);
  }

  // ── Dio ───────────────────────────────────────────────────────────────────
  late Dio _dio;
  void _rebuildDio() {
    _dio = Dio(BaseOptions(
      baseUrl:        baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 120),
    ));
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────
  WebSocketChannel? _ws;
  final _statusCtrl =
      StreamController<Map<String, RecStatus>>.broadcast();

  Stream<Map<String, RecStatus>> get statusStream => _statusCtrl.stream;

  void connectWS() {
    if (!configured) return;
    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _ws!.stream.listen(
        (raw) {
          try {
            final json =
                jsonDecode(raw as String) as Map<String, dynamic>;
            if (json['type'] == 'status_update') {
              final data =
                  Map<String, dynamic>.from(json['data'] ?? {});
              _statusCtrl.add(data.map((k, v) => MapEntry(
                    k,
                    RecStatus.fromJson(
                        v as Map<String, dynamic>))));
            }
          } catch (_) {}
        },
        onDone:  () =>
            Future.delayed(const Duration(seconds: 3), connectWS),
        onError: (_) =>
            Future.delayed(const Duration(seconds: 3), connectWS),
      );
      _ws!.sink.add(jsonEncode({'action': 'subscribe'}));
    } catch (_) {
      Future.delayed(const Duration(seconds: 3), connectWS);
    }
  }

  void reconnectWS() {
    try { _ws?.sink.close(); } catch (_) {}
    Future.delayed(const Duration(milliseconds: 500), connectWS);
  }

  // ── Health ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> health() async {
    final r = await _dio.get<Map<String, dynamic>>('/health');
    return r.data!;
  }

  // ── Cameras ───────────────────────────────────────────────────────────────
  Future<List<CameraInfo>> listCameras() async {
    final r = await _dio.get<List<dynamic>>('/cameras');
    return r.data!
        .map((e) => CameraInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addCamera({
    required String name,
    required String rtspUrl,
    String? label,
  }) async {
    await _dio.post<void>('/cameras', data: {
      'name': name, 'rtsp_url': rtspUrl,
      if (label != null && label.isNotEmpty) 'label': label,
    });
  }

  Future<void> removeCamera(String name) async =>
      _dio.delete<void>('/cameras/$name');

  // ── Recordings ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> startRecording(StartRequest req) async {
    final r = await _dio
        .post<Map<String, dynamic>>('/recordings/start', data: req.toJson());
    return r.data!;
  }

  Future<void> stopRecording(String camName) async =>
      _dio.post<void>('/recordings/stop/$camName');

  Future<void> stopAll() async =>
      _dio.post<void>('/recordings/stop_all');

  // ── Files ─────────────────────────────────────────────────────────────────
  Future<List<RecFile>> listFiles({String? camName}) async {
    final r = await _dio.get<List<dynamic>>(
      '/files',
      queryParameters: camName != null ? {'cam_name': camName} : null,
    );
    return r.data!
        .map((e) => RecFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteFile(String filename) async =>
      _dio.delete<void>('/files/${Uri.encodeComponent(filename)}');

  /// Web  → triggers browser Save dialog (no local path returned).
  /// Other → streams file to documents folder, returns local path.
  Future<String> downloadFile(
    String filename, {
    void Function(double)? onProgress,
  }) async {
    final url =
        '$baseUrl/files/${Uri.encodeComponent(filename)}/download';
    if (kIsWeb) {
      downloadViaAnchor(url, filename);
      return filename;
    }
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$filename';
    await _dio.download(
      url, path,
      onReceiveProgress: (recv, total) {
        if (total > 0) onProgress?.call(recv / total);
      },
    );
    return path;
  }

  String snapshotUrl(String camName) =>
      '$baseUrl/stream/$camName/snapshot';
}
