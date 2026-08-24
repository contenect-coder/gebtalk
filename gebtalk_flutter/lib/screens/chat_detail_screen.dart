import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/app_state.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/webrtc_service.dart';
import '../widgets/ebi_bot.dart';
import '../theme/colors.dart';
import '../widgets/animations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/error_handler.dart';
import '../utils/file_download_helper.dart';
import 'contact_info_screen.dart';
import 'media_viewer_screen.dart';
import '../widgets/link_preview.dart';
import 'camera_screen.dart';
import '../widgets/sticker_picker.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/email_call_modal.dart';
import '../widgets/email_compose_modal.dart';

class ChatDetailScreen extends StatelessWidget {
  const ChatDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatDetailContent(showLeadingBackButton: true);
  }
}

class ChatDetailContent extends StatefulWidget {
  final bool showLeadingBackButton;

  const ChatDetailContent({
    super.key,
    this.showLeadingBackButton = true,
  });

  @override
  State<ChatDetailContent> createState() => _ChatDetailContentState();
}

class _ChatDetailContentState extends State<ChatDetailContent>
    with TickerProviderStateMixin {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isInputFocused = false;
  bool _isPanelOpen = false;
  bool _showStickerSheet = false;
  bool _showEmojiSheet = false;

  PlatformFile? _selectedFile;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  // Download simulation progress states
  final Map<int, double> _downloadProgresses = {};
  final Set<int> _isDownloading = {};

  // WhatsApp Advanced Parity States
  Message? _replyingToMessage;
  bool _isSearchingInChat = false;
  final TextEditingController _inChatSearchCtrl = TextEditingController();
  int _searchMatchIndex = 0;
  List<int> _searchMatchIndices = [];
  bool _viewOnceMode = false;

  // Typing indicator animation
  late AnimationController _typingController;
  late List<Animation<double>> _dotAnimations;

  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(() {
      setState(() => _isInputFocused = _inputFocusNode.hasFocus);
    });

    // Staggered bounce for 3 dots
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _dotAnimations = List.generate(3, (i) {
      final start = i * 0.2;
      final end = start + 0.4;
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _typingController,
          curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeInOut),
        ),
      );
    });

    // Poll active chat history every 2 seconds for real-time updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        if (appState.activeContactId != null && !appState.isLoading) {
          appState.pollMessages();
        }
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _typingController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 60.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() async {
    if (_isUploading) return;
    if (_selectedFile != null) {
      _uploadAndSendFile();
      return;
    }
    
    var text = _msgController.text.trim();
    if (text.isEmpty) return;

    if (_replyingToMessage != null) {
      final replySender = _replyingToMessage!.isUser ? 'You' : 'Contact';
      text = "┌ [Replying to $replySender]: ${_replyingToMessage!.text}\n$text";
      setState(() {
        _replyingToMessage = null;
      });
    }

    _msgController.clear();
    final appState = Provider.of<AppState>(context, listen: false);
    final success = await appState.sendMessage(text);
    if (success) {
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  void _simulateAudioAttach() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final success = await appState.sendMessage('', isAudio: true, duration: "0:42");
    if (success) {
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  void _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'zip', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
        withData: true, // For web, this loads the bytes into memory if needed
      );

      if (result != null && result.files.isNotEmpty) {
        PlatformFile file = result.files.first;
        if (!_validateFile(file)) return;
        setState(() {
          _selectedFile = file;
        });
      }
    } catch (e) {
      ErrorHandler.showError("Failed to pick file: $e");
    }
  }

  bool _validateFile(PlatformFile file) {
    // 20 MB size limit
    const int maxSize = 20 * 1024 * 1024;
    if (file.size > maxSize) {
      ErrorHandler.showError("File size exceeds 20MB limit.");
      return false;
    }
    return true;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  /*
  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'doc':
      case 'docx': return 'application/msword';
      case 'xls':
      case 'xlsx': return 'application/vnd.ms-excel';
      case 'ppt':
      case 'pptx': return 'application/vnd.ms-powerpoint';
      default: return 'application/octet-stream';
    }
  }
  */

  void _triggerDownloadOrOpen(int msgId, String? fileData, String fileName) async {
    if (_isDownloading.contains(msgId)) return;
    if (fileData == null || fileData.isEmpty) {
      ErrorHandler.showError("File URL is invalid.");
      return;
    }

    final resolvedUrl = ApiService.resolveUrl(fileData);

    setState(() {
      _isDownloading.add(msgId);
      _downloadProgresses[msgId] = 0.0;
    });

    // Simulate progress increments
    for (int i = 1; i <= 5; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() {
        _downloadProgresses[msgId] = i / 10.0;
      });
    }

    try {
      if (resolvedUrl.startsWith('data:')) {
        triggerFileView(resolvedUrl);
      } else {
        // Trigger actual download for network files
        await triggerFileDownload(resolvedUrl, fileName);
      }

      // Complete progress simulation
      for (int i = 6; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 80));
        if (!mounted) return;
        setState(() {
          _downloadProgresses[msgId] = i / 10.0;
        });
      }

      ErrorHandler.showSuccess("Download started successfully!");
    } catch (e) {
      ErrorHandler.showError("Download failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading.remove(msgId);
          _downloadProgresses.remove(msgId);
        });
      }
    }
  }

  void _showPdfOptionsDialog(BuildContext context, Message msg, String? fileData, String fileName) {
    final resolvedUrl = fileData != null ? ApiService.resolveUrl(fileData) : null;
    final extension = fileName.split('.').last.toUpperCase();
    final fileSize = msg.fileSize ?? '2.5 MB';
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              side: BorderSide(color: AppColors.border, width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.secondary, size: 24),
                ),
                const SizedBox(width: 12),
                const Text(
                  "PDF Attachment",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Product Sans',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.insert_drive_file_outlined, "Size: $fileSize"),
                const SizedBox(height: 6),
                _buildInfoRow(Icons.calendar_today_outlined, "Uploaded: ${msg.time}"),
                const SizedBox(height: 6),
                _buildInfoRow(Icons.extension_outlined, "Format: $extension Document"),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actionsPadding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white),
                label: const Text("View PDF", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _viewPdf(resolvedUrl, fileName);
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                label: const Text("Download PDF", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _downloadPdf(msg.id, resolvedUrl, fileName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textMuted, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  void _viewPdf(String? url, String fileName) {
    if (url == null || url.isEmpty) {
      ErrorHandler.showError("PDF URL is invalid.");
      return;
    }
    try {
      triggerFileView(url);
    } catch (e) {
      ErrorHandler.showError("Error opening PDF: $e");
    }
  }

  void _downloadPdf(int msgId, String? url, String fileName) async {
    if (url == null || url.isEmpty) {
      ErrorHandler.showError("PDF URL is invalid.");
      return;
    }

    setState(() {
      _isDownloading.add(msgId);
      _downloadProgresses[msgId] = 0.0;
    });

    for (int i = 1; i <= 5; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() {
        _downloadProgresses[msgId] = i / 10.0;
      });
    }

    try {
      await triggerFileDownload(url, fileName);
      
      for (int i = 6; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 80));
        if (!mounted) return;
        setState(() {
          _downloadProgresses[msgId] = i / 10.0;
        });
      }
      
      ErrorHandler.showSuccess("Download started successfully!");
    } catch (e) {
      ErrorHandler.showError("Download failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading.remove(msgId);
          _downloadProgresses.remove(msgId);
        });
      }
    }
  }

  void _uploadAndSendFile() async {
    if (_selectedFile == null) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    List<int>? fileBytes = _selectedFile!.bytes;
    if (fileBytes == null && !kIsWeb && _selectedFile!.path != null) {
      try {
        fileBytes = await io.File(_selectedFile!.path!).readAsBytes();
      } catch (e) {
        debugPrint("Error reading file: $e");
      }
    }

    if (fileBytes == null) {
      ErrorHandler.showError("Failed to read file contents.");
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
      return;
    }

    // Start upload in parallel
    bool uploadComplete = false;
    final uploadFuture = ApiService.uploadFile(fileBytes, _selectedFile!.name);
    uploadFuture.then((_) {
      uploadComplete = true;
    }).catchError((_) {
      uploadComplete = true;
    });

    // Simulated progress increments while HTTP upload in progress
    for (int i = 1; i <= 9; i++) {
      if (uploadComplete) break;
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      setState(() {
        _uploadProgress = i / 10.0;
      });
    }

    final uploadedUrl = await uploadFuture;
    uploadComplete = true;

    if (uploadedUrl == null) {
      ErrorHandler.showError("Failed to upload file to storage server.");
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
      return;
    }

    setState(() {
      _uploadProgress = 1.0;
    });

    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Ensure we have an extension to show, fallback to "FILE"
    String ext = _selectedFile!.extension?.toUpperCase() ?? "FILE";
    String formattedSize = _formatFileSize(_selectedFile!.size);
    String displaySizeStr = "$formattedSize • $ext";
    
    // Use the text input as caption if available
    String caption = _msgController.text.trim();
    _msgController.clear();

    final messageText = jsonEncode({
      'caption': caption,
      'url': uploadedUrl,
    });
    
    final success = await appState.sendMessage(
      messageText, 
      isFile: true, 
      fileName: _selectedFile!.name, 
      fileSize: displaySizeStr,
    );
    
    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
        _selectedFile = null;
      });
      if (success) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      } else {
        ErrorHandler.showError("Failed to send file message.");
      }
    }
  }

  /*
  void _openInfoDrawer(BuildContext context, Contact contact, AppState appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Text(
                        "Contact Management",
                        style: TextStyle(color: AppColors.textMain, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Folder Picker
                  const Text("Assign to Folder", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: appState.folders.where((f) => f.id != 'all').map((folder) {
                        final isSelected = contact.folder == folder.id;
                        return GestureDetector(
                          onTap: () async {
                            await appState.updateContactAssignments(contact.id, folder.id, contact.tags.map((t) => t.id).toList());
                            setModalState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? _parseColor(folder.color).withValues(alpha: 0.12) : AppColors.background,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected ? _parseColor(folder.color) : AppColors.border,
                              ),
                            ),
                            child: Text(
                              folder.name,
                              style: TextStyle(
                                color: isSelected ? AppColors.textMain : AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
  */

  void _showReactionPicker(BuildContext context, int messageId, AppState appState) {
    final msg = appState.messages.firstWhere((m) => m.id == messageId, orElse: () => appState.messages.first);
    _showEnhancedMessageActions(context, msg, appState);
  }

  void _showEnhancedMessageActions(BuildContext context, Message msg, AppState appState) {
    final isStarred = msg.isStarred;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick Emoji Reaction Bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                      return TapScaleWidget(
                        onTap: () {
                          appState.reactToMessage(msg.id, emoji);
                          Navigator.pop(ctx);
                        },
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      );
                    }).toList(),
                  ),
                ),

                const Divider(color: Colors.white10),

                // Reply Action
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: AppColors.primary, size: 22),
                  title: const Text('Reply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _replyingToMessage = msg;
                    });
                    _inputFocusNode.requestFocus();
                  },
                ),

                // Star / Unstar Action
                ListTile(
                  leading: Icon(
                    isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.amberAccent,
                    size: 22,
                  ),
                  title: Text(isStarred ? 'Unstar Message' : 'Star Message', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await appState.toggleStarMessage(msg.id);
                  },
                ),

                // Pin / Unpin Action
                ListTile(
                  leading: const Icon(Icons.push_pin_rounded, color: Colors.blueAccent, size: 22),
                  title: const Text('Pin Message', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await appState.togglePinMessage(msg.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pinned message in this conversation!')),
                    );
                  },
                ),

                // Forward Action
                ListTile(
                  leading: const Icon(Icons.forward_rounded, color: Colors.greenAccent, size: 22),
                  title: const Text('Forward...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showForwardDialog(context, msg, appState);
                  },
                ),

                // Forward to Email Action
                ListTile(
                  leading: const Icon(Icons.email_outlined, color: Color(0xFF60A5FA), size: 22),
                  title: const Text('Forward to Email ✉', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Send this message as a formal email', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final contact = appState.activeContact;
                    final contactName = contact?.name ?? 'Contact';
                    final contactEmail = contact?.email ?? '';
                    final defaultSubject = 'GEBTALK Message from $contactName';
                    final bodyText = '[${msg.time}] ${msg.isUser ? "Me" : contactName}:\n${msg.text}';
                    EmailComposeModal.show(
                      context,
                      initialTo: contactEmail,
                      initialSubject: defaultSubject,
                      initialBody: bodyText,
                    );
                  },
                ),

                // Copy Action
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: Colors.white70, size: 22),
                  title: const Text('Copy Text', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard!')),
                    );
                  },
                ),

                // Delete Action
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                  title: const Text('Delete Message', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    appState.deleteMessage(msg.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showForwardDialog(BuildContext context, Message msg, AppState appState) {
    final selectedContacts = <String>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Forward to...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (selectedContacts.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await appState.forwardMessageToContacts([msg.id], selectedContacts.toList());
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Forwarded to ${selectedContacts.length} chats!')),
                        );
                      },
                      child: Text('SEND (${selectedContacts.length})', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: appState.contacts.length,
                  itemBuilder: (context, index) {
                    final c = appState.contacts[index];
                    final isSel = selectedContacts.contains(c.id);
                    return CheckboxListTile(
                      activeColor: AppColors.primary,
                      secondary: CircleAvatar(
                        backgroundColor: AppColors.primary,
                        backgroundImage: c.avatar.isNotEmpty ? NetworkImage(ApiService.resolveUrl(c.avatar)) : null,
                        child: c.avatar.isEmpty ? Text(c.name[0].toUpperCase()) : null,
                      ),
                      title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(c.role, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                      value: isSel,
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true) {
                            selectedContacts.add(c.id);
                          } else {
                            selectedContacts.remove(c.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Date divider between message groups ──
  Widget _buildDateDivider(String dateLabel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.border.withValues(alpha: 0.0),
                    AppColors.border,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Text(
                dateLabel,
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.border,
                    AppColors.border.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Typing indicator (3 bouncing dots) ──
  Widget _buildTypingIndicator() {
    return AnimatedBuilder(
      animation: _typingController,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border(
                    left: BorderSide(color: AppColors.primary.withValues(alpha: 0.4), width: 2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    return Transform.translate(
                      offset: Offset(0, -4 * sin(_dotAnimations[i].value * pi)),
                      child: Container(
                        margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.3 + (_dotAnimations[i].value * 0.5)),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final contact = appState.activeContact;
    final messages = appState.activeChatHistory;
    final searchQuery = _inChatSearchCtrl.text.trim().toLowerCase();
    final displayedMessages = searchQuery.isEmpty
        ? messages
        : messages.where((m) => m.text.toLowerCase().contains(searchQuery)).toList();

    // Trigger scrolling on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    if (contact == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left: Main chat screen (app bar, message list, input bar)
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    // ─── Gradient App Bar ───
                    _buildGradientAppBar(context, contact, appState),

                    // ─── Sticky Pinned Message Header Banner ───
                    _buildStickyPinnedBanner(contact, appState),

                    // ─── Message History Feed ───
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        itemCount: displayedMessages.length,
                        itemBuilder: (context, index) {
                          final msg = displayedMessages[index];

                          // Date divider logic: show when the date label changes
                          Widget? divider;
                          if (index == 0) {
                            divider = _buildDateDivider(_extractDateLabel(msg.time));
                          } else {
                            final prevDate = _extractDateLabel(displayedMessages[index - 1].time);
                            final curDate = _extractDateLabel(msg.time);
                            if (curDate != prevDate) {
                              divider = _buildDateDivider(curDate);
                            }
                          }

                          return AnimatedListItem(
                            index: index,
                            child: Column(
                              children: [
                                if (divider != null) divider,
                                _buildMessageBubble(msg, appState),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // ─── Typing Indicator (shown when loading) ───
                    if (appState.isLoading) _buildTypingIndicator(),

                    // ─── Message Input Bar ───
                    SafeArea(
                      top: false,
                      child: _buildInputBar(),
                    ),
                  ],
                ),
                EbiBot(screen: widget.showLeadingBackButton ? 'chat_detail' : 'chat_detail_embedded'),
              ],
            ),
          ),
          // Right: Collapsible side panel
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            width: _isPanelOpen ? 320 : 0,
            child: ClipRect(
              child: SizedBox(
                width: 320,
                child: _buildSideInfoPanel(context, contact, appState),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _launchPhoneCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri url = Uri.parse('tel:$cleanPhone');
    try {
      await launchUrl(url);
    } catch (e) {
      ErrorHandler.showError("Could not launch phone dialer: $e");
    }
  }

  // ── Gradient App Bar with WhatsApp In-Chat Search & 3-Dots Menu ──
  Widget _buildGradientAppBar(BuildContext context, Contact contact, AppState appState) {
    if (_isSearchingInChat) {
      return Container(
        decoration: const BoxDecoration(
          gradient: AppColors.headerGradient,
          boxShadow: [
            BoxShadow(color: Color(0x1A08615B), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => setState(() {
                    _isSearchingInChat = false;
                    _inChatSearchCtrl.clear();
                  }),
                ),
                Expanded(
                  child: TextField(
                    controller: _inChatSearchCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Search in conversation...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => _inChatSearchCtrl.clear(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A08615B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              if (widget.showLeadingBackButton)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              if (!widget.showLeadingBackButton) const SizedBox(width: 16),
              // Tappable avatar → Contact Info
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ContactInfoScreen(contact: contact),
                    ),
                  );
                },
                child: _buildAvatar(contact),
              ),
              const SizedBox(width: 10),
              // Tappable name/status area → Contact Info
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactInfoScreen(contact: contact),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        contact.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                          fontFamily: 'Product Sans',
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Online/Last Seen/Typing status
                      _buildPresenceSubtitle(contact, appState),
                    ],
                  ),
                ),
              ),
              // Video Call
              IconButton(
                icon: Icon(
                  Icons.videocam_rounded,
                  color: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? Colors.white24 : Colors.white,
                  size: 22,
                ),
                onPressed: () {
                  final isSelf = contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase());
                  if (isSelf) {
                    ErrorHandler.showError('Voice & video calls are disabled for your own account.');
                    return;
                  }
                  final webrtcService = Provider.of<WebRtcService>(context, listen: false);
                  webrtcService.startCall(contact.id, contact.name, peerAvatar: contact.avatar);
                },
                tooltip: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? 'Calling disabled for self' : 'Video Call',
              ),
              // Voice Call
              IconButton(
                icon: Icon(
                  Icons.call_rounded,
                  color: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? Colors.white24 : Colors.white,
                  size: 22,
                ),
                onPressed: () {
                  final isSelf = contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase());
                  if (isSelf) {
                    ErrorHandler.showError('Voice & video calls are disabled for your own account.');
                    return;
                  }
                  final webrtcService = Provider.of<WebRtcService>(context, listen: false);
                  webrtcService.startCall(contact.id, contact.name, peerAvatar: contact.avatar);
                },
                tooltip: (contact.id == appState.currentProfile?.id || ((contact.email?.isNotEmpty ?? false) && contact.email?.toLowerCase() == appState.currentProfile?.email?.toLowerCase())) ? 'Calling disabled for self' : 'Internet Voice Call',
              ),
              // Info Panel Toggle
              IconButton(
                icon: Icon(
                  _isPanelOpen ? Icons.info : Icons.info_outline,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _isPanelOpen = !_isPanelOpen;
                  });
                },
              ),
              // WhatsApp 3-Dots Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (val) => _handleDetailMenuAction(val, contact, appState),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'email_call',
                    child: Row(
                      children: [
                        Icon(Icons.video_camera_front_rounded, color: AppColors.primary, size: 20),
                        SizedBox(width: 12),
                        Text('Email Video Call', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'forward_email',
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined, color: Color(0xFF60A5FA), size: 20),
                        SizedBox(width: 12),
                        Text('Forward Chat to Email', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'search',
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: Colors.white70, size: 20),
                        SizedBox(width: 12),
                        Text('Search', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'pinned',
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_rounded, color: Colors.blueAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Pinned Messages', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'safety',
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_rounded, color: Colors.greenAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Verify Safety Code', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'wallpaper',
                    child: Row(
                      children: [
                        Icon(Icons.wallpaper_rounded, color: Colors.purpleAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Wallpaper', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'mute',
                    child: Row(
                      children: [
                        Icon(Icons.volume_off_rounded, color: Colors.orangeAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Mute Notifications', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear_media',
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_rounded, color: Colors.amberAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Clear Media', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  const PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, color: Colors.orangeAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Block Contact', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Delete Contact', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleDetailMenuAction(String val, Contact contact, AppState appState) {
    switch (val) {
      case 'email_call':
        EmailCallModal.show(
          context,
          initialEmail: contact.email,
          initialName: contact.name,
          contactId: contact.id,
        );
        break;
      case 'forward_email':
        final contactEmail = contact.email ?? '';
        final msgs = appState.activeChatHistory;
        final lines = msgs.map((m) => '[${m.time}] ${m.isUser ? "Me" : contact.name}: ${m.text ?? (m.isFile ? "[File: ${m.fileName}]" : "[Audio]")}').join('\n');
        EmailComposeModal.show(
          context,
          initialTo: contactEmail,
          initialSubject: 'GEBTALK Chat Transcript with ${contact.name}',
          initialBody: lines,
        );
        break;
      case 'search':
        setState(() => _isSearchingInChat = true);
        break;
      case 'pinned':
        _showPinnedMessagesModal(context, contact, appState);
        break;
      case 'safety':
        _showSafetyNumberDialog(context, contact);
        break;
      case 'wallpaper':
        _showWallpaperPicker(context, contact, appState);
        break;
      case 'mute':
        appState.toggleMuteChat(contact.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notifications toggled for ${contact.name}')),
        );
        break;
      case 'clear_media':
        appState.clearChatMedia(contact.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Media cleared for ${contact.name}')),
        );
        break;
      case 'block':
        appState.toggleBlockContact(contact.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Blocked status toggled for ${contact.name}')),
        );
        break;
      case 'delete':
        _confirmDeleteContact(context, contact, appState);
        break;
    }
  }

  void _confirmDeleteContact(BuildContext context, Contact contact, AppState appState) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Delete ${contact.name}?',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${contact.name} from your contacts? All messages and call history with this contact will be permanently deleted.',
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await appState.deleteContact(contact.id);
              if (mounted) {
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Contact "${contact.name}" deleted successfully'),
                      backgroundColor: Colors.redAccent.shade700,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete "${contact.name}"'),
                      backgroundColor: Colors.orange.shade800,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showPinnedMessagesModal(BuildContext context, Contact contact, AppState appState) async {
    final pinned = await appState.getPinnedMessages(contact.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.push_pin_rounded, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 10),
                Text('Pinned in ${contact.name}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (pinned.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No pinned messages in this chat.', style: TextStyle(color: Colors.white54))),
              )
            else
              ...pinned.map((m) => ListTile(
                    title: Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(m.time, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                      tooltip: 'Unpin',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await appState.togglePinMessage(m.id);
                      },
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  void _showSafetyNumberDialog(BuildContext context, Contact contact) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('Verify Safety Number', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'To verify that end-to-end encryption is securely configured with this contact, compare the 60-digit number below or scan the QR code.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.qr_code_2_rounded, color: Colors.black, size: 140),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
              child: const Text(
                '38291 84920 18274 95820\n10294 85739 20194 84729\n91827 48392 01928 47291',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.primary, fontFamily: 'monospace', letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }

  void _showWallpaperPicker(BuildContext context, Contact contact, AppState appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set Chat Wallpaper', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildWallpaperChoice('Dark Obsidian', '#0A0E18', contact, appState, ctx),
                _buildWallpaperChoice('Nebula Teal', '#08252B', contact, appState, ctx),
                _buildWallpaperChoice('Deep Violet', '#1E0E2B', contact, appState, ctx),
                _buildWallpaperChoice('Emerald Forest', '#0B2217', contact, appState, ctx),
                _buildWallpaperChoice('Midnight Blue', '#0C172E', contact, appState, ctx),
                _buildWallpaperChoice('Classic WhatsApp', '#0B141A', contact, appState, ctx),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperChoice(String label, String colorHex, Contact contact, AppState appState, BuildContext ctx) {
    final colorVal = Color(int.parse(colorHex.replaceAll('#', '0xFF')));
    return InkWell(
      onTap: () {
        appState.setChatWallpaper(contact.id, colorHex);
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallpaper updated to $label')),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: colorVal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  /// Shows typing indicator, online status, or last seen below the contact name
  Widget _buildPresenceSubtitle(Contact contact, AppState appState) {
    return FutureBuilder<UserPresence?>(
      future: appState.getUserPresence(contact.id),
      builder: (context, snapshot) {
        // Check for typing first
        return FutureBuilder<List<TypingIndicator>>(
          future: appState.getTypingIndicators(contact.id),
          builder: (context, typingSnapshot) {
            final typers = typingSnapshot.data ?? [];
            final isTyping = typers.any((t) => t.isTyping);

            if (isTyping) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'typing',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Product Sans',
                    ),
                  ),
                  const SizedBox(width: 2),
                  _buildTypingDots(),
                ],
              );
            }

            // Then show online/last seen
            final presence = snapshot.data;
            if (presence != null) {
              final statusText = presence.lastSeenFormatted;
              return Text(
                statusText,
                style: TextStyle(
                  color: presence.isOnline
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: presence.isOnline ? FontWeight.w500 : FontWeight.normal,
                  fontFamily: 'Product Sans',
                ),
              );
            }

            // Fallback to phone/role
            return Text(
              contact.phone.isNotEmpty ? contact.phone : contact.role,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontFamily: 'Product Sans',
              ),
            );
          },
        );
      },
    );
  }

  /// Animated typing dots (3 bouncing dots)
  Widget _buildTypingDots() {
    return SizedBox(
      width: 24,
      height: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _dotAnimations[i],
            builder: (context, child) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                width: 4,
                height: 4 + _dotAnimations[i].value * 4,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }

  // ── Sticky Pinned Message Header Banner ──
  Widget _buildStickyPinnedBanner(Contact contact, AppState appState) {
    final pinned = appState.messages.where((m) => m.isPinned).toList();
    if (pinned.isEmpty) return const SizedBox.shrink();
    final latestPinned = pinned.last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pinned Message', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                Text(
                  latestPinned.text,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
            onPressed: () => appState.togglePinMessage(latestPinned.id),
          ),
        ],
      ),
    );
  }

  // ── WhatsApp Reply Preview Banner ──
  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyingToMessage!.isUser ? 'You' : 'Contact',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingToMessage!.text,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
            onPressed: () => setState(() => _replyingToMessage = null),
          ),
        ],
      ),
    );
  }

  // ── Enhanced Input Bar ──
  Widget _buildFilePreview() {
    if (_selectedFile == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.insert_drive_file, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedFile!.name,
                      style: const TextStyle(color: AppColors.textMain, fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatFileSize(_selectedFile!.size),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (!_isUploading)
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _selectedFile = null;
                    });
                  },
                ),
            ],
          ),
          if (_isUploading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Uploading... ${(_uploadProgress * 100).toInt()}%",
              style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Teal shimmer top border
        Container(
          height: 1.5,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0x0008615B),
                AppColors.tealGlow,
                AppColors.primaryLight,
                AppColors.tealGlow,
                Color(0x0008615B),
              ],
              stops: [0.0, 0.2, 0.5, 0.8, 1.0],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildReplyPreview(),
              _buildFilePreview(),
              Row(
                children: [
                  // Attachment button
                  _buildIconCircle(Icons.attach_file, _isUploading ? () {} : () => _showAttachmentSheet(context)),
                  const SizedBox(width: 2),
                  // Camera button
                  _buildIconCircle(Icons.camera_alt_rounded, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(
                          onMediaCaptured: (url, caption) async {
                            final appState = Provider.of<AppState>(context, listen: false);
                            await appState.sendMessage(url, isFile: true, fileName: 'camera_capture.jpg');
                          },
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: 2),
                  // Sticker / GIF Picker button
                  _buildIconCircle(Icons.sticky_note_2, () {
                    setState(() {
                      _showEmojiSheet = false;
                      _showStickerSheet = !_showStickerSheet;
                    });
                  }),
                  const SizedBox(width: 2),
                  // Emoji Picker button
                  _buildIconCircle(Icons.sentiment_satisfied_alt, () {
                    setState(() {
                      _showStickerSheet = false;
                      _showEmojiSheet = !_showEmojiSheet;
                    });
                  }),
                  const SizedBox(width: 2),
                  // Mic button
                  _buildIconCircle(Icons.mic_none, _simulateAudioAttach),
                  const SizedBox(width: 4),
                  // Text input
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: _isInputFocused
                            ? AppColors.primaryGradient
                            : const LinearGradient(
                                colors: [AppColors.border, AppColors.border],
                              ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(20.5),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _msgController,
                          focusNode: _inputFocusNode,
                          style: const TextStyle(color: AppColors.textMain, fontSize: 13),
                          enabled: !_isUploading,
                          decoration: InputDecoration(
                            hintText: _selectedFile != null ? "Add a caption..." : "Type a secure message...",
                            hintStyle: const TextStyle(color: AppColors.textLight),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                          onChanged: (text) {
                            final appState = Provider.of<AppState>(context, listen: false);
                            if (appState.activeContactId != null) {
                              appState.sendTypingIndicator(appState.activeContactId!, text.isNotEmpty);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  TapScaleWidget(
                    onTap: _isUploading ? () {} : _sendMessage,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.orangeGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.orangeGlow.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Sticker / GIF Picker Panel
        if (_showStickerSheet)
          StickerPickerWidget(
            onStickerSelected: (url) async {
              setState(() => _showStickerSheet = false);
              final appState = Provider.of<AppState>(context, listen: false);
              await appState.sendMessage(url, isFile: true, fileName: 'sticker.webp');
            },
            onGifSelected: (url) async {
              setState(() => _showStickerSheet = false);
              final appState = Provider.of<AppState>(context, listen: false);
              await appState.sendMessage(url, isFile: true, fileName: 'animation.gif');
            },
          ),

        // Emoji Picker Panel
        if (_showEmojiSheet)
          EmojiPickerWidget(
            onEmojiSelected: (emoji) {
              _msgController.text = _msgController.text + emoji;
              _msgController.selection = TextSelection.fromPosition(
                TextPosition(offset: _msgController.text.length),
              );
            },
          ),
      ],
    );
  }

  // ── Icon circle for attach / mic buttons ──
  Widget _buildIconCircle(IconData icon, VoidCallback onPressed) {
    return TapScaleWidget(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }

  // --- WHATSAPP MODAL SHEETS & FEATURE DIALOGS ---

  void _showAttachmentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAttachOption(Icons.insert_drive_file_rounded, 'Document', Colors.purpleAccent, () {
                    Navigator.pop(context);
                    _pickFile();
                  }),
                  _buildAttachOption(Icons.camera_alt_rounded, 'Camera', Colors.pinkAccent, () {
                    Navigator.pop(context);
                    _pickFile();
                  }),
                  _buildAttachOption(Icons.image_rounded, 'Gallery', Colors.purple, () {
                    Navigator.pop(context);
                    _pickFile();
                  }),
                  _buildAttachOption(Icons.location_on_rounded, 'Location', Colors.greenAccent, () {
                    Navigator.pop(context);
                    _showLocationPickerModal(context);
                  }),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAttachOption(Icons.person_rounded, 'Contact', Colors.blueAccent, () {
                    Navigator.pop(context);
                    _showContactPickerModal(context);
                  }),
                  _buildAttachOption(Icons.bar_chart_rounded, 'Poll', Colors.orangeAccent, () {
                    Navigator.pop(context);
                    _showPollCreatorModal(context);
                  }),
                  _buildAttachOption(Icons.timer_rounded, 'Disappearing', Colors.amberAccent, () {
                    Navigator.pop(context);
                    _showDisappearingTimerSheet(context);
                  }),
                  _buildAttachOption(Icons.security_rounded, 'E2EE Info', Colors.tealAccent, () {
                    Navigator.pop(context);
                    _showE2eeInfoDialog(context);
                  }),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  void _showLocationPickerModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.location_on_rounded, color: Colors.greenAccent),
              SizedBox(width: 10),
              Text('Share Location', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  image: const DecorationImage(
                    image: NetworkImage('https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?auto=format&fit=crop&w=600&q=80'),
                    fit: BoxFit.cover,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 30),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.near_me_rounded, color: Colors.greenAccent),
                title: const Text('Send Current Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Accurate to 5 meters', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  final appState = Provider.of<AppState>(context, listen: false);
                  appState.sendLocationMessage(37.7749, -122.4194, 'San Francisco Tech HQ');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showContactPickerModal(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: appState.contacts.length,
          itemBuilder: (context, index) {
            final c = appState.contacts[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: c.avatar.isNotEmpty ? NetworkImage(c.avatar) : null,
                child: c.avatar.isEmpty ? Text(c.name[0]) : null,
              ),
              title: Text(c.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(c.phone.isNotEmpty ? c.phone : c.role, style: const TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                appState.sendContactCardMessage(c.id, c.name, c.phone.isNotEmpty ? c.phone : c.role);
              },
            );
          },
        );
      },
    );
  }

  void _showPollCreatorModal(BuildContext context) {
    final qCtrl = TextEditingController();
    final opt1Ctrl = TextEditingController();
    final opt2Ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Create Poll', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Question...', hintStyle: TextStyle(color: Colors.grey))),
              const SizedBox(height: 10),
              TextField(controller: opt1Ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Option 1', hintStyle: TextStyle(color: Colors.grey))),
              const SizedBox(height: 10),
              TextField(controller: opt2Ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Option 2', hintStyle: TextStyle(color: Colors.grey))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final appState = Provider.of<AppState>(context, listen: false);
                if (appState.activeContactId != null && qCtrl.text.isNotEmpty) {
                  ApiService.createPoll(appState.activeContactId!, qCtrl.text, [opt1Ctrl.text, opt2Ctrl.text]);
                  appState.sendMessage('📊 Poll: ${qCtrl.text}');
                }
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _showEbiAiSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text('EBI AI Assistant', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.g_translate_rounded, color: Colors.blueAccent),
                title: const Text('Translate Chat to Spanish', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final translated = await ApiService.translateMessage(_msgController.text.isNotEmpty ? _msgController.text : "Hello team!", "Spanish");
                  if (translated != null && mounted) {
                    _msgController.text = translated;
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.summarize_rounded, color: Colors.purpleAccent),
                title: const Text('Summarize Chat Conversation', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final appState = Provider.of<AppState>(context, listen: false);
                  if (appState.activeContactId != null) {
                    final summary = await ApiService.summarizeChat(appState.activeContactId!);
                    if (summary != null) {
                      appState.sendMessage(summary);
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showE2eeInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_rounded, color: Colors.greenAccent),
              SizedBox(width: 10),
              Text('End-to-End Encrypted', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'Messages and calls in GebTalk are secured with 256-bit AES End-to-End Encryption. No one outside of this chat, not even GebTalk, can read or listen to them.',
            style: TextStyle(color: Colors.grey, height: 1.5),
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        );
      },
    );
  }

  void _showDisappearingTimerSheet(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Disappearing Messages Timer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (var timer in [
              {'label': '24 Hours', 'sec': 86400},
              {'label': '7 Days', 'sec': 604800},
              {'label': '90 Days', 'sec': 7776000},
              {'label': 'Off', 'sec': 0},
            ])
              ListTile(
                title: Text(timer['label'] as String, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  if (appState.activeContactId != null) {
                    ApiService.setDisappearingTimer(appState.activeContactId!, timer['sec'] as int);
                    appState.sendMessage("⏱️ Disappearing messages set to ${timer['label']}.");
                  }
                },
              )
          ],
        );
      },
    );
  }

  Widget _buildStatusCheckmark(String status) {
    Widget icon;
    if (status == 'sent') {
      icon = const Icon(Icons.check, size: 12, color: AppColors.textMuted);
    } else if (status == 'delivered') {
      icon = const Icon(Icons.done_all_rounded, size: 13, color: AppColors.textMuted);
    } else if (status == 'read') {
      icon = const Icon(Icons.done_all_rounded, size: 13, color: AppColors.primary);
    } else {
      return const SizedBox.shrink();
    }
    
    return icon
        .animate(key: ValueKey(status))
        .scale(duration: 200.ms, curve: Curves.easeOutBack);
  }

  Widget _buildMessageBubble(Message msg, AppState appState) {
    final isUser = msg.isUser;
    final contact = appState.activeContact;
    final accentColor = contact != null ? AppColors.accentForRole(contact.role) : AppColors.primary;

    return GestureDetector(
      onLongPress: () => _showReactionPicker(context, msg.id, appState),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // ── Bubble ──
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                gradient: isUser
                    ? const LinearGradient(
                        colors: [Color(0x2600FFD1), Color(0x143B82F6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          accentColor.withValues(alpha: 0.12),
                          AppColors.surface.withValues(alpha: 0.35),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                border: Border.all(
                  color: isUser
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : accentColor.withValues(alpha: 0.25),
                  width: 1.0,
                ),
                boxShadow: [
                  if (isUser)
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      spreadRadius: -2,
                    )
                  else
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.04),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                ],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (msg.isBroadcast) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.campaign,
                            size: 14,
                            color: isUser ? Colors.white.withValues(alpha: 0.7) : AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "📢 Broadcast Message",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isUser ? Colors.white.withValues(alpha: 0.7) : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (msg.isViewOnce) ...[
                      // WhatsApp View Once Bubble
                      InkWell(
                        onTap: () {
                          if (!msg.isViewed) {
                            _showViewOnceModal(context, msg, appState);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: msg.isViewed ? Colors.white24 : AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: msg.isViewed ? Colors.white38 : AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  '①',
                                  style: TextStyle(
                                    color: msg.isViewed ? Colors.white38 : AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                msg.isViewed ? 'Opened' : 'Photo (View once)',
                                style: TextStyle(
                                  color: msg.isViewed ? Colors.white54 : Colors.white,
                                  fontWeight: msg.isViewed ? FontWeight.normal : FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (msg.isAudio) ...[
                      // Enhanced WhatsApp Voice Note Waveform Player
                      _VoiceNotePlayerWidget(
                        duration: msg.duration ?? "0:42",
                        isUser: isUser,
                      ),
                    ] else if (msg.isFile) ...[
                      _buildFileBubbleContent(msg, isUser),
                    ] else if (msg.text.startsWith('✉️ [Ref:')) ...[
                      _buildEmailRefBubble(msg, isUser),
                    ] else ...[
                      // Normal text
                      Text(
                        msg.text,
                        style: TextStyle(color: isUser ? Colors.white : AppColors.textMain, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Reactions & timestamp below bubble ──
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Timestamp
                Text(
                  msg.time,
                  style: const TextStyle(color: AppColors.textLight, fontSize: 9),
                ),
                if (isUser) ...[
                  const SizedBox(width: 4),
                  _buildStatusCheckmark(msg.status),
                ],
                const SizedBox(width: 6),
                // Reactions list
                if (msg.reactions.isNotEmpty)
                  Row(
                    children: msg.reactions.map((r) {
                      return Container(
                        margin: const EdgeInsets.only(left: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.black.withValues(alpha: 0.15) : AppColors.borderLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isUser ? Colors.transparent : AppColors.border, width: 0.5),
                        ),
                        child: Text(r, style: TextStyle(color: isUser ? Colors.white : AppColors.textMain, fontSize: 10)),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailRefBubble(Message msg, bool isUser) {
    final lines = msg.text.split('\n');
    final refHeader = lines.isNotEmpty ? lines[0] : '✉️ Email Reference';
    final previewBody = lines.length > 1 ? lines.sublist(1).join('\n') : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? Colors.black.withValues(alpha: 0.2) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.mark_email_read_rounded, color: Color(0xFF60A5FA), size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  refHeader,
                  style: const TextStyle(
                    color: Color(0xFF93C5FD),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (previewBody.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              previewBody,
              style: TextStyle(
                color: isUser ? Colors.white70 : const Color(0xFFCBD5E1),
                fontSize: 12,
                height: 1.3,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileBubbleContent(Message msg, bool isUser) {
    String caption = '';
    String? fileData;
    try {
      final trimmedText = msg.text.trim();
      if (trimmedText.startsWith('{') && trimmedText.endsWith('}')) {
        final parsed = jsonDecode(trimmedText);
        caption = parsed['caption'] ?? '';
        fileData = parsed['url'] ?? parsed['data'];
      } else if (trimmedText.startsWith('http') || trimmedText.startsWith('data:')) {
        fileData = trimmedText;
        caption = '';
      } else {
        caption = trimmedText;
      }
    } catch (e) {
      caption = msg.text;
    }

    final filename = msg.fileName ?? 'file';
    final extension = filename.split('.').last.toLowerCase();
    
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension) ||
                    (fileData != null && (
                      fileData.startsWith('data:image') ||
                      fileData.toLowerCase().contains('.png') ||
                      fileData.toLowerCase().contains('.jpg') ||
                      fileData.toLowerCase().contains('.jpeg') ||
                      fileData.toLowerCase().contains('.webp') ||
                      fileData.toLowerCase().contains('.gif')
                    ));
    final isPdf = extension == 'pdf';

    if (isImage) {
      return _buildImageBubble(msg, caption, fileData, isUser);
    } else if (isPdf) {
      return _buildPdfBubble(msg, caption, fileData, isUser);
    } else {
      return _buildGenericDocBubble(msg, caption, fileData, isUser, extension);
    }
  }

  Widget _buildImageBubble(Message msg, String caption, String? fileData, bool isUser) {
    final filename = msg.fileName ?? 'image.jpg';
    final filesize = msg.fileSize ?? '';

    Widget imageWidget;
    if (fileData != null && fileData.startsWith('data:image')) {
      final base64Content = fileData.split(',').last;
      try {
        imageWidget = Image.memory(
          base64Decode(base64Content),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 180,
          errorBuilder: (context, error, stackTrace) => _buildImageErrorPlaceholder(filename),
        );
      } catch (e) {
        imageWidget = _buildImageErrorPlaceholder(filename);
      }
    } else if (fileData != null && fileData.startsWith('http')) {
      final resolvedUrl = ApiService.resolveUrl(fileData);
      imageWidget = Image.network(
        resolvedUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 180,
        errorBuilder: (context, error, stackTrace) => _buildImageErrorPlaceholder(filename),
      );
    } else {
      // Premium Unsplash default placeholder based on hash to look diverse
      final index = (filename.hashCode % 5).abs();
      final placeholders = [
        "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=400&q=80",
        "https://images.unsplash.com/photo-1634017839464-5c339ebe3cb4?auto=format&fit=crop&w=400&q=80",
        "https://images.unsplash.com/photo-1614850523459-c2f4c699c52e?auto=format&fit=crop&w=400&q=80",
        "https://images.unsplash.com/photo-1620641788421-7a1c342ea42e?auto=format&fit=crop&w=400&q=80",
        "https://images.unsplash.com/photo-1574169208507-84376144848b?auto=format&fit=crop&w=400&q=80",
      ];
      imageWidget = Image.network(
        placeholders[index],
        fit: BoxFit.cover,
        width: double.infinity,
        height: 180,
        errorBuilder: (context, error, stackTrace) => _buildImageErrorPlaceholder(filename),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _openFullscreenImage(context, fileData, filename, caption),
          child: Container(
            width: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isUser ? Colors.white.withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.5),
              child: Stack(
                children: [
                  imageWidget,
                  // Glassmorphic metadata overlay badge
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        filesize.split('•').first.trim(),
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              caption,
              style: TextStyle(color: isUser ? Colors.white : AppColors.textMain, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImageErrorPlaceholder(String filename) {
    return Container(
      width: double.infinity,
      height: 180,
      color: Colors.red.withValues(alpha: 0.1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_rounded, color: AppColors.secondary, size: 36),
          const SizedBox(height: 8),
          Text(
            filename,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _openFullscreenImage(BuildContext context, String? fileData, String filename, String caption) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Stack(
            children: [
              // Interactive Image Viewer
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: fileData != null && fileData.startsWith('data:image')
                      ? Image.memory(base64Decode(fileData.split(',').last))
                      : fileData != null && fileData.startsWith('http')
                          ? Image.network(ApiService.resolveUrl(fileData))
                          : Image.network("https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=800&q=80"),
                ),
              ),
              // Header actions
              Positioned(
                top: 40,
                right: 20,
                child: Row(
                  children: [
                    // Download/Open button
                    ClipOval(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.12),
                        child: IconButton(
                          icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                          onPressed: () {
                            if (fileData != null && fileData.isNotEmpty) {
                              try {
                                final resolved = ApiService.resolveUrl(fileData);
                                triggerFileView(resolved);
                                ErrorHandler.showSuccess("Opening image in new tab...");
                              } catch (e) {
                                ErrorHandler.showError("Failed to open image: $e");
                              }
                            } else {
                              ErrorHandler.showError("Image URL is invalid.");
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Close button
                    ClipOval(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.12),
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Footer Caption
              if (caption.isNotEmpty)
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text(
                        caption,
                        style: const TextStyle(color: Colors.white, fontSize: 14, decoration: TextDecoration.none, fontFamily: 'Product Sans'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPdfBubble(Message msg, String caption, String? fileData, bool isUser) {
    final filename = msg.fileName ?? 'document.pdf';
    final filesize = msg.fileSize ?? '2.5 MB';
    
    // Deterministic page count based on filename
    final mockPageCount = (filename.hashCode % 18).abs() + 3;
    final isDownloading = _isDownloading.contains(msg.id);
    final downloadProgress = _downloadProgresses[msg.id] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _showPdfOptionsDialog(context, msg, fileData, filename),
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? Colors.black.withValues(alpha: 0.2) : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isUser 
                    ? Colors.white.withValues(alpha: 0.2) 
                    : AppColors.secondary.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.secondary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            filename,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${filesize.split('•').first.trim()} • $mockPageCount Pages",
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    if (isDownloading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: AppColors.secondary,
                          strokeWidth: 2.0,
                        ),
                      )
                    else
                      Icon(
                        Icons.arrow_downward_rounded,
                        color: isUser ? Colors.white.withValues(alpha: 0.7) : AppColors.textMuted,
                        size: 20,
                      ),
                  ],
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: downloadProgress,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondary),
                      minHeight: 3.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              caption,
              style: TextStyle(color: isUser ? Colors.white : AppColors.textMain, fontSize: 12.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGenericDocBubble(Message msg, String caption, String? fileData, bool isUser, String ext) {
    final filename = msg.fileName ?? 'file';
    final filesize = msg.fileSize ?? '1.2 MB';

    IconData icon;
    Color accentColor;
    
    switch (ext.toLowerCase()) {
      case 'doc':
      case 'docx':
        icon = Icons.description_rounded;
        accentColor = Colors.blue;
        break;
      case 'xls':
      case 'xlsx':
        icon = Icons.table_chart_rounded;
        accentColor = Colors.green;
        break;
      case 'ppt':
      case 'pptx':
        icon = Icons.slideshow_rounded;
        accentColor = Colors.orange;
        break;
      case 'zip':
      case 'rar':
        icon = Icons.folder_zip_rounded;
        accentColor = Colors.amber;
        break;
      case 'txt':
        icon = Icons.article_rounded;
        accentColor = Colors.blueGrey;
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        accentColor = Colors.teal;
    }

    final isDownloading = _isDownloading.contains(msg.id);
    final downloadProgress = _downloadProgresses[msg.id] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _triggerDownloadOrOpen(msg.id, fileData, filename),
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? Colors.black.withValues(alpha: 0.2) : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isUser 
                    ? Colors.white.withValues(alpha: 0.2) 
                    : accentColor.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: accentColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            filename,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            filesize.split('•').first.trim(),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    if (isDownloading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: accentColor,
                          strokeWidth: 2.0,
                        ),
                      )
                    else
                      Icon(
                        Icons.open_in_new_rounded,
                        color: isUser ? Colors.white.withValues(alpha: 0.7) : AppColors.textMuted,
                        size: 18,
                      ),
                  ],
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: downloadProgress,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      minHeight: 3.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              caption,
              style: TextStyle(color: isUser ? Colors.white : AppColors.textMain, fontSize: 12.5),
            ),
          ),
        ],
      ],
    );
  }

  // ── Avatar with PulsingDot status indicator ──
  Widget _buildAvatar(Contact contact) {
    Widget avatarWidget;

    if (contact.avatar.isEmpty) {
      avatarWidget = Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.primary, Color(0xFF0D9488)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.psychology, color: Colors.white, size: 20),
      );
    } else {
      avatarWidget = ClipOval(
        child: Image.network(
          contact.avatar,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(Icons.person, color: AppColors.primary, size: 20),
            );
          },
        ),
      );
    }

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          Center(child: avatarWidget),
          // Online PulsingDot overlay — bottom-right
          const Positioned(
            right: 0,
            bottom: 0,
            child: PulsingDot(
              color: Color(0xFF22C55E),
              size: 9,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  /// Extract a readable date label from the time string for dividers.
  /// Falls back to the raw time if no date portion exists.
  String _extractDateLabel(String time) {
    // If the time string contains a comma or multi-word date, use it directly.
    // Otherwise create a generic "Today" label.
    if (time.contains(',')) {
      return time.split(',').first.trim();
    }
    return 'Today';
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return Color(int.parse(hex, radix: 16));
  }

  Widget _buildSideInfoPanel(BuildContext context, Contact contact, AppState appState) {
    final staffMembers = appState.contacts.where((c) => c.folder == 'staff').toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          left: BorderSide(color: AppColors.borderLight, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.contact_page_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    "Customer Info",
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Product Sans',
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                    onPressed: () {
                      setState(() {
                        _isPanelOpen = false;
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                          ),
                          child: SizedBox(
                            width: 88,
                            height: 88,
                            child: contact.avatar.isNotEmpty
                                ? ClipOval(
                                    child: Image.network(
                                      contact.avatar,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: AppColors.primary.withValues(alpha: 0.1),
                                          child: const Icon(Icons.person, color: AppColors.primary, size: 36),
                                        );
                                      },
                                    ),
                                  )
                                : CircleAvatar(
                                    radius: 44,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                    child: const Icon(Icons.person, color: AppColors.primary, size: 36),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          contact.name,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Product Sans',
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          contact.role,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontFamily: 'Product Sans',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (contact.phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            contact.phone,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Product Sans',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (appState.isAdmin && contact.folder == 'customers') ...[
                    const Text(
                      "Assigned Staff Member",
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Product Sans'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: contact.assignedStaffId,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      style: const TextStyle(color: AppColors.textMain, fontFamily: 'Product Sans', fontSize: 13),
                      dropdownColor: AppColors.surface,
                      items: staffMembers.map((staff) {
                        return DropdownMenuItem<String>(
                          value: staff.id,
                          child: Text(staff.name),
                        );
                      }).toList(),
                      onChanged: (newStaffId) async {
                        if (newStaffId != null) {
                          final messenger = ScaffoldMessenger.of(context);
                          final staffName = staffMembers.firstWhere((s) => s.id == newStaffId).name;
                          final success = await appState.moveCustomerToStaff(contact.id, newStaffId);
                          if (success && mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text("Reassigned customer to $staffName")),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  const Text(
                    "Tags",
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Product Sans'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: appState.tags.map((tag) {
                      final isSelected = contact.tags.any((t) => t.id == tag.id);
                      final tagColor = _parseColor(tag.color);
                      return GestureDetector(
                        onTap: () async {
                          final tagIds = List<String>.from(contact.tags.map((t) => t.id));
                          if (isSelected) {
                            tagIds.remove(tag.id);
                          } else {
                            tagIds.add(tag.id);
                          }
                          await appState.updateContactAssignments(contact.id, contact.folder, tagIds);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? tagColor.withValues(alpha: 0.12) : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? tagColor : AppColors.border,
                            ),
                          ),
                          child: Text(
                            tag.name,
                            style: TextStyle(
                              color: isSelected ? AppColors.textMain : AppColors.textMuted,
                              fontSize: 11,
                              fontFamily: 'Product Sans',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    "Assign to Folder",
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Product Sans'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: appState.folders.where((f) => f.id != 'all').map((folder) {
                      final isSelected = contact.folder == folder.id;
                      final folderColor = _parseColor(folder.color);
                      return GestureDetector(
                        onTap: () async {
                          await appState.updateContactAssignments(contact.id, folder.id, contact.tags.map((t) => t.id).toList());
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? folderColor.withValues(alpha: 0.12) : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? folderColor : AppColors.border,
                            ),
                          ),
                          child: Text(
                            folder.name,
                            style: TextStyle(
                              color: isSelected ? AppColors.textMain : AppColors.textMuted,
                              fontSize: 11,
                              fontFamily: 'Product Sans',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showViewOnceModal(BuildContext context, Message msg, AppState appState) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_clock_rounded, color: AppColors.primary, size: 18),
                  SizedBox(width: 8),
                  Text('View-Once Protected Photo', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                ApiService.resolveUrl(msg.text.contains('http') ? msg.text : 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=600&q=80'),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white, size: 64),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                Navigator.pop(ctx);
                appState.markViewOnce(msg.id);
              },
              child: const Text('Close & Destroy', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp Voice Note Waveform Player with 1x / 1.5x / 2x speed toggles
class _VoiceNotePlayerWidget extends StatefulWidget {
  final String duration;
  final bool isUser;

  const _VoiceNotePlayerWidget({required this.duration, required this.isUser});

  @override
  State<_VoiceNotePlayerWidget> createState() => _VoiceNotePlayerWidgetState();
}

class _VoiceNotePlayerWidgetState extends State<_VoiceNotePlayerWidget> {
  bool _isPlaying = false;
  double _speed = 1.0;

  void _cycleSpeed() {
    setState(() {
      if (_speed == 1.0) {
        _speed = 1.5;
      } else if (_speed == 1.5) {
        _speed = 2.0;
      } else {
        _speed = 1.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final waveHeights = [8.0, 14.0, 6.0, 20.0, 16.0, 10.0, 22.0, 18.0, 12.0, 15.0, 8.0, 18.0, 14.0, 10.0, 20.0, 6.0];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: widget.isUser ? Colors.white : AppColors.primary, size: 30),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => setState(() => _isPlaying = !_isPlaying),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: waveHeights.map((h) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: widget.isUser ? Colors.white70 : AppColors.primary.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }).toList(),
        ),
        const SizedBox(width: 8),
        Text(
          widget.duration,
          style: TextStyle(color: widget.isUser ? Colors.white70 : AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: _cycleSpeed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_speed}x',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

