import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_theme.dart';

class RecordingSessionScreen extends StatefulWidget {
  final List<CameraInfo> cameras;
  final int    durationSeconds;
  final String format;

  const RecordingSessionScreen({
    super.key,
    required this.cameras,
    this.durationSeconds = 3600,
    this.format = 'ts',
  });

  @override
  State<RecordingSessionScreen> createState() =>
      _RecordingSessionScreenState();
}

class _RecordingSessionScreenState extends State<RecordingSessionScreen>
    with TickerProviderStateMixin {

  Map<String, RecStatus> _statuses = {};
  StreamSubscription?    _wsSub;
  bool                   _starting = true;
  bool                   _stopping = false;
  String?                _startError;

  final Map<String, int>    _elapsed = {};
  final Map<String, double> _sizeMb  = {};
  Timer?                    _ticker;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    for (final c in widget.cameras) {
      _elapsed[c.name] = 0;
      _sizeMb[c.name]  = 0.0;
    }

    _wsSub = ApiService().statusStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _statuses = s;
        for (final cam in widget.cameras) {
          final st = s[cam.name];
          if (st != null && st.elapsedSeconds != null) {
            _elapsed[cam.name] = st.elapsedSeconds!;
          }
        }
      });
    });

    _startRecording();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        for (final cam in widget.cameras) {
          _elapsed[cam.name] = (_elapsed[cam.name] ?? 0) + 1;
          final mb = cam.width != null && cam.width! >= 1920
              ? 0.23
              : cam.width != null && cam.width! >= 1280
                  ? 0.17
                  : 0.11;
          _sizeMb[cam.name] = (_sizeMb[cam.name] ?? 0) + mb;
        }
      });
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ticker?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      await ApiService().startRecording(StartRequest(
        cameraNames:     widget.cameras.map((c) => c.name).toList(),
        durationSeconds: widget.durationSeconds,
        format:          widget.format,
      ));
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() { _starting = false; _startError = e.toString(); });
      }
    }
  }

  // ── DISMISS WITHOUT STOPPING ──────────────────────────────────────────────
  // Recording keeps running on the server.
  // The cameras screen shows an active banner so the user knows.
  void _dismissToBackground() {
    Navigator.of(context).pop();
  }

  // ── STOP AND CLOSE ────────────────────────────────────────────────────────
  Future<void> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop recording?',
          style: TextStyle(
            color: AppColors.text, fontWeight: FontWeight.w700)),
        content: const Text(
          'All recordings will stop and files will be saved on the server.',
          style: TextStyle(color: AppColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppColors.text2))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _stopping = true);
    try {
      for (final cam in widget.cameras) {
        await ApiService().stopRecording(cam.name);
      }
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  String _fmtTime(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${_p(h)}:${_p(m)}:${_p(sec)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  double get _totalMb =>
      _sizeMb.values.fold(0.0, (a, b) => a + b);

  int get _maxElapsed =>
      _elapsed.values.fold(0, (a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept back gesture — dismiss to background, do NOT stop recording
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _dismissToBackground();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg0,
        appBar: AppBar(
          backgroundColor: AppColors.bg1,
          // Back arrow → dismiss to background (recording continues)
          leading: IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded, color: AppColors.text2),
            tooltip: 'Dismiss (recording continues)',
            onPressed: _dismissToBackground,
          ),
          title: const Text('Recording Session',
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Opacity(
                  opacity: (_starting || _stopping) ? 0.4 : _pulseAnim.value,
                  child: _RecChip(
                    label: _starting
                        ? 'Starting…'
                        : _stopping
                            ? 'Stopping…'
                            : 'REC',
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _startError != null
            ? _ErrorBody(
                error: _startError!, onRetry: _startRecording)
            : Column(
                children: [
                  // ── Dismiss hint banner ─────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: AppColors.bg3,
                    child: Row(
                      children: const [
                        Icon(Icons.info_outline_rounded,
                            size: 13, color: AppColors.text3),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Swipe down or tap ↓ to go back — recording keeps running in background.',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.text3),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Timer card ──────────────────────────────────────────
                  _TimerCard(
                    timeLabel:       _starting
                        ? '00:00:00'
                        : _fmtTime(_maxElapsed),
                    cameraCount:     widget.cameras.length,
                    totalMb:         _totalMb,
                    starting:        _starting,
                    durationSeconds: widget.durationSeconds,
                    format:          widget.format,
                  ),

                  // ── Camera rows ─────────────────────────────────────────
                  Expanded(
                    child: _starting
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.red))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: widget.cameras.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final cam = widget.cameras[i];
                              return _CamSessionTile(
                                camera:  cam,
                                status:  _statuses[cam.name],
                                elapsed: _elapsed[cam.name] ?? 0,
                                sizeMb:  _sizeMb[cam.name]  ?? 0.0,
                              );
                            },
                          ),
                  ),

                  // ── Buttons ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        // Dismiss — keep recording running
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.text2,
                              side: const BorderSide(
                                  color: AppColors.border2),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _dismissToBackground,
                            icon: const Icon(
                                Icons.arrow_downward_rounded, size: 16),
                            label: const Text('Dismiss',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Stop recording
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  AppColors.red.withOpacity(0.15),
                              foregroundColor: AppColors.red,
                              side: const BorderSide(
                                  color: AppColors.red, width: 1),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: (_stopping || _starting)
                                ? null
                                : _confirmStop,
                            icon: const Icon(Icons.stop_rounded, size: 18),
                            label: Text(
                              _stopping ? 'Stopping…' : 'Stop',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timer card with segment progress
// ─────────────────────────────────────────────────────────────────────────────

class _TimerCard extends StatelessWidget {
  final String timeLabel;
  final int    cameraCount;
  final double totalMb;
  final bool   starting;
  final int    durationSeconds;
  final String format;

  const _TimerCard({
    required this.timeLabel,
    required this.cameraCount,
    required this.totalMb,
    required this.starting,
    required this.durationSeconds,
    required this.format,
  });

  double _progress() {
    try {
      final parts = timeLabel.split(':').map(int.parse).toList();
      final elapsed = parts[0] * 3600 + parts[1] * 60 + parts[2];
      if (durationSeconds <= 0) return 0;
      return (elapsed % durationSeconds) / durationSeconds;
    } catch (_) { return 0; }
  }

  String _fmtDuration() {
    if (durationSeconds < 60)   return '${durationSeconds}s';
    if (durationSeconds < 3600) return '${durationSeconds ~/ 60}min';
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    return m > 0 ? '${h}h ${m}min' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final prog = starting ? 0.0 : _progress();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.red.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(timeLabel,
            style: const TextStyle(
              fontSize: 52, fontWeight: FontWeight.w300,
              color: AppColors.text, letterSpacing: 3,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
          const SizedBox(height: 6),
          Text(
            '$cameraCount camera${cameraCount > 1 ? 's' : ''}'
            '  ·  ${totalMb.toStringAsFixed(1)} MB'
            '  ·  .${format.toUpperCase()}',
            style: const TextStyle(fontSize: 11, color: AppColors.text3)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: prog, minHeight: 4,
              backgroundColor: AppColors.border2,
              valueColor: const AlwaysStoppedAnimation(AppColors.red),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_fmtDuration()} / segment',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.text3)),
              Text('${(prog * 100).toInt()}%',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-camera tile
// ─────────────────────────────────────────────────────────────────────────────

class _CamSessionTile extends StatelessWidget {
  final CameraInfo camera;
  final RecStatus? status;
  final int        elapsed;
  final double     sizeMb;

  const _CamSessionTile({
    required this.camera,
    required this.status,
    required this.elapsed,
    required this.sizeMb,
  });

  String _p(int n) => n.toString().padLeft(2, '0');

  String get _elapsedLabel {
    final m = elapsed ~/ 60; final s = elapsed % 60;
    return '${_p(m)}:${_p(s)}';
  }

  String get _sizeLabel => sizeMb >= 1000
      ? '${(sizeMb / 1000).toStringAsFixed(1)} GB'
      : '${sizeMb.toStringAsFixed(1)} MB';

  String get _filename {
    final fn = status?.currentFile?.split('/').last ?? '';
    return fn.isNotEmpty ? fn : '${camera.name}_recording';
  }

  @override
  Widget build(BuildContext context) {
    final isRec   = status?.state == RecState.recording;
    final progress = status?.progress ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: isRec
                      ? AppColors.red.withOpacity(0.12)
                      : AppColors.bg3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isRec ? Icons.fiber_manual_record : Icons.videocam_rounded,
                  size: 16,
                  color: isRec ? AppColors.red : AppColors.text3),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(camera.displayName,
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(_filename,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.text3),
                      overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_sizeLabel,
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.text2,
                      fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 2),
                  Text(status?.state.name ?? 'idle',
                    style: TextStyle(
                      fontSize: 10,
                      color: isRec ? AppColors.red : AppColors.text3)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border2,
              valueColor: const AlwaysStoppedAnimation(AppColors.red),
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text('Elapsed $_elapsedLabel',
                style: const TextStyle(
                  fontSize: 10, color: AppColors.text3,
                  fontFeatures: [FontFeature.tabularFigures()])),
              const Spacer(),
              Text('${(progress * 100).toInt()}%',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RecChip extends StatelessWidget {
  final String label;
  const _RecChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.red.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.red.withOpacity(0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.fiber_manual_record, size: 8, color: AppColors.red),
        const SizedBox(width: 4),
        Text(label,
          style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.red)),
      ],
    ),
  );
}

class _ErrorBody extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 48, color: AppColors.text3),
        const SizedBox(height: 12),
        const Text('Failed to start',
          style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.text3))),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry')),
      ],
    ),
  );
}
