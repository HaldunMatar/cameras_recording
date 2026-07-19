import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/app_theme.dart';

// ── SCP config singleton ──────────────────────────────────────────────────────
// Stores the 4 fields needed to build the scp command shown on each file card.

class ScpConfig {
  static final ScpConfig _i = ScpConfig._();
  factory ScpConfig() => _i;
  ScpConfig._();

  String sshUser      = '';   // e.g. mini
  String sshHost      = '';   // e.g. 100.121.60.36
  String remotePath   = '';   // e.g. /home/mini/cam_recorder/recordings
  String localPath    = '';   // e.g. /Users/me/projects/videos

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sshUser    = p.getString('scp_user')    ?? '';
    sshHost    = p.getString('scp_host')    ?? '';
    remotePath = p.getString('scp_remote')  ?? '';
    localPath  = p.getString('scp_local')   ?? '';
  }

  Future<void> save({
    required String user,
    required String host,
    required String remote,
    required String local,
  }) async {
    sshUser    = user;
    sshHost    = host;
    remotePath = remote;
    localPath  = local;
    final p = await SharedPreferences.getInstance();
    await p.setString('scp_user',   user);
    await p.setString('scp_host',   host);
    await p.setString('scp_remote', remote);
    await p.setString('scp_local',  local);
  }

  /// Build the scp command for a given filename.
  /// Returns null if any field is missing.
  String? scpCommand(String filename) {
    if (sshUser.isEmpty || sshHost.isEmpty ||
        remotePath.isEmpty || localPath.isEmpty) return null;
    final remote = remotePath.endsWith('/')
        ? '$remotePath$filename'
        : '$remotePath/$filename';
    return 'scp $sshUser@$sshHost:$remote $localPath';
  }

  bool get configured =>
      sshUser.isNotEmpty && sshHost.isNotEmpty &&
      remotePath.isNotEmpty && localPath.isNotEmpty;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // API
  final _ipCtrl   = TextEditingController();
  final _portCtrl = TextEditingController();
  Map<String, dynamic>? _health;
  bool _checking = false;
  bool _savingApi = false;

  // SCP
  final _userCtrl   = TextEditingController();
  final _hostCtrl   = TextEditingController();
  final _remoteCtrl = TextEditingController();
  final _localCtrl  = TextEditingController();
  bool _savingScp = false;

  /// Returns the Tailscale IP from the browser URL if not already configured.
  String _detectServerIp(String savedIp) {
    if (savedIp.isNotEmpty) return savedIp;
    final host = Uri.base.host;
    if (host.startsWith('100.')) return host;
    return savedIp;
  }

  @override
  void initState() {
    super.initState();
    final api = ApiService();
    _ipCtrl.text   = _detectServerIp(api.ip);
    _portCtrl.text = api.port;

    final scp = ScpConfig();
    _userCtrl.text   = scp.sshUser;
    _hostCtrl.text   = scp.sshHost;
    _remoteCtrl.text = scp.remotePath;
    _localCtrl.text  = scp.localPath;


    _loadFromServer();

    _checkHealth();
  }

  @override
  void dispose() {
    _ipCtrl.dispose(); _portCtrl.dispose();
    _userCtrl.dispose(); _hostCtrl.dispose();
    _remoteCtrl.dispose(); _localCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    setState(() => _checking = true);
    try {
      final h = await ApiService().health();
      if (mounted) setState(() { _health = h; _checking = false; });
    } catch (e) {
      if (mounted) setState(() {
        _health = {'error': e.toString()}; _checking = false;
      });
    }
  }

  Future<void> _saveApi() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() => _savingApi = true);
    await ApiService().saveConfig(ip, _portCtrl.text.trim());
    setState(() => _savingApi = false);
    _checkHealth();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API settings saved')));
    }
  }
// في initState — بعد تحميل الـ API settings العادية:

Future<void> _loadFromServer() async {
  try {
    final cfg = await ApiService().loadRemoteConfig();
    setState(() {
      _userCtrl.text   = cfg['scp_user']   ?? '';
      _hostCtrl.text   = cfg['scp_host']   ?? '';
      _remoteCtrl.text = cfg['scp_remote'] ?? '';
      _localCtrl.text  = cfg['scp_local']  ?? '';
    });
    // حدّث ScpConfig singleton أيضاً
    ScpConfig()
      ..sshUser    = cfg['scp_user']   ?? ''
      ..sshHost    = cfg['scp_host']   ?? ''
      ..remotePath = cfg['scp_remote'] ?? ''
      ..localPath  = cfg['scp_local']  ?? '';
  } catch (_) {}
}

Future<void> _saveScp() async {
  setState(() => _savingScp = true);
  // احفظ محلياً
  await ScpConfig().save(
    user:   _userCtrl.text.trim(),
    host:   _hostCtrl.text.trim(),
    remote: _remoteCtrl.text.trim(),
    local:  _localCtrl.text.trim(),
  );
  // واحفظ على السيرفر
  try {
    await ApiService().saveRemoteConfig({
      'server_ip':   ApiService().ip,
      'server_port': ApiService().port,
      'scp_user':    _userCtrl.text.trim(),
      'scp_host':    _hostCtrl.text.trim(),
      'scp_remote':  _remoteCtrl.text.trim(),
      'scp_local':   _localCtrl.text.trim(),
    });
  } catch (_) {} // إذا فشل السيرفر، الإعدادات المحلية محفوظة
  setState(() => _savingScp = false);
}


  // Preview scp command with a placeholder filename
  String get _scpPreview {
    final scp = ScpConfig()
      ..sshUser    = _userCtrl.text.trim()
      ..sshHost    = _hostCtrl.text.trim()
      ..remotePath = _remoteCtrl.text.trim()
      ..localPath  = _localCtrl.text.trim();
    return scp.scpCommand('entrance1_2025-06-11_09-00-00.ts')
        ?? 'Fill all fields to see preview';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('Settings',
          style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── API connection ────────────────────────────────────────────
          _SectionCard(
            title: 'Server API',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(ctrl: _ipCtrl,   label: 'Server IP / hostname',
                  hint: '100.74.149.25'),
                const SizedBox(height: 10),
                _Field(ctrl: _portCtrl, label: 'API port', hint: '8765',
                  keyboard: TextInputType.number),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.red,
                          minimumSize: const Size.fromHeight(42)),
                        onPressed: _savingApi ? null : _saveApi,
                        child: _savingApi
                            ? const _Spinner()
                            : const Text('Save & connect',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text2,
                        side: const BorderSide(color: AppColors.border2),
                        minimumSize: const Size(80, 42)),
                      onPressed: _checking ? null : _checkHealth,
                      child: _checking
                          ? const _Spinner()
                          : const Text('Test'),
                    ),
                  ],
                ),
                if (_health != null) ...[
                  const SizedBox(height: 12),
                  _HealthBanner(health: _health!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── SCP settings ──────────────────────────────────────────────
          _SectionCard(
            title: 'SCP / SSH (for file copy commands)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Field(ctrl: _userCtrl, label: 'SSH user',
                        hint: 'mini')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Field(ctrl: _hostCtrl, label: 'Server host / IP',
                        hint: '100.121.60.36')),
                  ],
                ),
                const SizedBox(height: 10),
                _Field(ctrl: _remoteCtrl,
                  label: 'Remote recordings folder',
                  hint: '/home/mini/cam_recorder/recordings'),
                const SizedBox(height: 10),
                _Field(ctrl: _localCtrl,
                  label: 'Local destination folder',
                  hint: '/Users/me/projects/videos'),
                const SizedBox(height: 14),

                // Live preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bg0,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Preview',
                        style: TextStyle(fontSize: 9, color: AppColors.text3,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      SelectableText(
                        _scpPreview,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11, color: AppColors.text2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                    minimumSize: const Size.fromHeight(42)),
                  onPressed: _savingScp ? null : _saveScp,
                  child: _savingScp
                      ? const _Spinner()
                      : const Text('Save SCP settings',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Info ──────────────────────────────────────────────────────
          _SectionCard(
            title: 'Network',
            child: Column(
              children: const [
                _InfoRow(label: 'Protocol',  value: 'HTTP + WebSocket'),
                _InfoRow(label: 'API port',  value: '8765'),
                _InfoRow(label: 'VPN',       value: 'Direct — no port forwarding'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Center(
            child: Text('Camera Recorder v1.0',
              style: TextStyle(fontSize: 11, color: AppColors.text3))),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.bg1,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final TextInputType? keyboard;
  const _Field({
    required this.ctrl,
    required this.label,
    this.hint = '',
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: keyboard,
    style: const TextStyle(color: AppColors.text, fontSize: 13),
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 16, height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}

class _HealthBanner extends StatelessWidget {
  final Map<String, dynamic> health;
  const _HealthBanner({required this.health});

  @override
  Widget build(BuildContext context) {
    final hasError = health.containsKey('error');
    final color    = hasError ? AppColors.red : AppColors.green;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(hasError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasError
                  ? 'Unreachable: ${health['error']}'
                  : 'Connected · ${health['cameras']} cameras · '
                    '${health['active_recordings']} recording · '
                    '${health['storage_free_gb']} GB free',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
      ],
    ),
  );
}
