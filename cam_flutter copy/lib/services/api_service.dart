import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._();

  // ── Config ────────────────────────────────────────────────────────────────

  String _ip   = '100.121.60.36';
  String _port = '8765';

  String get ip   => _ip;
  String get port => _port;

  String get baseUrl => 'http://$_ip:$_port';
  String get wsUrl   => 'ws://$_ip:$_port/ws';
  bool   get configured => _ip.isNotEmpty;

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _ip   = prefs.getString('srv_ip')   ?? '';
    _port = prefs.getString('srv_port') ?? '8765';
    _rebuildDio();
  }

  Future<void> saveConfig(String ip, String port) async {
    _ip   = ip;
    _port = port.isEmpty ? '8765' : port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('srv_ip',   _ip);
    await prefs.setString('srv_port', _port);
    _rebuildDio();
    reconnectWS();
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

  WebSocketChannel?  _ws;
  final _statusCtrl = StreamController<Map<String, RecStatus>>.broadcast();

  Stream<Map<String, RecStatus>> get statusStream => _statusCtrl.stream;

  void connectWS() {
    if (!configured) return;
    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _ws!.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            if (json['type'] == 'status_update') {
              final data = Map<String, dynamic>.from(json['data'] ?? {});
              _statusCtrl.add(data.map((k, v) => MapEntry(
                    k,
                    RecStatus.fromJson(v as Map<String, dynamic>),
                  )));
            }
          } catch (_) {}
        },
        onDone:  () => Future.delayed(const Duration(seconds: 3), connectWS),
        onError: (_) => Future.delayed(const Duration(seconds: 3), connectWS),
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
    final res = await _dio.get<Map<String, dynamic>>('/health');
    return res.data!;
  }

  // ── Cameras ───────────────────────────────────────────────────────────────

  Future<List<CameraInfo>> listCameras() async {
    final res = await _dio.get<List<dynamic>>('/cameras');
    return res.data!
        .map((e) => CameraInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addCamera({
    required String name,
    required String rtspUrl,
    String? label,
  }) async {
    await _dio.post<void>('/cameras', data: {
      'name':     name,
      'rtsp_url': rtspUrl,
      if (label != null && label.isNotEmpty) 'label': label,
    });
  }

  Future<void> removeCamera(String name) async =>
      _dio.delete<void>('/cameras/$name');

  // ── Recordings ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> startRecording(StartRequest req) async {
    final res =
        await _dio.post<Map<String, dynamic>>('/recordings/start', data: req.toJson());
    return res.data!;
  }

  Future<void> stopRecording(String camName) async =>
      _dio.post<void>('/recordings/stop/$camName');

  Future<void> stopAll() async =>
      _dio.post<void>('/recordings/stop_all');

  // ── Files ─────────────────────────────────────────────────────────────────

  Future<List<RecFile>> listFiles({String? camName}) async {
    final res = await _dio.get<List<dynamic>>(
      '/files',
      queryParameters: camName != null ? {'cam_name': camName} : null,
    );
    return res.data!
        .map((e) => RecFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteFile(String filename) async =>
      _dio.delete<void>('/files/${Uri.encodeComponent(filename)}');

  Future<String> downloadFile(
    String filename, {
    void Function(double)? onProgress,
  }) async {
    final dir = await _dlDir();
    final path = '${dir.path}/$filename';
    await _dio.download(
      '/files/${Uri.encodeComponent(filename)}/download',
      path,
      onReceiveProgress: (recv, total) {
        if (total > 0) onProgress?.call(recv / total);
      },
    );
    return path;
  }

  Future<Directory> _dlDir() async {
    if (Platform.isAndroid) {
      final d = Directory('/storage/emulated/0/Download/CamRecorder')
        ..createSync(recursive: true);
      return d;
    }
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/CamRecorder')
      ..createSync(recursive: true);
    return d;
  }

  // ── Snapshot URL ──────────────────────────────────────────────────────────

  String snapshotUrl(String camName) =>
      '$baseUrl/stream/$camName/snapshot';
}
