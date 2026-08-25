import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_models.dart';
import '../models/email_models.dart';
import '../providers/app_state.dart';
import '../services/api_service.dart';
import '../services/webrtc_service.dart';
import '../theme/colors.dart';
import '../utils/error_handler.dart';
import '../widgets/email_calling_overlay.dart';
import '../widgets/create_account_modal.dart';
import '../widgets/ceo_manage_credentials_modal.dart';
import 'chat_detail_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DirectoryUser> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.ensureInitialDataLoaded();
      appState.fetchContactRequests();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final results = await ApiService.searchUsers(q);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _showAddContactModal() {
    final emailController = TextEditingController();
    final messageController = TextEditingController(text: 'Hi, I would like to connect with you on GEBTALK.');
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF60A5FA), size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Send Connection Request',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter their permanent email address to send a secure connection request.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: emailController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'user@gmail.com or @username',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.email_outlined, color: Colors.white54, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Introduction note...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final em = emailController.text.trim();
                              if (em.isEmpty) return;
                              setModalState(() => isSubmitting = true);
                              final appState = Provider.of<AppState>(context, listen: false);
                              final success = await appState.sendContactRequest(
                                targetEmail: em,
                                message: messageController.text.trim(),
                              );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(success ? 'Connection request sent to $em' : 'Failed to send request'),
                                    backgroundColor: success ? const Color(0xFF10B981) : Colors.redAccent,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : const Text('Send Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final contacts = appState.contacts.where((c) => !c.isGroup).toList();
    final requests = appState.contactRequests;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Contacts',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: Color(0xFF8B5CF6)),
            tooltip: 'Add Contact',
            onPressed: _showAddContactModal,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchQuery,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search people by email or @username...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchQuery('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),

          // Content Area
          Expanded(
            child: _searchController.text.trim().isNotEmpty
                ? _buildSearchResults(appState)
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      // Pending Requests Section
                      if (requests.isNotEmpty) ...[
                        _buildPendingRequestsCard(requests, appState),
                        const SizedBox(height: 16),
                      ],

                      // Connected Contacts Header
                      Row(
                        children: [
                          const Text(
                            'Connected Contacts',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${contacts.length} people',
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Contacts List
                      if (contacts.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: const Column(
                            children: [
                              Icon(Icons.person_search_rounded, color: Colors.white24, size: 48),
                              SizedBox(height: 12),
                              Text('No contacts yet', style: TextStyle(color: Colors.white60, fontSize: 15)),
                              SizedBox(height: 4),
                              Text('Search an email to connect with people', style: TextStyle(color: Colors.white38, fontSize: 12)),
                            ],
                          ),
                        )
                      else
                        ...contacts.map((c) => _buildContactCard(c, appState)),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: (appState.canCreateAccounts && !appState.isCustomerRole && !appState.isStaffRole)
          ? FloatingActionButton.extended(
              onPressed: () => CreateAccountModal.show(context),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 6,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              label: Text(
                appState.isCeo ? 'Provision User' : 'Add Team Member',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            )
          : null,
    );
  }

  void _showReassignDialog(BuildContext context, Contact customer, AppState appState) {
    final staff = appState.staffMembers;
    String? selectedStaffId = customer.assignedStaffId;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF334155))),
              title: Text(
                'Reassign ${customer.name}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select a staff specialist to route this customer to:',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.4)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedStaffId ?? '',
                        dropdownColor: const Color(0xFF1E293B),
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF60A5FA)),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        items: [
                          const DropdownMenuItem<String>(value: '', child: Text('Unassigned / Pool')),
                          ...staff.map((s) => DropdownMenuItem<String>(value: s.id, child: Text('${s.name} (${s.role})'))),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            selectedStaffId = val;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final staffId = (selectedStaffId != null && selectedStaffId!.isNotEmpty) ? selectedStaffId : null;
                    await appState.reassignCustomer(contactId: customer.id, newStaffId: staffId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Customer ${customer.name} reassigned successfully'),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    }
                  },
                  child: const Text('Confirm Reassignment', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPendingRequestsCard(List<ContactRequest> requests, AppState appState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C3AED).withValues(alpha: 0.2),
            const Color(0xFF1E293B).withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_unread_rounded, color: Color(0xFFA78BFA), size: 18),
              const SizedBox(width: 8),
              Text(
                'Incoming Requests (${requests.length})',
                style: const TextStyle(
                  color: Color(0xFFDDD6FE),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...requests.map((r) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        child: Text(
                          r.senderName.isNotEmpty ? r.senderName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.senderName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              r.senderEmail,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (r.message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '“${r.message}”',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => appState.respondContactRequest(r.id, 'accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => appState.respondContactRequest(r.id, 'decline'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Decline', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildContactCard(Contact contact, AppState appState) {
    final email = contact.email ?? '${contact.id}@gebtalk.com';
    final isCustomer = contact.folder == 'customers' || contact.role.toLowerCase().contains('customer') || contact.role.toLowerCase().contains('client');
    final isStaff = contact.folder == 'staff';

    String? assignedStaffName;
    if (isCustomer && contact.assignedStaffId != null) {
      final staffMatch = appState.contacts.firstWhere(
        (c) => c.id == contact.assignedStaffId,
        orElse: () => Contact(id: '', name: contact.assignedStaffId!, phone: '', role: '', avatar: '', status: '', folder: '', unreadCount: 0, tags: []),
      );
      assignedStaffName = staffMatch.name;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            appState.selectContact(contact.id);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => const ChatDetailScreen(),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
          // Avatar with presence
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isCustomer
                    ? const Color(0xFF10B981).withOpacity(0.2)
                    : (isStaff ? const Color(0xFF3B82F6).withOpacity(0.2) : const Color(0xFF334155)),
                backgroundImage: (contact.avatar != null && contact.avatar!.startsWith('http'))
                    ? NetworkImage(contact.avatar!)
                    : null,
                child: (contact.avatar == null || !contact.avatar!.startsWith('http'))
                    ? Text(
                        contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: isCustomer ? const Color(0xFF34D399) : (isStaff ? const Color(0xFF60A5FA) : Colors.white),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: contact.status.toLowerCase().contains('online') || contact.status.toLowerCase().contains('active')
                        ? const Color(0xFF10B981)
                        : const Color(0xFF64748B),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0B1120), width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Name, Email, and Assigned Staff Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCustomer) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                        ),
                        child: const Text('Customer', style: TextStyle(color: Color(0xFF34D399), fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),
                    ] else if (isStaff) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                        ),
                        child: const Text('Staff', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 11),
                ),
                if (isCustomer && assignedStaffName != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.support_agent_rounded, color: Color(0xFF34D399), size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Assigned: $assignedStaffName',
                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Actions
          if (appState.isCeo)
            IconButton(
              icon: const Icon(Icons.vpn_key_rounded, color: Color(0xFFFBBF24), size: 19),
              tooltip: 'Manage Credentials (CEO)',
              onPressed: () => CeoManageCredentialsModal.show(context, contact: contact),
            ),
          if (appState.canAssignCustomers && isCustomer)
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded, color: Color(0xFFA78BFA), size: 20),
              tooltip: 'Reassign Specialist',
              onPressed: () => _showReassignDialog(context, contact, appState),
            ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF60A5FA), size: 19),
            tooltip: 'Message',
            onPressed: () {
              final appState = Provider.of<AppState>(context, listen: false);
              appState.selectContact(contact.id);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => const ChatDetailScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.call_outlined,
              color: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? Colors.white24 : const Color(0xFF10B981),
              size: 19,
            ),
            tooltip: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? 'Calling disabled for self' : 'Internet Voice Call',
            onPressed: () {
              final isSelf = contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase());
              if (isSelf) {
                ErrorHandler.showError('Voice calls cannot be placed to your own account.');
                return;
              }
              final webrtcService = Provider.of<WebRtcService>(context, listen: false);
              webrtcService.startCall(contact.id, contact.name, peerAvatar: contact.avatar);
            },
          ),
          IconButton(
            icon: Icon(
              Icons.videocam_outlined,
              color: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? Colors.white24 : const Color(0xFF8B5CF6),
              size: 19,
            ),
            tooltip: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? 'Calling disabled for self' : 'Video Call',
            onPressed: () {
              final isSelf = contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase());
              if (isSelf) {
                ErrorHandler.showError('Video calls cannot be placed to your own account.');
                return;
              }
              final webrtcService = Provider.of<WebRtcService>(context, listen: false);
              webrtcService.startCall(contact.id, contact.name, peerAvatar: contact.avatar);
            },
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(AppState appState) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white30, size: 48),
            const SizedBox(height: 12),
            const Text('No users found', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 6),
            Text('No match for "${_searchController.text}"', style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final user = _searchResults[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      user.email,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF60A5FA), size: 20),
                tooltip: 'Message',
                onPressed: () {
                  appState.selectContact(user.id.isNotEmpty ? user.id : user.email);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const ChatDetailScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.call_outlined, color: Color(0xFF10B981), size: 20),
                tooltip: 'Voice Call',
                onPressed: () {
                  final webrtcService = Provider.of<WebRtcService>(context, listen: false);
                  webrtcService.startCall(user.id.isNotEmpty ? user.id : user.email, user.name, calleeEmail: user.email);
                },
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final success = await appState.sendContactRequest(targetEmail: user.email);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Connection request sent to ${user.email}' : 'Request sent'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.person_add_rounded, size: 14),
                label: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
