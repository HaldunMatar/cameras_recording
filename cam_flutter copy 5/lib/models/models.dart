// ─── Camera ───────────────────────────────────────────────────────────────────

class CameraInfo {
  final String name;
  final String rtspUrl;
  final String? label;
  final bool online;
  final int? width;
  final int? height;
  final int? fps;
  final String? codec;
  final String? error;

  const CameraInfo({
    required this.name,
    required this.rtspUrl,
    this.label,
    required this.online,
    this.width,
    this.height,
    this.fps,
    this.codec,
    this.error,
  });

  String get displayName => label?.isNotEmpty == true ? label! : name;

  String get resolutionLabel {
    if (width == null || height == null) return '';
    return '${width}×$height${fps != null ? ' · ${fps}fps' : ''}';
  }

  factory CameraInfo.fromJson(Map<String, dynamic> j) => CameraInfo(
        name: j['name'] as String,
        rtspUrl: (j['rtsp_url'] as String?) ?? '',
        label: j['label'] as String?,
        online: (j['online'] as bool?) ?? false,
        width: j['width'] as int?,
        height: j['height'] as int?,
        fps: j['fps'] as int?,
        codec: j['codec'] as String?,
        error: j['error'] as String?,
      );
}

// ─── Recording state ──────────────────────────────────────────────────────────

enum RecState { idle, starting, recording, scheduled, error }

class RecStatus {
  final String camName;
  final RecState state;
  final String? currentFile;
  final int? elapsedSeconds;
  final double? progress;
  final String? error;

  const RecStatus({
    required this.camName,
    required this.state,
    this.currentFile,
    this.elapsedSeconds,
    this.progress,
    this.error,
  });

  bool get isActive =>
      state == RecState.recording || state == RecState.starting;

  factory RecStatus.fromJson(Map<String, dynamic> j) => RecStatus(
        camName: j['cam_name'] as String,
        state: RecState.values.firstWhere(
          (s) => s.name == j['state'],
          orElse: () => RecState.idle,
        ),
        currentFile: j['current_file'] as String?,
        elapsedSeconds: j['elapsed_seconds'] as int?,
        progress: (j['progress'] as num?)?.toDouble(),
        error: j['error'] as String?,
      );
}

// ─── File ─────────────────────────────────────────────────────────────────────

class RecFile {
  final String filename;
  final String camName;
  final int sizeBytes;
  final double sizeMb;
  final String createdAt;
  final int? durationSeconds;
  final bool isRecording;

  const RecFile({
    required this.filename,
    required this.camName,
    required this.sizeBytes,
    required this.sizeMb,
    required this.createdAt,
    this.durationSeconds,
    required this.isRecording,
  });

  String get sizeLabel => sizeMb >= 1000
      ? '${(sizeMb / 1000).toStringAsFixed(1)} GB'
      : '${sizeMb.toStringAsFixed(0)} MB';

  String get durationLabel {
    if (durationSeconds == null) return '—';
    final h = durationSeconds! ~/ 3600;
    final m = (durationSeconds! % 3600) ~/ 60;
    final s = durationSeconds! % 60;
    return '${_p(h)}:${_p(m)}:${_p(s)}';
  }

  String get dateLabel {
    try {
      final dt = DateTime.parse(createdAt);
      return '${_p(dt.day)}/${_p(dt.month)}  ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return createdAt.length > 16 ? createdAt.substring(0, 16) : createdAt;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  factory RecFile.fromJson(Map<String, dynamic> j) => RecFile(
        filename: j['filename'] as String,
        camName: j['cam_name'] as String,
        sizeBytes: (j['size_bytes'] as int?) ?? 0,
        sizeMb: ((j['size_mb'] as num?) ?? 0).toDouble(),
        createdAt: (j['created_at'] as String?) ?? '',
        durationSeconds: j['duration_seconds'] as int?,
        isRecording: (j['is_recording'] as bool?) ?? false,
      );
}

// ─── Start request ────────────────────────────────────────────────────────────

class StartRequest {
  final List<String> cameraNames;
  final int durationSeconds;
  final int width;
  final int height;
  final int fps;
  final int crf;
  final String format; // "mp4" or "ts"

  const StartRequest({
    required this.cameraNames,
    this.durationSeconds = 3600,
    this.width = 960,
    this.height = 540,
    this.fps = 15,
    this.crf = 23,
    this.format = 'mp4',
  });

  Map<String, dynamic> toJson() => {
        'camera_names': cameraNames,
        'duration_seconds': durationSeconds,
        'width': width,
        'height': height,
        'fps': fps,
        'crf': crf,
        'format': format,
      };
}
