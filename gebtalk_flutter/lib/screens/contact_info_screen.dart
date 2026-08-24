import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/webrtc_service.dart';
import '../theme/colors.dart';
import '../utils/error_handler.dart';
import '../widgets/email_call_modal.dart';

class ContactInfoScreen extends StatefulWidget {
  final Contact contact;
  const ContactInfoScreen({super.key, required this.contact});

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Message> _mediaItems = [];
  List<Message> _docItems = [];
  List<Message> _linkItems = [];
  bool _loading = true;
  int _disappearingTimer = 0;

  @override
  void initState() {
    super.initState();
    _disappearingTimer = widget.contact.disappearingTimer;
    _tabController = TabController(length: 3, vsync: this);
    _fetchMedia();
  }

  void _startAudioCall() {
    final appState = Provider.of<AppState>(context, listen: false);
    final isSelf = widget.contact.id == appState.currentProfile?.id ||
        ((widget.contact.email?.isNotEmpty ?? false) &&
            widget.contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase());
    if (isSelf) {
      ErrorHandler.showError('Voice calls cannot be placed to your own account.');
      return;
    }
    final webrtcService = Provider.of<WebRtcService>(context, listen: false);
    webrtcService.startCall(widget.contact.id, widget.contact.name, peerAvatar: widget.contact.avatar);
  }

  void _startVideoCall() {
    final appState = Provider.of<AppState>(context, listen: false);
    final isSelf = widget.contact.id == appState.currentProfile?.id ||
        ((widget.contact.email?.isNotEmpty ?? false) &&
            widget.contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase());
    if (isSelf) {
      ErrorHandler.showError('Video calls cannot be placed to your own account.');
      return;
    }
    final webrtcService = Provider.of<WebRtcService>(context, listen: false);
    webrtcService.startCall(widget.contact.id, widget.contact.name, peerAvatar: widget.contact.avatar);
  }

  void _showDisappearingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Disappearing Messages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'For more privacy and storage, new messages will disappear from this chat for everyone after the selected duration.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...[
              {'label': '24 Hours', 'seconds': 86400},
              {'label': '7 Days', 'seconds': 604800},
              {'label': '90 Days', 'seconds': 7776000},
              {'label': 'Off', 'seconds': 0},
            ].map((item) {
              final seconds = item['seconds'] as int;
              final isSelected = _disappearingTimer == seconds;
              return ListTile(
                title: Text(item['label'] as String, style: const TextStyle(color: Colors.white)),
                trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => _disappearingTimer = seconds);
                  await ApiService.setDisappearingTimer(widget.contact.id, seconds);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Disappearing messages timer set to ${item['label']}')),
                    );
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showWallpaperDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Chat Wallpaper', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...['Default (Dark Galaxy)', 'Nebula Purple', 'Deep Ocean', 'Emerald Matrix', 'Obsidian AMOLED'].map((wp) {
              return ListTile(
                leading: const Icon(Icons.wallpaper_rounded, color: AppColors.primary),
                title: Text(wp, style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ApiService.setChatWallpaper(widget.contact.id, wp);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Wallpaper updated to $wp')),
                    );
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Report ${widget.contact.name}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If you report this contact, the last 5 messages from this contact will be forwarded to GebTalk Trust & Safety for review.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...['Spam', 'Harassment or Bullying', 'Inappropriate Content', 'Fake Account', 'Other'].map((reason) {
              return ListTile(
                dense: true,
                title: Text(reason, style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ApiService.reportContact(widget.contact.id, reportType: 'abuse', reason: reason);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Report submitted for reason: $reason. Thank you for keeping GebTalk safe.')),
                    );
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchMedia() async {
    final mediaData = await ApiService.getChatMedia(widget.contact.id, filter: 'images');
    final docData = await ApiService.getChatMedia(widget.contact.id, filter: 'docs');
    final linkData = await ApiService.getChatMedia(widget.contact.id, filter: 'links');
    if (mounted) {
      setState(() {
        _mediaItems = mediaData.map((e) => Message.fromJson(e)).toList();
        _docItems = docData.map((e) => Message.fromJson(e)).toList();
        _linkItems = linkData.map((e) => Message.fromJson(e)).toList();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final contact = widget.contact;
    final isMuted = appState.isMuted(contact.id);
    final isBlocked = appState.isBlocked(contact.id);
    final isPinned = appState.isPinnedChat(contact.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Hero Header
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.surface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (!contact.isGroup)
                IconButton(
                  icon: const Icon(Icons.call_rounded, color: Colors.white),
                  onPressed: _startAudioCall,
                  tooltip: 'Audio Call',
                ),
              IconButton(
                icon: const Icon(Icons.videocam_rounded, color: Colors.white),
                onPressed: _startVideoCall,
                tooltip: 'Video Call',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                color: AppColors.surface,
                onSelected: (value) => _handleMenuAction(value, appState),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'share', child: Text('Share Contact', style: TextStyle(color: Colors.white70))),
                  PopupMenuItem(value: 'export', child: Text('Export Chat', style: TextStyle(color: Colors.white70))),
                  PopupMenuItem(value: 'clear', child: Text('Clear Chat', style: TextStyle(color: Colors.redAccent))),
                  if (!contact.isGroup)
                    PopupMenuItem(
                      value: 'block',
                      child: Text(isBlocked ? 'Unblock' : 'Block', style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.3),
                      AppColors.background,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    // Avatar
                    Hero(
                      tag: 'avatar_${contact.id}',
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: contact.avatar.isNotEmpty
                              ? Image.network(
                                  ApiService.resolveUrl(contact.avatar),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildInitialsAvatar(contact),
                                )
                              : _buildInitialsAvatar(contact),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Name
                    Text(
                      contact.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Phone/Role
                    Text(
                      contact.phone.isNotEmpty ? contact.phone : contact.role,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Quick Actions Bar
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildQuickAction(Icons.chat_rounded, 'Message', () => Navigator.pop(context)),
                  _buildQuickAction(
                    Icons.video_camera_front_rounded,
                    'Email Meet',
                    () => EmailCallModal.show(
                      context,
                      initialEmail: contact.email,
                      initialName: contact.name,
                      contactId: contact.id,
                    ),
                  ),
                  _buildQuickAction(
                    Icons.call_rounded,
                    'Audio',
                    _startAudioCall,
                  ),
                  _buildQuickAction(
                    Icons.videocam_rounded,
                    'Video',
                    _startVideoCall,
                  ),
                ],
              ),
            ),
          ),

          // About Section
          if (!contact.isGroup)
            SliverToBoxAdapter(
              child: _buildSection(
                title: 'About',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    contact.role.isNotEmpty ? contact.role : 'Hey there! I am using GebTalk',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15),
                  ),
                ),
              ),
            ),

          // Encryption Lock Info
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Messages are end-to-end encrypted. No one outside of this chat can read or listen to them.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Media, Docs, Links Tabs
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.primary,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: Colors.white54,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [
                      Tab(text: 'Media (${_mediaItems.length})'),
                      Tab(text: 'Docs (${_docItems.length})'),
                      Tab(text: 'Links (${_linkItems.length})'),
                    ],
                  ),
                  SizedBox(
                    height: _loading ? 100 : (_getActiveTabItems().isEmpty ? 80 : 120),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildMediaGrid(),
                              _buildDocsList(),
                              _buildLinksList(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Chat Settings
          SliverToBoxAdapter(
            child: _buildSection(
              title: 'Chat Settings',
              child: Column(
                children: [
                  _buildSettingTile(
                    icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    title: isMuted ? 'Unmute Notifications' : 'Mute Notifications',
                    subtitle: isMuted ? 'Currently muted' : 'Receive notifications',
                    iconColor: isMuted ? Colors.orange : Colors.white54,
                    onTap: () => _showMuteOptions(appState),
                  ),
                  _buildSettingTile(
                    icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    title: isPinned ? 'Unpin Chat' : 'Pin Chat',
                    subtitle: isPinned ? 'Currently pinned' : 'Pin to top of chat list',
                    iconColor: isPinned ? AppColors.primary : Colors.white54,
                    onTap: () async {
                      await appState.togglePinChat(contact.id);
                      if (mounted) setState(() {});
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.timer_outlined,
                    title: 'Disappearing Messages',
                    subtitle: _disappearingTimer > 0
                        ? '${(_disappearingTimer / 3600).round()} hours'
                        : 'Off',
                    iconColor: Colors.white54,
                    onTap: _showDisappearingDialog,
                  ),
                  _buildSettingTile(
                    icon: Icons.wallpaper_rounded,
                    title: 'Wallpaper',
                    subtitle: 'Change chat wallpaper',
                    iconColor: Colors.white54,
                    onTap: _showWallpaperDialog,
                  ),
                ],
              ),
            ),
          ),

          // Group Members (if group)
          if (contact.isGroup)
            SliverToBoxAdapter(
              child: _buildSection(
                title: 'Group Members',
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchGroupMembers(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final members = snapshot.data!;
                    return Column(
                      children: members.map((m) {
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                            child: Text(
                              (m['name'] ?? 'U')[0].toUpperCase(),
                              style: TextStyle(color: AppColors.primary),
                            ),
                          ),
                          title: Text(
                            m['name'] ?? m['contact_id'] ?? 'Unknown',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: Text(
                            m['role'] ?? 'member',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                          ),
                          trailing: m['role'] == 'admin'
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Admin', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                                )
                              : null,
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),

          // Danger Zone
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  if (!contact.isGroup)
                    _buildSettingTile(
                      icon: Icons.block_rounded,
                      title: isBlocked ? 'Unblock ${contact.name}' : 'Block ${contact.name}',
                      subtitle: isBlocked ? 'This contact is blocked' : 'Block this contact',
                      iconColor: Colors.redAccent,
                      titleColor: Colors.redAccent,
                      onTap: () => _confirmBlock(appState),
                    ),
                  _buildSettingTile(
                    icon: Icons.thumb_down_rounded,
                    title: 'Report ${contact.name}',
                    subtitle: 'Report spam or abuse',
                    iconColor: Colors.redAccent,
                    titleColor: Colors.redAccent,
                    onTap: _showReportDialog,
                  ),
                  _buildSettingTile(
                    icon: Icons.delete_rounded,
                    title: 'Clear Chat',
                    subtitle: 'Delete all messages in this chat',
                    iconColor: Colors.orangeAccent,
                    titleColor: Colors.orangeAccent,
                    onTap: () => _confirmClearChat(appState),
                  ),
                  if (!contact.isGroup)
                    _buildSettingTile(
                      icon: Icons.delete_forever_rounded,
                      title: 'Delete Contact',
                      subtitle: 'Remove ${contact.name} and all data',
                      iconColor: Colors.redAccent,
                      titleColor: Colors.redAccent,
                      onTap: () => _confirmDeleteContact(appState),
                    ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(Contact contact) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.3),
      child: Center(
        child: Text(
          contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          child,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(title, style: TextStyle(color: titleColor ?? Colors.white, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
      onTap: onTap,
      dense: true,
    );
  }

  List<Message> _getActiveTabItems() {
    switch (_tabController.index) {
      case 0: return _mediaItems;
      case 1: return _docItems;
      case 2: return _linkItems;
      default: return [];
    }
  }

  Widget _buildMediaGrid() {
    if (_mediaItems.isEmpty) {
      return Center(
        child: Text('No media shared yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
      );
    }
    return GridView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _mediaItems.length,
      itemBuilder: (context, index) {
        final msg = _mediaItems[index];
        final url = msg.text.isNotEmpty && msg.text.startsWith('http') ? msg.text : '';
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppColors.primary.withValues(alpha: 0.1),
          ),
          child: url.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(ApiService.resolveUrl(url), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(Icons.image_rounded, color: Colors.white24)),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_rounded, color: Colors.white24, size: 30),
                      const SizedBox(height: 4),
                      Text(msg.fileName ?? 'Media', style: TextStyle(color: Colors.white38, fontSize: 10), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildDocsList() {
    if (_docItems.isEmpty) {
      return Center(
        child: Text('No documents shared yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _docItems.length,
      itemBuilder: (context, index) {
        final doc = _docItems[index];
        return ListTile(
          dense: true,
          leading: Icon(Icons.description_rounded, color: AppColors.primary, size: 20),
          title: Text(doc.fileName ?? 'Document', style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
          subtitle: Text(doc.fileSize ?? '', style: TextStyle(color: Colors.white38, fontSize: 11)),
          trailing: Text(doc.time, style: TextStyle(color: Colors.white24, fontSize: 10)),
        );
      },
    );
  }

  Widget _buildLinksList() {
    if (_linkItems.isEmpty) {
      return Center(
        child: Text('No links shared yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _linkItems.length,
      itemBuilder: (context, index) {
        final link = _linkItems[index];
        return ListTile(
          dense: true,
          leading: Icon(Icons.link_rounded, color: Colors.blueAccent, size: 20),
          title: Text(link.text, style: const TextStyle(color: Colors.blueAccent, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
          subtitle: Text(link.time, style: TextStyle(color: Colors.white38, fontSize: 11)),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchGroupMembers() async {
    try {
      final response = await ApiService.getGroupMembers(widget.contact.id);
      return response;
    } catch (e) {
      return [];
    }
  }

  void _handleMenuAction(String action, AppState appState) async {
    switch (action) {
      case 'export':
        final text = await appState.exportChatText(widget.contact.id);
        if (text != null && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('Chat Export', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: SingleChildScrollView(
                  child: SelectableText(text, style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: TextStyle(color: AppColors.primary))),
              ],
            ),
          );
        }
        break;
      case 'clear':
        _confirmClearChat(appState);
        break;
      case 'block':
        _confirmBlock(appState);
        break;
    }
  }

  void _showMuteOptions(AppState appState) {
    final isMuted = appState.isMuted(widget.contact.id);
    if (isMuted) {
      appState.toggleMuteChat(widget.contact.id);
      setState(() {});
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mute Notifications', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildMuteOption('8 hours', appState, duration: const Duration(hours: 8)),
            _buildMuteOption('1 week', appState, duration: const Duration(days: 7)),
            _buildMuteOption('Always', appState),
          ],
        ),
      ),
    );
  }

  Widget _buildMuteOption(String label, AppState appState, {Duration? duration}) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        String? mutedUntil;
        if (duration != null) {
          mutedUntil = DateTime.now().add(duration).toIso8601String();
        }
        appState.toggleMuteChat(widget.contact.id, mutedUntil: mutedUntil);
        Navigator.pop(context);
        setState(() {});
      },
    );
  }

  void _confirmClearChat(AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear Chat?', style: TextStyle(color: Colors.white)),
        content: Text(
          'All messages in this chat will be permanently deleted. This cannot be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await appState.clearChatHistory(widget.contact.id);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmBlock(AppState appState) {
    final isBlocked = appState.isBlocked(widget.contact.id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(isBlocked ? 'Unblock ${widget.contact.name}?' : 'Block ${widget.contact.name}?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isBlocked
              ? 'You will be able to send and receive messages from this contact again.'
              : 'Blocked contacts will no longer be able to send you messages or see your status updates.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await appState.toggleBlockContact(widget.contact.id);
              if (mounted) setState(() {});
            },
            child: Text(isBlocked ? 'Unblock' : 'Block', style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteContact(AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Delete ${widget.contact.name}?', style: const TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${widget.contact.name} from your contacts? All messages and history will be permanently deleted.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await appState.deleteContact(widget.contact.id);
              if (mounted) {
                if (success) {
                  // Pop contact info and chat detail back to list
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Contact "${widget.contact.name}" deleted successfully'),
                      backgroundColor: Colors.redAccent.shade700,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete "${widget.contact.name}"'),
                      backgroundColor: Colors.orange.shade800,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
