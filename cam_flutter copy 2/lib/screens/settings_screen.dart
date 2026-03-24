import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ipCtrl   = TextEditingController();
  final _portCtrl = TextEditingController();
  Map<String, dynamic>? _health;
  bool _checking = false;
  bool _saving   = false;

  @override
  void initState() {
    super.initState();
    _ipCtrl.text   = ApiService().ip;
    _portCtrl.text = ApiService().port;
    _checkHealth();
  }

  @override
  void dispose() { _ipCtrl.dispose(); _portCtrl.dispose(); super.dispose(); }

  Future<void> _checkHealth() async {
    setState(() => _checking = true);
    try {
      final h = await ApiService().health();
      if (mounted) setState(() { _health = h; _checking = false; });
    } catch (e) {
      if (mounted) setState(() { _health = {'error': e.toString()}; _checking = false; });
    }
  }

  Future<void> _save() async {
    final ip   = _ipCtrl.text.trim();
    final port = _portCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() => _saving = true);
    await ApiService().saveConfig(ip, port);
    setState(() => _saving = false);
    _checkHealth();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Server connection ──────────────────────────────────────
          _SectionCard(
            title: 'Server connection',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(ctrl: _ipCtrl,   label: 'Server IP / hostname',
                  hint: '100.74.149.25'),
                const SizedBox(height: 10),
                _Field(ctrl: _portCtrl, label: 'Port', hint: '8765',
                  keyboardType: TextInputType.number),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.red,
                          minimumSize: const Size.fromHeight(42)),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save & connect',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text2,
                        side: const BorderSide(color: AppColors.border2),
                        minimumSize: const Size(90, 42)),
                      onPressed: _checking ? null : _checkHealth,
                      child: _checking
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text3))
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

          // ── Server info ────────────────────────────────────────────
          _SectionCard(
            title: 'Network info',
            child: Column(
              children: const [
                _InfoRow(label: 'Protocol',  value: 'HTTP + WebSocket'),
                _InfoRow(label: 'API port',  value: '8765'),
                _InfoRow(label: 'VPN',       value: 'Direct access — no port forwarding'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── App info ───────────────────────────────────────────────
          Center(
            child: Text('Camera Recorder v1.0',
              style: const TextStyle(fontSize: 11, color: AppColors.text3))),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

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
  final TextInputType? keyboardType;
  const _Field({required this.ctrl, required this.label, this.hint = '', this.keyboardType});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    style: const TextStyle(color: AppColors.text, fontSize: 13),
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
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
