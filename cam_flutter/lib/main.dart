import 'dart:async';
import 'package:cam_recorder/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'services/app_theme.dart';
import 'screens/cameras_screen.dart';
import 'screens/files_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/connection_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().loadConfig();
  await ScpConfig().load();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:           Colors.transparent,
    statusBarIconBrightness:  Brightness.light,
    systemNavigationBarColor: AppColors.bg1,
  ));
  ApiService().connectWS();
  runApp(const CamRecorderApp());
}

class CamRecorderApp extends StatelessWidget {
  const CamRecorderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title:                     'Camera Recorder',
    debugShowCheckedModeBanner: false,
    theme:                     AppTheme.dark,
    home:                      const AppShell(),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int                    _index     = 0;
  bool                   _connected = false;
  Timer?                 _healthTimer;
  Map<String, RecStatus> _statuses  = {};
  StreamSubscription?    _wsSub;
  bool                   _stopping  = false;

  @override
  void initState() {
    super.initState();
    _pollHealth();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 15), (_) => _pollHealth());

    // Subscribe to WS status — drives the global Stop All bar
    _wsSub = ApiService().statusStream.listen((s) {
      if (mounted) setState(() => _statuses = s);
    });
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _pollHealth() async {
    try {
      await ApiService().health();
      if (mounted) setState(() => _connected = true);
    } catch (_) {
      if (mounted) setState(() => _connected = false);
    }
  }

  // ── Active recordings count ────────────────────────────────────────────────
  int get _activeCount => _statuses.values
      .where((s) => s.isActive)
      .length;

  // ── Stop ALL — works from any tab, foreground or background ───────────────
  Future<void> _stopAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop all recordings?',
          style: TextStyle(
            color: AppColors.text, fontWeight: FontWeight.w700)),
        content: Text(
          '$_activeCount active recording${_activeCount > 1 ? 's' : ''} will be stopped '
          'and files will be saved on the server.',
          style: const TextStyle(color: AppColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppColors.text2))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop all')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _stopping = true);
    try {
      await ApiService().stopAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stop failed: $e'),
            backgroundColor: AppColors.red.withOpacity(0.85)));
      }
    }
    if (mounted) setState(() => _stopping = false);
    _pollHealth();
  }

  @override
  Widget build(BuildContext context) {
    final ip      = ApiService().ip;
    final hasRec  = _activeCount > 0;

    return Scaffold(
      body: Column(
        children: [
          // ── Server connection banner ──────────────────────────────────
          ConnectionBanner(connected: _connected, serverIp: ip),

          // ── Main screens ──────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                CamerasScreen(),
                FilesScreen(),
                SettingsScreen(),
              ],
            ),
          ),

          // ── GLOBAL STOP ALL BAR ───────────────────────────────────────
          // Appears above the bottom nav whenever any recording is active.
          // Works from any tab — even after dismissing the session screen.
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: hasRec
                ? _StopAllBar(
                    count:    _activeCount,
                    stopping: _stopping,
                    onStop:   _stopAll,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),

      // ── Bottom navigation ─────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          height: 62,
          destinations: [
            const NavigationDestination(
              icon:         Icon(Icons.videocam_outlined),
              selectedIcon: Icon(Icons.videocam),
              label:        'Cameras',
            ),
            // Badge on Files tab when recording is active
            NavigationDestination(
              icon: Badge(
                isLabelVisible: hasRec,
                backgroundColor: AppColors.red,
                label: Text('$_activeCount',
                  style: const TextStyle(fontSize: 9, color: Colors.white)),
                child: const Icon(Icons.folder_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: hasRec,
                backgroundColor: AppColors.red,
                label: Text('$_activeCount',
                  style: const TextStyle(fontSize: 9, color: Colors.white)),
                child: const Icon(Icons.folder),
              ),
              label: 'Files',
            ),
            const NavigationDestination(
              icon:         Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label:        'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Global Stop All bar — slides in above the bottom nav
// ─────────────────────────────────────────────────────────────────────────────

class _StopAllBar extends StatefulWidget {
  final int          count;
  final bool         stopping;
  final VoidCallback onStop;

  const _StopAllBar({
    required this.count,
    required this.stopping,
    required this.onStop,
  });

  @override
  State<_StopAllBar> createState() => _StopAllBarState();
}

class _StopAllBarState extends State<_StopAllBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        border: const Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          // Pulsing dot
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.red,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.red.withOpacity(0.4 + 0.4 * _pulse.value),
                    blurRadius: 6),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Label
          Expanded(
            child: Text(
              widget.stopping
                  ? 'Stopping recordings…'
                  : '${widget.count} recording${widget.count > 1 ? 's' : ''} active',
              style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.text),
            ),
          ),

          // Stop All button
          GestureDetector(
            onTap: widget.stopping ? null : widget.onStop,
            child: AnimatedOpacity(
              opacity: widget.stopping ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.red.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stop_rounded,
                        size: 14, color: AppColors.red),
                    const SizedBox(width: 5),
                    Text(
                      widget.stopping ? 'Stopping…' : 'Stop all',
                      style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: AppColors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
