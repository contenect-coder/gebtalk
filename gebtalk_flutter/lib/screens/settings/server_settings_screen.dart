import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/api_service.dart';
import '../../theme/colors.dart';
import '../../utils/error_handler.dart';

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  bool? _isOnline;
  String? _testMessage;

  static const String liveTunnelUrl = 'https://commission-livecam-able-condition.trycloudflare.com/api';
  static const String localWifiUrl = 'http://192.168.1.22:5000/api';

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ApiService.baseUrl);
    _testCurrentConnection();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testCurrentConnection([String? specificUrl]) async {
    final target = specificUrl ?? _urlController.text.trim();
    if (target.isEmpty) return;

    setState(() {
      _isTesting = true;
      _testMessage = 'Connecting...';
    });

    final stopwatch = Stopwatch()..start();
    final ok = await ApiService.testEndpoint(target);
    stopwatch.stop();

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _isOnline = ok;
      _testMessage = ok 
          ? 'Connected successfully (${stopwatch.elapsedMilliseconds}ms)' 
          : 'Failed to reach server. Check URL or tunnel.';
    });
  }

  Future<void> _applyUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      ErrorHandler.showError('Server URL cannot be empty');
      return;
    }

    await ApiService.setCustomBaseUrl(cleanUrl);
    _urlController.text = ApiService.baseUrl;

    if (!mounted) return;
    ErrorHandler.showSuccess('Server connected to: ${ApiService.baseUrl}');

    // Refresh state in background
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.fetchContacts();
    } catch (_) {}

    _testCurrentConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Server Connection',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isOnline == true
                    ? Colors.greenAccent.withValues(alpha: 0.3)
                    : (_isOnline == false ? Colors.redAccent.withValues(alpha: 0.3) : Colors.white10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isOnline == true
                          ? Icons.check_circle_rounded
                          : (_isOnline == false ? Icons.error_rounded : Icons.sync_rounded),
                      color: _isOnline == true
                          ? Colors.greenAccent
                          : (_isOnline == false ? Colors.redAccent : Colors.orangeAccent),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isOnline == true
                            ? 'Server Online'
                            : (_isOnline == false ? 'Connection Offline' : 'Checking Connection...'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_isTesting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                        tooltip: 'Retest Connection',
                        onPressed: () => _testCurrentConnection(),
                      ),
                  ],
                ),
                if (_testMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _testMessage!,
                    style: TextStyle(
                      color: _isOnline == true ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Active: ${ApiService.baseUrl}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'QUICK PRESETS',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),

          // Preset 1: Cloudflare Tunnel
          _buildPresetTile(
            icon: Icons.cloud_done_rounded,
            title: 'Live Cloudflare Tunnel',
            subtitle: liveTunnelUrl,
            isActive: ApiService.baseUrl == liveTunnelUrl,
            onTap: () {
              _urlController.text = liveTunnelUrl;
              _applyUrl(liveTunnelUrl);
            },
          ),
          const SizedBox(height: 8),

          // Preset 2: Local Wi-Fi
          _buildPresetTile(
            icon: Icons.wifi_rounded,
            title: 'Local Wi-Fi Network',
            subtitle: localWifiUrl,
            isActive: ApiService.baseUrl == localWifiUrl,
            onTap: () {
              _urlController.text = localWifiUrl;
              _applyUrl(localWifiUrl);
            },
          ),
          const SizedBox(height: 8),

          // Preset 3: Reset Default
          _buildPresetTile(
            icon: Icons.restore_rounded,
            title: 'Reset to Built-in Default',
            subtitle: ApiService.defaultFallbackUrl,
            isActive: ApiService.baseUrl == ApiService.defaultFallbackUrl,
            onTap: () async {
              await ApiService.resetToDefaultUrl();
              _urlController.text = ApiService.baseUrl;
              if (mounted) {
                ErrorHandler.showSuccess('Reset to default URL');
                _testCurrentConnection();
              }
            },
          ),

          const SizedBox(height: 28),
          const Text(
            'CUSTOM SERVER URL',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'https://your-tunnel.trycloudflare.com/api',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.network_check_rounded, size: 18),
                  label: const Text('Test URL'),
                  onPressed: _isTesting ? null : () => _testCurrentConnection(_urlController.text),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _applyUrl(_urlController.text),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Whenever your computer restarts or the Cloudflare tunnel changes, simply paste the new tunnel URL here. No APK re-installation required!',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? AppColors.primary.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : Colors.white10,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isActive)
              const Icon(Icons.radio_button_checked, color: AppColors.primary, size: 20)
            else
              const Icon(Icons.radio_button_off, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}
