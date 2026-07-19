import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_theme.dart';
import 'settings_screen.dart' show ScpConfig;

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<RecFile>             _files      = [];
  Map<String, RecStatus>    _statuses   = {};
  bool                      _loading    = true;
  String?                   _error;
  String?                   _camFilter;
  StreamSubscription?       _wsSub;
  final Map<String, double> _dlProgress = {};

  @override
  void initState() {
    super.initState();
    _wsSub = ApiService().statusStream.listen(
        (s) { if (mounted) setState(() => _statuses = s); });
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

  List<RecFile> get _filtered => _camFilter == null
      ? _files
      : _files.where((f) => f.camName == _camFilter).toList();

  List<String> get _camIds =>
      _files.map((f) => f.camName).toSet().toList()..sort();

  double get _totalMb  => _files.fold(0.0, (a, f) => a + f.sizeMb);
  int    get _recCount => _files.where((f) => f.isRecording).length;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _askDelete(RecFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?',
          style: TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w700)),
        content: Text(file.filename,
          style: const TextStyle(color: AppColors.text2, fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppColors.text2))),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: AppColors.red.withOpacity(0.85)));
      }
    }
  }

  Future<void> _download(RecFile file) async {
    setState(() => _dlProgress[file.filename] = 0.0);
    try {
      final path = await ApiService().downloadFile(
        file.filename,
        onProgress: (p) =>
            setState(() => _dlProgress[file.filename] = p),
      );
      setState(() => _dlProgress.remove(file.filename));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(kIsWeb
              ? 'Download started in browser'
              : 'Saved to $path')));
      }
    } catch (e) {
      setState(() => _dlProgress.remove(file.filename));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: AppColors.red.withOpacity(0.85)));
      }
    }
  }

  void _showScpSheet(RecFile file) {
    final cmd = ScpConfig().scpCommand(file.filename);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ScpSheet(filename: file.filename, command: cmd),
    );
  }

  void _showDeleteRangeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _DeleteRangeSheet(
        camIds: _camIds,
        onDeleted: (count) {
          _load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Deleted $count file${count != 1 ? 's' : ''}'),
            ));
          }
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('Recordings',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700,
              color: AppColors.text)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.red),
            onPressed: _camIds.isEmpty ? null : _showDeleteRangeSheet,
            tooltip: 'Delete by date range'),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.text2),
            onPressed: _load, tooltip: 'Refresh'),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Stats row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                _StatCard(label: 'Files',
                    value: '${_files.length}', color: AppColors.text2),
                const SizedBox(width: 8),
                _StatCard(label: 'Recording',
                    value: '$_recCount', color: AppColors.red),
                const SizedBox(width: 8),
                _StatCard(
                    label: 'GB Used',
                    value: (_totalMb / 1000).toStringAsFixed(1),
                    color: AppColors.blue),
              ],
            ),
          ),

          // ── Filter chips ───────────────────────────────────────────────
          if (_camIds.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                children: [
                  _FilterChip(label: 'All',
                      selected: _camFilter == null,
                      onTap: () => setState(() => _camFilter = null)),
                  const SizedBox(width: 6),
                  ..._camIds.map((id) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                        label: id,
                        selected: _camFilter == id,
                        onTap: () => setState(() => _camFilter = id)),
                  )),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              '${filtered.length} file${filtered.length != 1 ? 's' : ''}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.text3)),
          ),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.red))
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _load)
                    : filtered.isEmpty
                        ? const _EmptyState()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppColors.red,
                            backgroundColor: AppColors.bg2,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _FileCard(
                                file:   filtered[i],
                                status: _statuses[filtered[i].camName],
                                dlProg: _dlProgress[filtered[i].filename],
                                onDelete:   () => _askDelete(filtered[i]),
                                onDownload: () => _download(filtered[i]),
                                onScp:      () => _showScpSheet(filtered[i]),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delete by date range — bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DeleteRangeSheet extends StatefulWidget {
  final List<String>        camIds;
  final void Function(int)  onDeleted;

  const _DeleteRangeSheet({
    required this.camIds,
    required this.onDeleted,
  });

  @override
  State<_DeleteRangeSheet> createState() => _DeleteRangeSheetState();
}

class _DeleteRangeSheetState extends State<_DeleteRangeSheet> {
  late String   _selectedCam;
  DateTime      _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime      _toDate   = DateTime.now();
  bool          _loading  = false;
  String?       _result;
  bool          _isError  = false;

  @override
  void initState() {
    super.initState();
    _selectedCam = widget.camIds.first;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.red,
            surface: AppColors.bg2,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
      } else {
        _toDate = picked;
        if (_fromDate.isAfter(_toDate)) _fromDate = _toDate;
      }
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm deletion',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        content: Text(
          'Delete all recordings for "$_selectedCam"
'
          'from ${_fmt(_fromDate)} to ${_fmt(_toDate)}?

'
          'This cannot be undone.',
          style: const TextStyle(color: AppColors.text2, fontSize: 13)),
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
    if (confirmed != true) return;

    setState(() { _loading = true; _result = null; });
    try {
      final res = await ApiService().deleteFilesByRange(
        camName:  _selectedCam,
        fromDate: _fromDate,
        toDate:   _toDate,
      );
      final deleted = res['deleted_count'] as int;
      final skipped = res['skipped_count'] as int;
      setState(() {
        _loading = false;
        _isError = false;
        _result  = 'Deleted $deleted file${deleted != 1 ? 's' : ''}'
            '${skipped > 0 ? ' · $skipped skipped (recording)' : ''}';
      });
      widget.onDeleted(deleted);
    } catch (e) {
      setState(() {
        _loading = false;
        _isError = true;
        _result  = e.toString();
      });
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text('Delete by Date Range',
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.text)),
          const SizedBox(height: 4),
          const Text('Removes all segments for a camera within a date window.',
            style: TextStyle(fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 20),

          // Camera picker
          const Text('CAMERA',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: AppColors.text3, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.bg1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border2)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCam,
                isExpanded: true,
                dropdownColor: AppColors.bg2,
                style: const TextStyle(color: AppColors.text, fontSize: 14),
                items: widget.camIds.map((id) =>
                  DropdownMenuItem(value: id, child: Text(id))).toList(),
                onChanged: (v) { if (v != null) setState(() => _selectedCam = v); },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Date range row
          Row(
            children: [
              Expanded(child: _DateTile(
                label: 'FROM',
                date: _fromDate,
                onTap: () => _pickDate(isFrom: true),
              )),
              const SizedBox(width: 12),
              Expanded(child: _DateTile(
                label: 'TO',
                date: _toDate,
                onTap: () => _pickDate(isFrom: false),
              )),
            ],
          ),
          const SizedBox(height: 20),

          // Result message
          if (_result != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: _isError
                    ? AppColors.red.withOpacity(0.08)
                    : AppColors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isError
                      ? AppColors.red.withOpacity(0.3)
                      : AppColors.blue.withOpacity(0.3)),
              ),
              child: Text(_result!,
                style: TextStyle(
                  fontSize: 13,
                  color: _isError ? AppColors.red : AppColors.blue)),
            ),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text2,
                    side: const BorderSide(color: AppColors.border2),
                    minimumSize: const Size.fromHeight(46)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                    minimumSize: const Size.fromHeight(46)),
                  onPressed: _loading ? null : _delete,
                  icon: _loading
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: Text(_loading ? 'Deleting…' : 'Delete Files')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String   label;
  final DateTime date;
  final VoidCallback onTap;
  const _DateTile({required this.label, required this.date, required this.onTap});

  String get _fmt =>
      '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: AppColors.text3, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 13, color: AppColors.text2),
              const SizedBox(width: 6),
              Text(_fmt,
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.text)),
            ],
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// File card — horizontal list item
// ─────────────────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final RecFile      file;
  final RecStatus?   status;
  final double?      dlProg;
  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final VoidCallback onScp;

  const _FileCard({
    required this.file,
    required this.status,
    required this.dlProg,
    required this.onDelete,
    required this.onDownload,
    required this.onScp,
  });

  @override
  Widget build(BuildContext context) {
    final isRec  = file.isRecording;
    final isDl   = dlProg != null;
    final prog   = status?.progress ?? 0.0;
    final scpCmd = ScpConfig().scpCommand(file.filename);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isRec ? AppColors.red.withOpacity(0.04) : AppColors.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRec
              ? AppColors.red.withOpacity(0.3)
              : AppColors.border),
      ),
      child: Column(
        children: [

          // ── Main row ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                // Icon / badge
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: isRec
                        ? AppColors.red.withOpacity(0.12)
                        : AppColors.bg2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isRec
                      ? const _RecBadge()
                      : const Icon(Icons.movie_rounded,
                          size: 20, color: AppColors.border2),
                ),
                const SizedBox(width: 12),

                // File info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Badge(file.camName.toUpperCase()),
                          const SizedBox(width: 5),
                          _Badge(
                            file.filename.endsWith('.ts') ? 'TS' : 'MP4',
                            color: AppColors.blue,
                          ),
                          const Spacer(),
                          Text(file.sizeLabel,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.text3)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(file.filename,
                        style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: AppColors.text),
                        overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('${file.dateLabel}  ·  ${file.durationLabel}',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.text3)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Action buttons
                if (!isRec && !isDl)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconBtn(
                        icon: Icons.download_outlined,
                        onTap: onDownload,
                        tooltip: 'Download',
                      ),
                      const SizedBox(width: 6),
                      _IconBtn(
                        icon: Icons.delete_outline_rounded,
                        danger: true,
                        onTap: onDelete,
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ── Recording / download progress bar ──────────────────────
          if (isRec || isDl)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: isRec ? prog : dlProg,
                      minHeight: 3,
                      backgroundColor: AppColors.border2,
                      valueColor: AlwaysStoppedAnimation(
                          isRec ? AppColors.red : AppColors.blue),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        isRec ? 'Recording…' : 'Downloading…',
                        style: TextStyle(
                          fontSize: 10,
                          color: isRec ? AppColors.red : AppColors.blue)),
                      const Spacer(),
                      Text(
                        isRec
                            ? '${(prog * 100).toInt()}%'
                            : '${((dlProg ?? 0) * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 10,
                          color: isRec ? AppColors.red : AppColors.blue)),
                    ],
                  ),
                ],
              ),
            ),

          // ── SCP command row ────────────────────────────────────────
          GestureDetector(
            onTap: onScp,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terminal_rounded,
                      size: 11, color: AppColors.text3),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      scpCmd ?? '⚠ Configure SCP in Settings',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: scpCmd != null
                            ? AppColors.text2
                            : AppColors.red.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_all_rounded,
                      size: 13, color: AppColors.text3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCP bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ScpSheet extends StatelessWidget {
  final String  filename;
  final String? command;

  const _ScpSheet({required this.filename, required this.command});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('SCP command',
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.text)),
          const SizedBox(height: 4),
          Text(filename,
            style: const TextStyle(fontSize: 11, color: AppColors.text3)),
          const SizedBox(height: 14),

          if (command == null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.red.withOpacity(0.25))),
              child: const Text(
                'SCP not configured.
'
                'Go to Settings → SCP / SSH and fill in:
'
                '  • SSH user
'
                '  • Server host / IP
'
                '  • Remote recordings folder
'
                '  • Local destination folder',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.red,
                minimumSize: const Size.fromHeight(44)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg0,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border2)),
              child: SelectableText(
                command!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.text2,
                  height: 1.5),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Long-press to select text, or tap Copy.',
              style: TextStyle(fontSize: 11, color: AppColors.text3)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text2,
                      side: const BorderSide(color: AppColors.border2),
                      minimumSize: const Size.fromHeight(44)),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red,
                      minimumSize: const Size.fromHeight(44)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: command!));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('SCP command copied'),
                          duration: Duration(seconds: 2)));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String text;
  final Color  color;
  const _Badge(this.text, {this.color = AppColors.text3});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(text,
      style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 0.4)),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool     danger;
  final String   tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border2)),
        child: Icon(icon, size: 15,
          color: danger ? AppColors.red : AppColors.text2),
      ),
    ),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatCard({
    required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
            style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.text3)),
        ],
      ),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label, required this.selected, required this.onTap});

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
          color: selected
              ? AppColors.red.withOpacity(0.38)
              : AppColors.border)),
      child: Text(label,
        style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: selected ? AppColors.red : AppColors.text3)),
    ),
  );
}

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
      child: const Icon(Icons.fiber_manual_record,
          size: 18, color: AppColors.red),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_open_rounded, size: 52, color: AppColors.text3),
        SizedBox(height: 12),
        Text('No recordings',
          style: TextStyle(
              color: AppColors.text2, fontWeight: FontWeight.w500)),
        SizedBox(height: 4),
        Text('Go to Cameras to start',
          style: TextStyle(fontSize: 12, color: AppColors.text3)),
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
        const Icon(Icons.cloud_off_rounded,
            size: 48, color: AppColors.text3),
        const SizedBox(height: 12),
        const Text('Could not load files',
          style: TextStyle(color: AppColors.text2)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message,
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
