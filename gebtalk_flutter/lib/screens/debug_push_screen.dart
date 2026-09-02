import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/app_state.dart';
import '../services/api_service.dart';
import '../services/web_push_manager.dart';
import '../theme/colors.dart';

class DebugPushScreen extends StatefulWidget {
  const DebugPushScreen({super.key});

  @override
  State<DebugPushScreen> createState() => _DebugPushScreenState();
}

class _DebugPushScreenState extends State<DebugPushScreen> {
  bool _isLoading = false;
  String _permissionStatus = 'Checking...';
  bool _isSwActive = false;
  String? _existingSubscription;
  String _vapidPublicKey = '';
  List<dynamic> _registeredDevices = [];
  String _lastTestResult = '';
  final List<String> _diagnosticLogs = [];

  @override
  void initState() {
    super.initState();
    _refreshDiagnostics();
  }

  void _log(String msg) {
    setState(() {
      _diagnosticLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    });
  }

  Future<void> _refreshDiagnostics() async {
    setState(() => _isLoading = true);
    _log('Refreshing push diagnostics...');

    try {
      // 1. Check browser permissions & SW
      final perm = await WebPushManager.instance.getNotificationPermission();
      final swActive = await WebPushManager.instance.isServiceWorkerActive();
      final sub = await WebPushManager.instance.getExistingSubscription();

      setState(() {
        _permissionStatus = perm ?? 'unknown';
        _isSwActive = swActive;
        _existingSubscription = sub;
      });

      _log('Browser Permission: $_permissionStatus, SW Active: $_isSwActive');
      if (sub != null) {
        _log('Existing Push Subscription Found: ${sub.substring(0, sub.length > 50 ? 50 : sub.length)}...');
      } else {
        _log('No active Web Push Subscription in browser');
      }

      // 2. Fetch VAPID key from backend
      try {
        final vapidRes = await http.get(Uri.parse('${ApiService.baseUrl}/notifications/vapid-public-key'));
        if (vapidRes.statusCode == 200) {
          final data = jsonDecode(vapidRes.body);
          setState(() {
            _vapidPublicKey = data['publicKey'] ?? '';
          });
          _log('VAPID Public Key loaded from backend');
        }
      } catch (e) {
        _log('Failed to fetch VAPID key: $e');
      }

      // 3. Fetch registered devices from backend
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentProfile?.id ?? appState.phoneNumber;
      if (userId.isNotEmpty) {
        try {
          final devRes = await http.get(Uri.parse('${ApiService.baseUrl}/devices/list?user_id=${Uri.encodeComponent(userId)}'));
          if (devRes.statusCode == 200) {
            final data = jsonDecode(devRes.body);
            setState(() {
              _registeredDevices = data['devices'] ?? [];
            });
            _log('Registered devices in backend: ${_registeredDevices.length}');
          }
        } catch (e) {
          _log('Failed to fetch devices: $e');
        }
      }
    } catch (e) {
      _log('Diagnostic error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _registerAndSubscribe() async {
    setState(() => _isLoading = true);
    _log('Starting Web Push Subscription process...');

    try {
      if (_vapidPublicKey.isEmpty) {
        final vapidRes = await http.get(Uri.parse('${ApiService.baseUrl}/notifications/vapid-public-key'));
        if (vapidRes.statusCode == 200) {
          final data = jsonDecode(vapidRes.body);
          _vapidPublicKey = data['publicKey'] ?? '';
        }
      }

      if (_vapidPublicKey.isEmpty) {
        _log('ERROR: VAPID Public Key not available');
        return;
      }

      _log('Requesting browser subscription with VAPID key...');
      final subResult = await WebPushManager.instance.subscribeToWebPush(_vapidPublicKey);

      if (subResult.containsKey('error')) {
        _log('Subscription Error: ${subResult['error']}');
      } else {
        _log('Browser Subscription SUCCESS! Registering device with backend...');
        final appState = Provider.of<AppState>(context, listen: false);
        final userId = appState.currentProfile?.id ?? appState.phoneNumber;
        final deviceId = 'web_${userId}_${DateTime.now().millisecondsSinceEpoch}';

        final regRes = await http.post(
          Uri.parse('${ApiService.baseUrl}/devices/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'device_id': deviceId,
            'platform': 'WEB',
            'push_token': subResult,
            'device_name': 'Web PWA Client (${defaultTargetPlatform.name})'
          }),
        );

        if (regRes.statusCode == 200) {
          _log('DEVICE REGISTERED IN DATABASE! Device ID: $deviceId');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Device Registered for Web Push Notifications!'), backgroundColor: Colors.green),
          );
        } else {
          _log('Backend Device Register Error: ${regRes.statusCode} - ${regRes.body}');
        }
      }

      await _refreshDiagnostics();
    } catch (e) {
      _log('Register exception: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendTestPush() async {
    setState(() => _isLoading = true);
    _log('Triggering Test Push from backend...');

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentProfile?.id ?? appState.phoneNumber;

      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/notifications/test'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'message': 'GEBTALK TEST: Background push notification received successfully!'
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] ?? [];
        final msg = 'Dispatched to ${data['devices_found']} device(s). Results: ${jsonEncode(results)}';
        setState(() => _lastTestResult = msg);
        _log('Test Push Sent: $msg');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔔 Push Sent to ${data['devices_found']} device(s)! Check notification banner.'),
            backgroundColor: AppColors.primary,
          ),
        );
      } else {
        _log('Test push error: ${res.statusCode} - ${res.body}');
      }
    } catch (e) {
      _log('Test push exception: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final profile = appState.currentProfile;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Push & Background Calling Diagnostics', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: _refreshDiagnostics,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User & Platform Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_circle_rounded, color: AppColors.primary, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile?.name ?? 'GebTalk User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('ID: ${profile?.id ?? appState.phoneNumber}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.electricBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        kIsWeb ? 'WEB / PWA' : defaultTargetPlatform.name.toUpperCase(),
                        style: const TextStyle(color: AppColors.electricBlue, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildStatusRow('Notification Permission', _permissionStatus.toUpperCase(), _permissionStatus == 'granted' ? Colors.green : Colors.orange),
                const SizedBox(height: 8),
                _buildStatusRow('Service Worker Active', _isSwActive ? 'YES' : 'NO', _isSwActive ? Colors.green : Colors.red),
                const SizedBox(height: 8),
                _buildStatusRow('Push Subscription', _existingSubscription != null ? 'ACTIVE' : 'NOT SUBSCRIBED', _existingSubscription != null ? Colors.green : Colors.amber),
                const SizedBox(height: 8),
                _buildStatusRow('Backend Devices Registered', '${_registeredDevices.length} Device(s)', _registeredDevices.isNotEmpty ? Colors.green : Colors.red),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.deepSpaceBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.phonelink_ring_rounded),
                  label: const Text('REGISTER & SUBSCRIBE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: _isLoading ? null : _registerAndSubscribe,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('SEND TEST PUSH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: _isLoading ? null : _sendTestPush,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Registered Devices List
          const Text('REGISTERED DEVICES IN BACKEND', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          if (_registeredDevices.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
              child: const Text('No active devices registered. Click "REGISTER & SUBSCRIBE" above.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            ..._registeredDevices.map((dev) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Icon(dev['platform'] == 'ANDROID' ? Icons.android_rounded : (dev['platform'] == 'IOS' ? Icons.apple_rounded : Icons.language_rounded), color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dev['device_name'] ?? dev['device_id'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('ID: ${dev['device_id']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                ],
              ),
            )),

          const SizedBox(height: 24),

          // Diagnostics Log Box
          const Text('REAL-TIME DIAGNOSTIC LOGS', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            height: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.deepSpaceBlack,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: _diagnosticLogs.isEmpty
                ? const Center(child: Text('No diagnostic logs yet.', style: TextStyle(color: Colors.white24)))
                : ListView.builder(
                    itemCount: _diagnosticLogs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(_diagnosticLogs[index], style: const TextStyle(color: Color(0xFF4ADE80), fontFamily: 'monospace', fontSize: 11)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }
}
