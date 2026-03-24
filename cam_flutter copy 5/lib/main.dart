import 'dart:async';
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
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:          Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg1,
  ));
  ApiService().connectWS();
  runApp(const CamRecorderApp());
}

class CamRecorderApp extends StatelessWidget {
  const CamRecorderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title:                    'Camera Recorder',
    debugShowCheckedModeBanner: false,
    theme:                    AppTheme.dark,
    home:                     const AppShell(),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int  _index     = 0;
  bool _connected = false;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _pollHealth();
    _healthTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollHealth());
  }

  @override
  void dispose() { _healthTimer?.cancel(); super.dispose(); }

  Future<void> _pollHealth() async {
    try {
      await ApiService().health();
      if (mounted) setState(() => _connected = true);
    } catch (_) {
      if (mounted) setState(() => _connected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ip = ApiService().ip;
    return Scaffold(
      body: Column(
        children: [
          ConnectionBanner(connected: _connected, serverIp: ip),
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
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          height: 62,
          destinations: const [
            NavigationDestination(
              icon:         Icon(Icons.videocam_outlined),
              selectedIcon: Icon(Icons.videocam),
              label:        'Cameras',
            ),
            NavigationDestination(
              icon:         Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label:        'Files',
            ),
            NavigationDestination(
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
