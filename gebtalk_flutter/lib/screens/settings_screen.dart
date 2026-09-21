import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/api_service.dart';
import '../theme/colors.dart';
import 'profile_screen.dart';
import 'settings/account_settings_screen.dart';
import 'settings/privacy_settings_screen.dart';
import 'settings/chat_settings_screen.dart';
import 'settings/notification_settings_screen.dart';
import 'settings/storage_settings_screen.dart';
import 'chat_backup_screen.dart';
import 'linked_devices_screen.dart';
import 'payment_screen.dart';
import 'starred_messages_screen.dart';
import 'debug_push_screen.dart';
import 'settings/server_settings_screen.dart';

/// Full WhatsApp Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final profile = appState.currentProfile;

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
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white70),
            onPressed: () => _showSearchSettingsDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // User Profile Card Header
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primary,
                    backgroundImage: profile?.avatar != null && profile!.avatar.isNotEmpty
                        ? NetworkImage(ApiService.resolveUrl(profile.avatar))
                        : null,
                    child: (profile?.avatar == null || profile!.avatar.isEmpty)
                        ? Text(
                            profile?.name.isNotEmpty == true ? profile!.name[0].toUpperCase() : 'U',
                            style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.name ?? 'GebTalk User',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile?.about ?? 'Available on GebTalk',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile?.phone ?? appState.phoneNumber,
                          style: TextStyle(color: AppColors.primary.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_rounded, color: AppColors.primary, size: 28),
                    onPressed: () => _showQRCodeDialog(context, profile?.name ?? 'GebTalk User', profile?.phone ?? appState.phoneNumber),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Core Settings Menu Tiles
          _buildSettingsTile(
            context,
            icon: Icons.key_rounded,
            title: 'Account',
            subtitle: 'Security notifications, 2-step verification, delete account',
            destination: const AccountSettingsScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.lock_rounded,
            title: 'Privacy',
            subtitle: 'Block contacts, disappearing messages, app lock',
            destination: const PrivacySettingsScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.chat_rounded,
            title: 'Chats',
            subtitle: 'Theme, wallpapers, chat backup, chat history',
            destination: const ChatSettingsScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Message, group & call tones, vibration, priority',
            destination: const NotificationSettingsScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.pie_chart_rounded,
            title: 'Storage and Data',
            subtitle: 'Network usage, auto-download, storage cleaner',
            destination: const StorageSettingsScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.star_rounded,
            title: 'Starred Messages',
            subtitle: 'Messages you bookmarked across chats',
            destination: const StarredMessagesScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.devices_rounded,
            title: 'Linked Devices',
            subtitle: 'Web, desktop and companion sessions',
            destination: const LinkedDevicesScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.payment_rounded,
            title: 'Payments',
            subtitle: 'GebTalk Pay wallet and transaction logs',
            destination: const PaymentScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.cloud_sync_rounded,
            title: 'Chat Backup',
            subtitle: 'Backup chat history and media to cloud/local',
            destination: const ChatBackupScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.notifications_active_rounded,
            title: 'Push & Calling Diagnostics',
            subtitle: 'Register device, test background push wake-up & VAPID',
            destination: const DebugPushScreen(),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.dns_rounded,
            title: 'Server Connection',
            subtitle: 'Change live tunnel URL or switch to local Wi-Fi backend',
            destination: const ServerSettingsScreen(),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Divider(color: Colors.white10),
          ),

          _buildSettingsTile(
            context,
            icon: Icons.language_rounded,
            title: 'App Language',
            subtitle: "English (device's language)",
            onTap: () => _showLanguageDialog(context),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.help_outline_rounded,
            title: 'Help',
            subtitle: 'Help center, contact support desk, terms & privacy',
            onTap: () => _showHelpDialog(context),
          ),
          _buildSettingsTile(
            context,
            icon: Icons.group_add_rounded,
            title: 'Invite a Friend',
            subtitle: 'Share GebTalk with friends and family worldwide',
            onTap: () => _showInviteDialog(context),
          ),

          const SizedBox(height: 30),

          // Footer
          Center(
            child: Column(
              children: [
                Text(
                  'from',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                ),
                const SizedBox(height: 2),
                const Text(
                  'EB GLOBAL TITAN',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  'GebTalk v3.0.0 (Global Edition)',
                  style: TextStyle(color: AppColors.primary.withValues(alpha: 0.6), fontSize: 10),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? destination,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
      onTap: () {
        if (destination != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
        } else if (onTap != null) {
          onTap();
        }
      },
    );
  }

  void _showQRCodeDialog(BuildContext context, String name, String phone) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('My QR Code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.qr_code_2_rounded, size: 180, color: Colors.black),
            ),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(phone, style: const TextStyle(color: AppColors.primary, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              'Your QR code is private. If you share it with someone, they can scan it with their GebTalk camera to add you as a contact.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('App Language', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              'English', 'Spanish', 'French', 'German', 'Hindi', 'Arabic', 'Portuguese', 'Russian', 'Japanese', 'Chinese'
            ].map((lang) {
              return ListTile(
                title: Text(lang, style: const TextStyle(color: Colors.white)),
                leading: Radio<String>(
                  value: lang,
                  groupValue: 'English',
                  activeColor: AppColors.primary,
                  onChanged: (v) => Navigator.pop(ctx),
                ),
                onTap: () => Navigator.pop(ctx),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('GebTalk Help & Support', style: TextStyle(color: Colors.white)),
        content: const Text(
          'GebTalk is the premier global secure communications application.\n\n• End-to-End Encryption\n• HD Voice & Video Calling\n• 4GB Lossless File Sharing\n• Built-in EBI AI Assistant\n• Real-time Instant Translation\n\nFor enterprise inquiries, contact: support@gebtalk.app',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }

  void _showInviteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Invite Friends to GebTalk', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Share your invitation link:\n\nhttps://gebtalk.app/join/global',
          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Copy Link', style: TextStyle(color: AppColors.primary))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  void _showSearchSettingsDialog(BuildContext context) {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Search Settings', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type setting name...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setDlgState(() {}),
                ),
                const SizedBox(height: 12),
                ...[
                  {'name': 'Security notifications', 'dest': const AccountSettingsScreen()},
                  {'name': 'Two-step verification', 'dest': const AccountSettingsScreen()},
                  {'name': 'Change number', 'dest': const AccountSettingsScreen()},
                  {'name': 'Delete account', 'dest': const AccountSettingsScreen()},
                  {'name': 'Last seen & online', 'dest': const PrivacySettingsScreen()},
                  {'name': 'Profile photo privacy', 'dest': const PrivacySettingsScreen()},
                  {'name': 'Read receipts', 'dest': const PrivacySettingsScreen()},
                  {'name': 'Blocked contacts', 'dest': const PrivacySettingsScreen()},
                  {'name': 'App Lock', 'dest': const PrivacySettingsScreen()},
                  {'name': 'Wallpaper', 'dest': const ChatSettingsScreen()},
                  {'name': 'Theme & Font size', 'dest': const ChatSettingsScreen()},
                  {'name': 'Message tones', 'dest': const NotificationSettingsScreen()},
                  {'name': 'Storage and Network Data', 'dest': const StorageSettingsScreen()},
                ].where((item) => (item['name'] as String).toLowerCase().contains(searchCtrl.text.toLowerCase())).take(5).map((item) {
                  return ListTile(
                    dense: true,
                    title: Text(item['name'] as String, style: const TextStyle(color: Colors.white70)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => item['dest'] as Widget));
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Colors.white54))),
          ],
        ),
      ),
    );
  }
}
