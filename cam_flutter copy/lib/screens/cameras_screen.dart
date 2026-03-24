import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_theme.dart';
import 'recording_session_screen.dart';

class CamerasScreen extends StatefulWidget {
  const CamerasScreen({super.key});
  @override
  State<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends State<CamerasScreen> {
  List<CameraInfo>        _cameras  = [];
  Map<String, RecStatus>  _statuses = {};
  bool                    _loading  = true;
  String?                 _error;
  final Set<String>       _selected = {};
  StreamSubscription?     _wsSub;

  @override
  void initState() {
    super.initState();
    _wsSub = ApiService().statusStream.listen((s) {
      if (mounted) setState(() => _statuses = s);
    });
    _load();
  }

  @override
  void dispose() { _wsSub?.cancel(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cams = await ApiService().listCameras();
      if (mounted) setState(() { _cameras = cams; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _toggle(CameraInfo cam) {
    if (!cam.online) {
      _snack('${cam.displayName} is offline');
      return;
    }
    setState(() {
      _selected.contains(cam.name) ? _selected.remove(cam.name) : _selected.add(cam.name);
    });
  }

  Future<void> _startRecording() async {
    if (_selected.isEmpty) return;
    final cams = _cameras.where((c) => _selected.contains(c.name)).toList();
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => RecordingSessionScreen(cameras: cams),
    ));
    setState(() => _selected.clear());
    _load();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.red.withOpacity(0.9) : null,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cameras',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
            if (_selected.isNotEmpty)
              Text('${_selected.length} selected',
                style: const TextStyle(fontSize: 11, color: AppColors.red)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.text2),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppColors.text2),
            onPressed: _showAddCamera,
            tooltip: 'Add camera',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: AnimatedScale(
        scale: 1.0,
        duration: const Duration(milliseconds: 200),
        child: _RecordFAB(
          enabled:  _selected.isNotEmpty,
          count:    _selected.length,
          onTap:    _startRecording,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(4, (i) => const _CamSkeleton()),
      );
    }
    if (_error != null) {
      return _ErrorView(
        message: _error!,
        onRetry: _load,
      );
    }
    if (_cameras.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, size: 56, color: AppColors.text3),
            const SizedBox(height: 14),
            const Text('No cameras configured',
              style: TextStyle(fontSize: 16, color: AppColors.text2, fontWeight: FontWeight.w500)),
            const SizedBox(height: 18),
            _PrimaryButton(
              label: 'Add camera',
              icon: Icons.add_rounded,
              onTap: _showAddCamera,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.red,
      backgroundColor: AppColors.bg2,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: _cameras.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final cam = _cameras[i];
          final st  = _statuses[cam.name];
          return _CameraCard(
            camera:     cam,
            status:     st,
            isSelected: _selected.contains(cam.name),
            onTap:      () => _toggle(cam),
          );
        },
      ),
    );
  }

  void _showAddCamera() {
    final nameCtrl  = TextEditingController();
    final urlCtrl   = TextEditingController(text: 'rtsp://admin:pass@192.168.x.x:554/');
    final labelCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add camera',
            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Field(ctrl: nameCtrl,  label: 'Camera ID  (e.g. cam1)'),
              const SizedBox(height: 10),
              _Field(ctrl: labelCtrl, label: 'Display name  (optional)'),
              const SizedBox(height: 10),
              _Field(ctrl: urlCtrl,   label: 'RTSP URL', maxLines: 2),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text2)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              onPressed: saving ? null : () async {
                if (nameCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
                set(() => saving = true);
                try {
                  await ApiService().addCamera(
                    name:    nameCtrl.text.trim(),
                    rtspUrl: urlCtrl.text.trim(),
                    label:   labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  set(() => saving = false);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('$e')));
                  }
                }
              },
              child: saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Camera card ───────────────────────────────────────────────────────────────

class _CameraCard extends StatelessWidget {
  final CameraInfo   camera;
  final RecStatus?   status;
  final bool         isSelected;
  final VoidCallback onTap;

  const _CameraCard({
    required this.camera,
    required this.status,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRec = status?.state == RecState.recording;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.red.withOpacity(0.07)
            : isRec
                ? AppColors.red.withOpacity(0.04)
                : AppColors.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppColors.red.withOpacity(0.45)
              : isRec
                  ? AppColors.red.withOpacity(0.22)
                  : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AppColors.red.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              // ── Check / icon ───────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isSelected
                    ? Container(
                        key: const ValueKey('check'),
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.red,
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                      )
                    : Container(
                        key: const ValueKey('cam'),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.bg3,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.videocam_rounded,
                          size: 18,
                          color: camera.online ? AppColors.text2 : AppColors.text3,
                        ),
                      ),
              ),
              const SizedBox(width: 13),

              // ── Info ──────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(camera.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.text : AppColors.text,
                      )),
                    const SizedBox(height: 3),
                    Text(
                      camera.online
                          ? (camera.resolutionLabel.isNotEmpty
                              ? camera.resolutionLabel
                              : _extractIp(camera.rtspUrl))
                          : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 11,
                        color: camera.online ? AppColors.text3 : AppColors.red.withOpacity(0.7),
                      ),
                    ),
                    // Recording progress
                    if (isRec && status?.elapsedSeconds != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: status?.progress,
                                backgroundColor: AppColors.border2,
                                valueColor: const AlwaysStoppedAnimation(AppColors.red),
                                minHeight: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _fmtElapsed(status!.elapsedSeconds!),
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: AppColors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ── Status pill ────────────────────────────────────────────
              _StatusPill(camera: camera, isRecording: isRec),
            ],
          ),
        ),
      ),
    );
  }

  String _extractIp(String url) {
    try { return Uri.parse(url).host; } catch (_) { return url; }
  }

  String _fmtElapsed(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${_p(h)}:${_p(m)}:${_p(sec)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

class _StatusPill extends StatefulWidget {
  final CameraInfo camera;
  final bool isRecording;
  const _StatusPill({required this.camera, required this.isRecording});

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.isRecording) {
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: 0.5 + 0.5 * _ctrl.value,
          child: _pill(AppColors.red, 'REC'),
        ),
      );
    }
    return _pill(
      widget.camera.online ? AppColors.green : AppColors.text3,
      widget.camera.online ? 'Online' : 'Offline',
    );
  }

  Widget _pill(Color color, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 5, height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 5),
        Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ],
    ),
  );
}

// ── Record FAB ────────────────────────────────────────────────────────────────

class _RecordFAB extends StatefulWidget {
  final bool enabled;
  final int count;
  final VoidCallback onTap;
  const _RecordFAB({required this.enabled, required this.count, required this.onTap});

  @override
  State<_RecordFAB> createState() => _RecordFABState();
}

class _RecordFABState extends State<_RecordFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          decoration: BoxDecoration(
            gradient: widget.enabled
                ? const LinearGradient(
                    colors: [AppColors.red, AppColors.red2],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: widget.enabled ? null : AppColors.bg3,
            borderRadius: BorderRadius.circular(25),
            boxShadow: widget.enabled
                ? [BoxShadow(
                    color: AppColors.red.withOpacity(0.35),
                    blurRadius: 18, offset: const Offset(0, 5))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Opacity(
                  opacity: widget.enabled ? (0.5 + 0.5 * _ctrl.value) : 0.5,
                  child: Container(
                    width: 9, height: 9,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.enabled
                    ? 'Record ${widget.count} camera${widget.count > 1 ? 's' : ''}'
                    : 'Select cameras',
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _CamSkeleton extends StatelessWidget {
  const _CamSkeleton();
  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: AppColors.bg1,
      borderRadius: BorderRadius.circular(14),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.red,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final int maxLines;
  const _Field({required this.ctrl, required this.label, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(color: AppColors.text, fontSize: 13),
    decoration: InputDecoration(labelText: label),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.text3),
        const SizedBox(height: 12),
        const Text('Cannot reach server',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text2)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.text3)),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}
