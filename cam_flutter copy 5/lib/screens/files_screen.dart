import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_theme.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<RecFile>          _files    = [];
  Map<String, RecStatus> _statuses = {};
  bool                   _loading  = true;
  String?                _error;
  String?                _camFilter;
  StreamSubscription?    _wsSub;
  final Map<String, double> _dlProgress = {};

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
      final f = await ApiService().listFiles();
      if (mounted) setState(() { _files = f; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<RecFile>  get _filtered   => _camFilter == null ? _files : _files.where((f) => f.camName == _camFilter).toList();
  List<String>   get _camIds     => _files.map((f) => f.camName).toSet().toList()..sort();
  double         get _totalMb    => _files.fold(0.0, (a, f) => a + f.sizeMb);
  int            get _recCount   => _files.where((f) => f.isRecording).length;

  Future<void> _askDelete(RecFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        content: Text(file.filename,
          style: const TextStyle(color: AppColors.text2, fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text2))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService().deleteFile(file.filename);
      setState(() => _files.removeWhere((f) => f.filename == file.filename));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${file.camName} segment')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'),
            backgroundColor: AppColors.red.withOpacity(0.85)));
      }
    }
  }

  Future<void> _download(RecFile file) async {
    setState(() => _dlProgress[file.filename] = 0.0);
    try {
      final path = await ApiService().downloadFile(
        file.filename,
        onProgress: (p) => setState(() => _dlProgress[file.filename] = p),
      );
      setState(() => _dlProgress.remove(file.filename));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      setState(() => _dlProgress.remove(file.filename));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'),
            backgroundColor: AppColors.red.withOpacity(0.85)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('Recordings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.text2),
            onPressed: _load, tooltip: 'Refresh'),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stats row ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                _StatCard(label: 'Files',     value: '${_files.length}',           color: AppColors.text2),
                const SizedBox(width: 8),
                _StatCard(label: 'Recording', value: '$_recCount',                  color: AppColors.red),
                const SizedBox(width: 8),
                _StatCard(
                  label: 'GB Used',
                  value: (_totalMb / 1000).toStringAsFixed(1),
                  color: AppColors.blue,
                ),
              ],
            ),
          ),

          // ── Filter chips ────────────────────────────────────────────
          if (_camIds.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                children: [
                  _FilterChip(
                    label: 'All', selected: _camFilter == null,
                    onTap: () => setState(() => _camFilter = null)),
                  const SizedBox(width: 6),
                  ..._camIds.map((id) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: id, selected: _camFilter == id,
                      onTap: () => setState(() => _camFilter = id)),
                  )),
                ],
              ),
            ),

          // ── File count label ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              '${_filtered.length} file${_filtered.length != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.text3)),
          ),

          // ── Grid ────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.red))
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? const _EmptyState()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppColors.red,
                            backgroundColor: AppColors.bg2,
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final f = _filtered[i];
                                return _FileCard(
                                  file:             f,
                                  liveStatus:       _statuses[f.camName],
                                  downloadProgress: _dlProgress[f.filename],
                                  onDelete:         () => _askDelete(f),
                                  onDownload:       () => _download(f),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.text3)),
        ],
      ),
    ),
  );
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? AppColors.red.withOpacity(0.10) : AppColors.bg1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.red.withOpacity(0.38) : AppColors.border,
        ),
      ),
      child: Text(label,
        style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: selected ? AppColors.red : AppColors.text3)),
    ),
  );
}

// ── File card ─────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final RecFile      file;
  final RecStatus?   liveStatus;
  final double?      downloadProgress;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  const _FileCard({
    required this.file,
    required this.liveStatus,
    required this.downloadProgress,
    required this.onDelete,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isRec  = file.isRecording;
    final isDl   = downloadProgress != null;
    final prog   = liveStatus?.progress ?? 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isRec ? AppColors.red.withOpacity(0.04) : AppColors.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRec ? AppColors.red.withOpacity(0.3) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Thumbnail area ─────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.bg2,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                  ),
                  child: const Icon(Icons.movie_rounded, size: 32, color: AppColors.border2),
                ),
                // Gradient
                Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC080A0E)],
                      stops: [0.3, 1.0],
                    ),
                  ),
                ),
                // REC badge
                if (isRec) const Positioned(top: 7, left: 7, child: _RecBadge()),
                // Duration
                Positioned(
                  bottom: 6, right: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(file.durationLabel,
                      style: const TextStyle(fontSize: 9, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),

          // ── Info ──────────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cam badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bg3,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(file.camName.toUpperCase(),
                      style: const TextStyle(fontSize: 9, color: AppColors.text2,
                          fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 3),
                  // Filename
                  Text(file.filename,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                        color: AppColors.text),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  // Progress (recording)
                  if (isRec) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: prog, minHeight: 2,
                        backgroundColor: AppColors.border2,
                        valueColor: const AlwaysStoppedAnimation(AppColors.red),
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text('Recording…',
                      style: TextStyle(fontSize: 9, color: AppColors.red)),
                  ],
                  // Download progress
                  if (isDl) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: downloadProgress, minHeight: 3,
                        backgroundColor: AppColors.border2,
                        valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('${((downloadProgress ?? 0) * 100).toInt()}%',
                      style: const TextStyle(fontSize: 9, color: AppColors.blue)),
                  ],
                  // Meta row
                  Row(
                    children: [
                      Text(file.sizeLabel,
                        style: const TextStyle(fontSize: 9, color: AppColors.text3)),
                      const Spacer(),
                      Text(file.dateLabel,
                        style: const TextStyle(fontSize: 9, color: AppColors.text3)),
                    ],
                  ),
                  // Action buttons
                  if (!isRec && !isDl) ...[
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionBtn(
                            icon: Icons.download_outlined,
                            onTap: onDownload,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: _ActionBtn(
                            icon: Icons.delete_outline_rounded,
                            danger: true,
                            onTap: onDelete,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final bool     danger;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border2),
      ),
      child: Icon(icon, size: 13,
        color: danger ? AppColors.red : AppColors.text2),
    ),
  );
}

// ── REC badge ─────────────────────────────────────────────────────────────────

class _RecBadge extends StatefulWidget {
  const _RecBadge();
  @override
  State<_RecBadge> createState() => _RecBadgeState();
}

class _RecBadgeState extends State<_RecBadge>
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Opacity(
      opacity: 0.5 + 0.5 * _ctrl.value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 5, height: 5,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            const SizedBox(width: 3),
            const Text('REC',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    ),
  );
}

// ── Empty + Error ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_open_rounded, size: 52, color: AppColors.text3),
        SizedBox(height: 12),
        Text('No recordings', style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.w500)),
        SizedBox(height: 4),
        Text('Go to Cameras to start', style: TextStyle(fontSize: 12, color: AppColors.text3)),
      ],
    ),
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
        const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.text3),
        const SizedBox(height: 12),
        const Text('Could not load files', style: TextStyle(color: AppColors.text2)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.text3)),
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
