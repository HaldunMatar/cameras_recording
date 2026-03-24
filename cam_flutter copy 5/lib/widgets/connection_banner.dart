import 'package:flutter/material.dart';
import '../services/app_theme.dart';

/// Shows a non-intrusive banner when the server is unreachable.
class ConnectionBanner extends StatelessWidget {
  final bool connected;
  final String serverIp;
  const ConnectionBanner({
    super.key,
    required this.connected,
    required this.serverIp,
  });

  @override
  Widget build(BuildContext context) {
    if (connected && serverIp.isNotEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: serverIp.isEmpty
          ? AppColors.bg3
          : AppColors.red.withOpacity(0.15),
      child: Row(
        children: [
          Icon(
            serverIp.isEmpty ? Icons.settings_rounded : Icons.cloud_off_rounded,
            size: 14,
            color: serverIp.isEmpty ? AppColors.text3 : AppColors.red,
          ),
          const SizedBox(width: 8),
          Text(
            serverIp.isEmpty
                ? 'Set server IP in Settings'
                : 'Cannot reach $serverIp — check VPN',
            style: TextStyle(
              fontSize: 11,
              color: serverIp.isEmpty ? AppColors.text3 : AppColors.red,
            ),
          ),
        ],
      ),
    );
  }
}
