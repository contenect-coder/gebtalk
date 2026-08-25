import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/email_models.dart';
import '../models/chat_models.dart';
import '../providers/app_state.dart';
import '../services/api_service.dart';
import '../theme/colors.dart';
import '../widgets/email_calling_overlay.dart';
import '../widgets/email_compose_modal.dart';
import 'chat_detail_screen.dart';

class EmailDetailScreen extends StatefulWidget {
  final String emailId;

  const EmailDetailScreen({super.key, required this.emailId});

  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  Map<String, dynamic>? _emailData;
  bool _isLoading = true;
  bool _isConverting = false;

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getEmailDetail(widget.emailId);
    if (mounted) {
      setState(() {
        _emailData = data;
        _isLoading = false;
      });
      // Refresh inbox counter in app state
      final appState = Provider.of<AppState>(context, listen: false);
      appState.fetchEmails(silent: true);
    }
  }

  Future<void> _handleConvertToChat() async {
    setState(() => _isConverting = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final res = await appState.convertEmailToChat(widget.emailId);
    setState(() => _isConverting = false);

    if (mounted && res != null && res['success'] == true) {
      final contactMap = res['contact'] != null ? Map<String, dynamic>.from(res['contact'] as Map) : null;
      if (contactMap != null) {
        final contact = Contact.fromJson(contactMap);
        appState.selectContact(contact.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => const ChatDetailScreen(),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to convert email to in-app chat')),
      );
    }
  }

  void _handleStartCall(String callType) {
    if (_emailData == null) return;
    final senderEmail = _emailData!['from_address'] ?? '';
    final senderName = _emailData!['from_name'] ?? senderEmail;
    final subject = _emailData!['subject'] ?? 'GEBTALK Call';
    final meetingId = 'meet_${DateTime.now().millisecondsSinceEpoch % 100000}';

    EmailCallingOverlay.show(
      context,
      meetingId: meetingId,
      recipientEmail: senderEmail,
      recipientName: senderName,
      subject: subject,
      callType: callType,
      joinUrl: 'http://localhost:8080/#/meet?id=$meetingId',
      pin: '123456',
    );
  }

  void _handleReplyEmail() {
    if (_emailData == null) return;
    final senderEmail = _emailData!['from_address'] ?? '';
    final subject = _emailData!['subject'] ?? '';
    final replySubject = subject.startsWith('Re:') ? subject : 'Re: $subject';
    final bodySnippet = _emailData!['body_text'] ?? '';
    final replyBody = '\n\n--- On ${_emailData!['received_at']}, $senderEmail wrote: ---\n$bodySnippet';

    EmailComposeModal.show(
      context,
      initialTo: senderEmail,
      initialSubject: replySubject,
      initialBody: replyBody,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1120),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
        ),
      );
    }

    if (_emailData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1120),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: Text('Email not found', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final fromName = _emailData!['from_name'] ?? _emailData!['from_address'] ?? 'Unknown';
    final fromEmail = _emailData!['from_address'] ?? '';
    final subject = _emailData!['subject'] ?? '(No Subject)';
    final bodyText = _emailData!['body_text'] ?? '';
    final receivedAt = _emailData!['received_at'] ?? '';
    final isStarred = _emailData!['is_starred'] == true;
    final attachments = (_emailData!['attachments'] as List?) ?? [];
    final canChatInApp = _emailData!['can_chat_in_app'] == true || fromEmail.contains('@');

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isStarred ? const Color(0xFFF59E0B) : Colors.white60,
            ),
            onPressed: () async {
              final appState = Provider.of<AppState>(context, listen: false);
              await appState.toggleEmailStar(widget.emailId);
              setState(() => _emailData!['is_starred'] = !isStarred);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white60),
            onPressed: () async {
              final appState = Provider.of<AppState>(context, listen: false);
              await appState.deleteEmail(widget.emailId);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.reply_rounded, color: Color(0xFF60A5FA)),
            onPressed: _handleReplyEmail,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject Title
            Text(
              subject,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),

            // Sender Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                    child: Text(
                      fromName.isNotEmpty ? fromName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Color(0xFF60A5FA),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              fromName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              receivedAt,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fromEmail,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ========== ACTION HUB (EMAIL ⇄ CHAT / CALL BRIDGE) ==========
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1E3A8A).withValues(alpha: 0.4),
                    const Color(0xFF1E293B).withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.bolt_rounded, color: Color(0xFF60A5FA), size: 18),
                      SizedBox(width: 6),
                      Text(
                        'GEBTALK Unified Actions',
                        style: TextStyle(
                          color: Color(0xFF93C5FD),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Start In-App Chat
                      ElevatedButton.icon(
                        onPressed: _isConverting ? null : _handleConvertToChat,
                        icon: _isConverting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.chat_bubble_rounded, size: 16),
                        label: const Text('Start In-App Chat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                      // Voice Call
                      OutlinedButton.icon(
                        onPressed: () => _handleStartCall('voice'),
                        icon: const Icon(Icons.call_rounded, size: 16, color: Color(0xFF10B981)),
                        label: const Text('Voice Call', style: TextStyle(fontSize: 13, color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                      // Video Call
                      OutlinedButton.icon(
                        onPressed: () => _handleStartCall('video'),
                        icon: const Icon(Icons.videocam_rounded, size: 16, color: Color(0xFF8B5CF6)),
                        label: const Text('Video Call', style: TextStyle(fontSize: 13, color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                      // Reply Email
                      OutlinedButton.icon(
                        onPressed: _handleReplyEmail,
                        icon: const Icon(Icons.reply_rounded, size: 16, color: Colors.white70),
                        label: const Text('Reply Email', style: TextStyle(fontSize: 13, color: Colors.white70)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Email Body
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Text(
                bodyText,
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Attachments Section
            if (attachments.isNotEmpty) ...[
              const Text(
                'Attachments',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              ...attachments.map((att) {
                final name = att['name'] ?? 'Attachment';
                final size = att['size'] ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF60A5FA), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                            if (size.isNotEmpty)
                              Text(size, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_rounded, color: Color(0xFF60A5FA), size: 20),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Downloading $name...')),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
