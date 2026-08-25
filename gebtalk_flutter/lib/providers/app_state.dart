import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_models.dart';
import '../models/email_models.dart';
import '../services/api_service.dart';

class AppState extends ChangeNotifier {
  bool _authenticated = false;
  String _phoneNumber = '';
  Map<String, dynamic>? _userProfile;
  UserProfile? _currentProfile;
  List<BroadcastList> _broadcastLists = [];
  List<BroadcastHistoryItem> _broadcastHistory = [];

  List<Folder> _folders = [];
  List<Tag> _tags = [];
  List<Contact> _contacts = [];
  List<Message> _activeChatHistory = [];
  
  String? _activeContactId;
  String _activeFolderId = 'all';
  String? _selectedTagId;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _loadingStatus;
  bool _isBackgroundSyncing = false;
  String _backgroundSyncStatus = '';

  bool _isAdmin = false;
  String _currentStaffId = '';
  bool _forceStaffView = false;
  List<UserStatus> _userStatuses = [];
  List<CallLog> _callLogs = [];
  Timer? _contactsTimer;

  // Phase 1: Chat Preferences State
  ChatPreferences _chatPreferences = ChatPreferences();
  Map<String, UserPresence> _presenceCache = {};
  Map<String, List<TypingIndicator>> _typingCache = {};
  bool _showArchivedChats = false;

  // ========== EMAIL-FIRST STATE ==========
  List<EmailMessage> _emails = [];
  Map<String, int> _emailFolderCounts = {'inbox': 0, 'sent': 0, 'drafts': 0, 'starred': 0, 'trash': 0};
  int _unreadEmailCount = 0;
  String _currentEmailFolder = 'inbox';
  bool _isLoadingEmails = false;
  List<ContactRequest> _contactRequests = [];
  bool _isLoadingRequests = false;

  // Getters
  bool get authenticated => _authenticated;
  String get phoneNumber => _phoneNumber;
  Map<String, dynamic>? get userProfile => _userProfile;
  UserProfile? get currentProfile => _currentProfile;
  List<BroadcastList> get broadcastLists => _broadcastLists;
  List<BroadcastHistoryItem> get broadcastHistory => _broadcastHistory;

  List<Folder> get folders => _folders;
  List<Tag> get tags => _tags;
  List<Contact> get contacts => _contacts;
  List<Message> get activeChatHistory => _activeChatHistory;
  List<UserStatus> get userStatuses => _userStatuses;
  List<CallLog> get callLogs => _callLogs;
  
  String? get activeContactId => _activeContactId;
  String get activeFolderId => _activeFolderId;
  String? get selectedTagId => _selectedTagId;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get loadingStatus => _loadingStatus;
  bool get isBackgroundSyncing => _isBackgroundSyncing;
  String get backgroundSyncStatus => _backgroundSyncStatus;
  bool get isAdmin => _isAdmin && !_forceStaffView;
  bool get hasAdminPrivileges => _isAdmin;
  String get currentStaffId => _currentStaffId;
  ChatPreferences get chatPreferences => _chatPreferences;
  bool get showArchivedChats => _showArchivedChats;
  int get archivedCount => _chatPreferences.archived.length;

  // Email-First Getters
  List<EmailMessage> get emails => _emails;
  Map<String, int> get emailFolderCounts => _emailFolderCounts;
  int get unreadEmailCount => _unreadEmailCount;
  String get currentEmailFolder => _currentEmailFolder;
  bool get isLoadingEmails => _isLoadingEmails;
  List<ContactRequest> get contactRequests => _contactRequests;
  bool get isLoadingRequests => _isLoadingRequests;

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  void _applyRolePermissions() {
    if (_currentProfile == null) return;

    final normalizedUserPhone = _normalizePhone(_phoneNumber);

    Contact? staffMatch;
    for (final contact in _contacts) {
      if (contact.folder == 'staff' &&
          _normalizePhone(contact.phone) == normalizedUserPhone &&
          normalizedUserPhone.isNotEmpty) {
        staffMatch = contact;
        break;
      }
    }

    if (staffMatch != null) {
      _currentStaffId = staffMatch.id;
    } else {
      _currentStaffId = _currentProfile!.id;
    }

    // CEO/Executive has full administrative permissions
    if (isCeo) {
      _isAdmin = true;
    } else {
      _isAdmin = false;
    }
  }

  String get userRole {
    if (_currentProfile != null && _currentProfile!.role.isNotEmpty) {
      return _currentProfile!.role;
    }
    if (_userProfile != null && _userProfile!['role'] != null && _userProfile!['role'].toString().isNotEmpty) {
      return _userProfile!['role'].toString();
    }
    return '';
  }

  bool get isCustomerRole {
    final r = userRole.toLowerCase().trim();
    return r.contains('customer') || r.contains('client');
  }

  bool get isCeo {
    final r = userRole.toLowerCase().trim();
    if (r.isEmpty) return false;
    if (r.contains('customer') || r.contains('client') || r.contains('staff') || r.contains('specialist') || r.contains('manager') || r.contains('support')) {
      return false;
    }
    return r == 'ceo' || r == 'founder' || r == 'global ceo' || r == 'chief executive' || r == 'chief executive officer' || r.startsWith('ceo ') || r.endsWith(' ceo');
  }

  bool get isManager {
    if (isCustomerRole || isCeo) return false;
    final r = userRole.toLowerCase().trim();
    if (r.isEmpty) return false;
    return r.contains('manager') || r.contains('supervisor') || r.contains('admin');
  }

  bool get isStaffRole {
    if (isCustomerRole || isCeo || isManager) return false;
    final r = userRole.toLowerCase().trim();
    if (r.isEmpty) return false;
    return r.contains('staff') || r.contains('specialist') || r.contains('member') || r.contains('lead') || r.contains('architect') || r.contains('developer') || r.contains('engineer') || r.contains('support');
  }

  bool get canCreateAccounts => (isCeo || isManager) && !isCustomerRole && !isStaffRole;
  bool get canAssignCustomers => (isCeo || isManager) && !isCustomerRole && !isStaffRole;

  List<Contact> get staffMembers => _contacts.where((c) => 
    c.folder == 'staff' || 
    c.role.toLowerCase().contains('staff') || 
    c.role.toLowerCase().contains('specialist') || 
    c.role.toLowerCase().contains('lead') || 
    c.role.toLowerCase().contains('architect') || 
    c.role.toLowerCase().contains('developer')
  ).toList();

  List<Contact> get customerContacts => _contacts.where((c) => 
    c.folder == 'customers' || 
    c.role.toLowerCase().contains('customer') || 
    c.role.toLowerCase().contains('client')
  ).toList();

  Future<bool> createManagedAccount({
    required String name,
    required String email,
    required String role,
    String? password,
    String? phone,
    String? assignedStaffId,
    String? notes,
  }) async {
    setLoading(true, 'Creating $role account...');
    final res = await ApiService.createManagedAccount(
      name: name,
      email: email,
      role: role,
      password: password,
      phone: phone,
      assignedStaffId: assignedStaffId,
      notes: notes,
    );
    if (res != null && res['success'] == true) {
      fetchContacts();
      setLoading(false);
      return true;
    }
    setLoading(false);
    return false;
  }

  Future<bool> reassignCustomer({
    required String contactId,
    required String? newStaffId,
  }) async {
    final success = await ApiService.reassignCustomerContact(
      contactId: contactId,
      assignedStaffId: newStaffId,
    );
    if (success) {
      final index = _contacts.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        final old = _contacts[index];
        _contacts[index] = Contact(
          id: old.id,
          name: old.name,
          phone: old.phone,
          role: old.role,
          avatar: old.avatar,
          status: old.status,
          folder: old.folder,
          unreadCount: old.unreadCount,
          assignedStaffId: newStaffId,
          managerId: old.managerId,
          tags: old.tags,
          email: old.email,
          notes: old.notes,
          countryCode: old.countryCode,
          lastMessage: old.lastMessage,
          isGroup: old.isGroup,
          isChannel: old.isChannel,
          disappearingTimer: old.disappearingTimer,
          isLocked: old.isLocked,
          isArchived: old.isArchived,
          isMuted: old.isMuted,
          isPinned: old.isPinned,
          isBlocked: old.isBlocked,
          wallpaperUrl: old.wallpaperUrl,
        );
        notifyListeners();
      }
      fetchContacts();
      return true;
    }
    return false;
  }

  void setLoading(bool loading, [String? status]) {
    _isLoading = loading;
    _loadingStatus = status;
    notifyListeners();
  }

  // Filtered contacts based on active folder, tag, search query, and permissions
  List<Contact> get filteredContacts {
    return _contacts.where((contact) {
      // 1. Customer Role Filter: Only support contacts and assigned staff specialist
      if (isCustomerRole) {
        final customerContact = _contacts.firstWhere(
          (c) => c.folder == 'customers' && _normalizePhone(c.phone) == _normalizePhone(_phoneNumber),
          orElse: () => Contact(id: '', name: '', phone: '', role: '', avatar: '', status: '', folder: '', unreadCount: 0, tags: []),
        );
        final assignedStaffId = customerContact.assignedStaffId;
        
        if (contact.folder != 'support' && contact.id != 'ebi' && contact.id != assignedStaffId) {
          return false;
        }
      }

      // 2. Staff Role Filter: Only their own vault and assigned customers
      if (isStaffRole && !isCeo && !isManager) {
        if (contact.folder == 'staff' && contact.id != _currentStaffId) {
          return false;
        }
        if (contact.folder == 'customers' && contact.assignedStaffId != _currentStaffId) {
          return false;
        }
      }

      // 3. Manager Role Filter: Only see their team members and customers assigned to them
      if (isManager && !isCeo) {
        final teamStaffIds = _contacts
            .where((c) => c.folder == 'staff' && (c.managerId == _currentStaffId || c.id == _currentStaffId))
            .map((c) => c.id)
            .toList();
            
        if (contact.folder == 'staff') {
          if (!teamStaffIds.contains(contact.id)) return false;
        }
        if (contact.folder == 'customers') {
          if (!teamStaffIds.contains(contact.assignedStaffId) && contact.assignedStaffId != _currentStaffId) {
            return false;
          }
        }
      }

      // 4. Folder filter
      if (_activeFolderId != 'all') {
        if (contact.folder != _activeFolderId) return false;
      }
      
      // 5. Tag filter
      if (_selectedTagId != null) {
        bool hasTag = contact.tags.any((t) => t.id == _selectedTagId);
        if (!hasTag) return false;
      }
      
      // 6. Search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatches = contact.name.toLowerCase().contains(query);
        final roleMatches = contact.role.toLowerCase().contains(query);
        if (!nameMatches && !roleMatches) return false;
      }

      // 7. Hide archived chats (unless viewing archived)
      if (!_showArchivedChats && _chatPreferences.archived.contains(contact.id)) {
        return false;
      }

      // 8. Hide blocked contacts from chat list
      if (_chatPreferences.blocked.contains(contact.id)) {
        return false;
      }
      
      return true;
    }).toList()
    ..sort((a, b) {
      // Pinned chats first
      final aPin = _chatPreferences.pinned.contains(a.id) ? 0 : 1;
      final bPin = _chatPreferences.pinned.contains(b.id) ? 0 : 1;
      if (aPin != bPin) return aPin.compareTo(bPin);
      // Then by unread count
      if (a.unreadCount != b.unreadCount) return b.unreadCount.compareTo(a.unreadCount);
      return 0;
    });
  }

  void toggleAdminMode() {
    _forceStaffView = !_forceStaffView;
    notifyListeners();
  }

  Contact? get activeContact {
    if (_activeContactId == null) return null;
    final target = _activeContactId!.toLowerCase().trim();
    for (final contact in _contacts) {
      if (contact.id.toLowerCase() == target || (contact.email != null && contact.email!.toLowerCase() == target)) {
        return contact;
      }
    }
    // Dynamic fallback so ChatDetailScreen never gets stuck on infinite loading
    final displayName = _activeContactId!.contains('@')
        ? _activeContactId!.split('@')[0].replaceAll('.', ' ').split(' ').map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '').join(' ')
        : _activeContactId!;
    return Contact(
      id: _activeContactId!,
      name: displayName,
      phone: '',
      role: 'Contact',
      avatar: '',
      status: 'Available',
      folder: 'staff',
      unreadCount: 0,
      email: _activeContactId!.contains('@') ? _activeContactId : null,
      tags: [],
    );
  }

  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAuthenticated = prefs.getBool('auth_authenticated') ?? false;
      if (!isAuthenticated) return false;

      final savedPhone = prefs.getString('auth_phone');
      if (savedPhone == null || savedPhone.isEmpty) return false;

      _authenticated = true;
      _phoneNumber = savedPhone;
      ApiService.authenticatedPhone = savedPhone;

      final savedProfile = prefs.getString('auth_profile');
      final savedCurrentProfile = prefs.getString('auth_current_profile');

      if (savedProfile != null) {
        try {
          _userProfile = json.decode(savedProfile);
        } catch (_) {}
      }
      if (savedCurrentProfile != null) {
        try {
          _currentProfile = UserProfile.fromJson(json.decode(savedCurrentProfile));
        } catch (_) {}
      }

      _applyRolePermissions();
      notifyListeners();

      // Run background data sync asynchronously
      triggerBackgroundInitialization();
      return true;
    } catch (e) {
      debugPrint('Auto-login session restoration failed: $e');
    }
    return false;
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auth_authenticated', true);
      await prefs.setString('auth_phone', _phoneNumber);

      if (_userProfile != null) {
        final cleanProfile = Map<String, dynamic>.from(_userProfile!);
        final av = cleanProfile['avatar'] as String? ?? '';
        if (av.startsWith('data:image') || av.length > 500) {
          cleanProfile['avatar'] = '';
        }
        await prefs.setString('auth_profile', json.encode(cleanProfile));
      }

      if (_currentProfile != null) {
        final cleanCurrent = _currentProfile!.toJson();
        final av = cleanCurrent['avatar'] as String? ?? '';
        if (av.startsWith('data:image') || av.length > 500) {
          cleanCurrent['avatar'] = '';
        }
        await prefs.setString('auth_current_profile', json.encode(cleanCurrent));
      }
    } catch (e) {
      debugPrint('Warning: SharedPreferences quota or write issue: $e');
    }
  }

  // Setters & Actions
  void setPhoneNumber(String phone) {
    _phoneNumber = phone;
    notifyListeners();
  }

  Future<bool> verifyOtpCode(String otp, {String name = '', String countryCode = '', String countryName = '', String countryFlag = ''}) async {
    final stopwatch = Stopwatch()..start();
    setLoading(true, "Verifying...");

    final response = await ApiService.verifyOtp(
      _phoneNumber,
      otp,
      name: name,
      countryCode: countryCode,
      countryName: countryName,
      countryFlag: countryFlag,
    );
    stopwatch.stop();
    debugPrint('[Performance Logging] OTP verification duration: ${stopwatch.elapsedMilliseconds}ms');

    if (response != null) {
      final sessionStopwatch = Stopwatch()..start();
      _authenticated = true;
      _phoneNumber = response['token'] ?? _phoneNumber;
      ApiService.authenticatedPhone = _phoneNumber;
      _userProfile = response['user'];
      if (_userProfile != null) {
        _currentProfile = UserProfile.fromJson(_userProfile!);
      }
      _applyRolePermissions();
      sessionStopwatch.stop();
      debugPrint('[Performance Logging] Session creation duration: ${sessionStopwatch.elapsedMilliseconds}ms');

      // Persist session to SharedPreferences safely
      _persistSession();

      // Return immediately so the UI can navigate instantly to the main screen
      setLoading(false);
      
      // Kick off background synchronization
      triggerBackgroundInitialization();
      
      return true;
    }
    setLoading(false);
    return false;
  }

  Future<bool> loginWithEmail(String email, String password) async {
    final stopwatch = Stopwatch()..start();
    setLoading(true, "Authenticating...");

    final response = await ApiService.loginWithEmail(email, password);
    stopwatch.stop();
    debugPrint('[Performance Logging] Email login duration: ${stopwatch.elapsedMilliseconds}ms');

    if (response != null) {
      final sessionStopwatch = Stopwatch()..start();
      _authenticated = true;
      _phoneNumber = response['token'] ?? email;
      ApiService.authenticatedPhone = _phoneNumber;
      _userProfile = response['user'];
      if (_userProfile != null) {
        _currentProfile = UserProfile.fromJson(_userProfile!);
      }
      _applyRolePermissions();
      sessionStopwatch.stop();
      debugPrint('[Performance Logging] Session creation duration: ${sessionStopwatch.elapsedMilliseconds}ms');

      // Persist session to SharedPreferences safely
      _persistSession();

      setLoading(false);
      triggerBackgroundInitialization();
      return true;
    }
    setLoading(false);
    return false;
  }

  Future<bool> verifyEmailOtpCode(String email, String otp, {String name = ''}) async {
    final stopwatch = Stopwatch()..start();
    setLoading(true, "Verifying email code...");

    final response = await ApiService.verifyEmailOtp(email, otp, name: name);
    stopwatch.stop();
    debugPrint('[Performance Logging] Email OTP verification duration: ${stopwatch.elapsedMilliseconds}ms');

    if (response != null) {
      final sessionStopwatch = Stopwatch()..start();
      _authenticated = true;
      _phoneNumber = response['token'] ?? email;
      ApiService.authenticatedPhone = _phoneNumber;
      _userProfile = response['user'];
      if (_userProfile != null) {
        _currentProfile = UserProfile.fromJson(_userProfile!);
      }
      _applyRolePermissions();
      sessionStopwatch.stop();

      _persistSession();
      setLoading(false);
      triggerBackgroundInitialization();
      return true;
    }
    setLoading(false);
    return false;
  }

  void startContactsPolling() {
    _contactsTimer?.cancel();
    _contactsTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_authenticated) {
        refreshContacts();
      }
    });
  }

  void stopContactsPolling() {
    _contactsTimer?.cancel();
    _contactsTimer = null;
  }

  @override
  void dispose() {
    stopContactsPolling();
    super.dispose();
  }

  void logout() {
    _authenticated = false;
    _phoneNumber = '';
    _userProfile = null;
    _currentProfile = null;
    _forceStaffView = false;
    _isAdmin = true;
    _currentStaffId = '';
    ApiService.authenticatedPhone = null;
    stopContactsPolling();
    
    // Clear SharedPreferences asynchronously
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('auth_authenticated');
      prefs.remove('auth_phone');
      prefs.remove('auth_profile');
      prefs.remove('auth_current_profile');
    }).catchError((e) {
      debugPrint('Failed to clear auth session: $e');
    });
    
    notifyListeners();
  }

  void ensureInitialDataLoaded() {
    if (_contacts.isEmpty && !_isBackgroundSyncing) {
      triggerBackgroundInitialization();
    }
  }

  void triggerBackgroundInitialization() async {
    if (_isBackgroundSyncing) return;
    
    _isBackgroundSyncing = true;
    _backgroundSyncStatus = "Preparing Workspace...";
    notifyListeners();

    try {
      final totalStopwatch = Stopwatch()..start();
      
      _backgroundSyncStatus = "Syncing Workspace...";
      notifyListeners();
      
      final data = await ApiService.getInitData(_phoneNumber);
      if (data != null) {
        if (data['folders'] != null) {
          final List fList = data['folders'];
          _folders = fList.map((item) => Folder.fromJson(item)).toList();
        }
        if (data['tags'] != null) {
          final List tList = data['tags'];
          _tags = tList.map((item) => Tag.fromJson(item)).toList();
        }
        if (data['contacts'] != null) {
          final List cList = data['contacts'];
          _contacts = cList.map((item) => Contact.fromJson(item)).toList();
        }
        if (data['profile'] != null) {
          final profileMap = data['profile'];
          _currentProfile = UserProfile.fromJson(profileMap);
          _userProfile = {
            'name': _currentProfile!.name,
            'role': _currentProfile!.role,
            'avatar': _currentProfile!.avatar,
            'email': _currentProfile!.email,
            'phone': _currentProfile!.phone,
          };
          _persistSession();
        }
        if (data['statuses'] != null) {
          final List sList = data['statuses'];
          _userStatuses = sList.map((item) => UserStatus.fromJson(item)).toList();
        }
        if (data['call_logs'] != null) {
          final List clList = data['call_logs'];
          _callLogs = clList.map((item) => CallLog.fromJson(item)).toList();
        }
        notifyListeners(); // Force UI update immediately after contacts are ready
      }

      _applyRolePermissions();
      startContactsPolling();
      
      final bStopwatch = Stopwatch()..start();
      await Future.wait([
        fetchBroadcastLists(),
        fetchBroadcastHistory(),
        fetchChatPreferences(),
      ]);
      bStopwatch.stop();
      debugPrint('[Performance Logging] Broadcast loading duration: ${bStopwatch.elapsedMilliseconds}ms');

      totalStopwatch.stop();
      debugPrint('[Performance Logging] Total background initialization duration: ${totalStopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint("Background sync error: $e");
    } finally {
      _isBackgroundSyncing = false;
      _backgroundSyncStatus = '';
      notifyListeners();
    }
  }

  Future<void> createStatus(String text, {String? mediaUrl, String? caption}) async {
    final success = await ApiService.createStatus(text, mediaUrl: mediaUrl, caption: caption);
    if (success) {
      final updatedStatuses = await ApiService.getStatuses();
      _userStatuses = updatedStatuses;
      notifyListeners();
    }
  }

  Future<void> fetchCallLogs() async {
    try {
      final logs = await ApiService.getCallLogs();
      _callLogs = logs;
      notifyListeners();
    } catch (e) {
      debugPrint('[AppState] Error fetching call logs: $e');
    }
  }

  Future<void> fetchDeferredData() async {
    triggerBackgroundInitialization();
  }

  Future<void> fetchInitialData() async {
    triggerBackgroundInitialization();
  }

  void setActiveFolder(String folderId) {
    _activeFolderId = folderId;
    notifyListeners();
  }

  void toggleTagFilter(String tagId) {
    if (_selectedTagId == tagId) {
      _selectedTagId = null;
    } else {
      _selectedTagId = tagId;
    }
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> selectContact(String contactId) async {
    _activeContactId = contactId;
    _activeChatHistory = [];
    notifyListeners();

    final cStopwatch = Stopwatch()..start();
    // Fetch messages from api
    _activeChatHistory = await ApiService.getMessages(contactId);
    cStopwatch.stop();
    debugPrint('[Performance Logging] Chat history loading duration for contact $contactId: ${cStopwatch.elapsedMilliseconds}ms');
    
    // Clear local unread counts in contact list
    int index = _contacts.indexWhere((c) => c.id == contactId);
    if (index != -1) {
      _contacts[index] = _contacts[index].copyWith(unreadCount: 0);
    }
    
    notifyListeners();
  }

  void closeConversation() {
    _activeContactId = null;
    _activeChatHistory = [];
    notifyListeners();
    refreshContacts(); // Refresh list to get any new updates
  }

  Future<void> refreshContacts() async {
    _contacts = await ApiService.getContacts();
    notifyListeners();
  }

  Future<bool> sendMessage(String text, {bool isAudio = false, String? duration, bool isFile = false, String? fileName, String? fileSize}) async {
    if (_activeContactId == null) return false;
    final contactId = _activeContactId!;

    final response = await ApiService.sendMessage(
      contactId,
      text: text,
      isAudio: isAudio,
      duration: duration,
      isFile: isFile,
      fileName: fileName,
      fileSize: fileSize,
    );

    if (response != null && response['status'] == 'success') {
      // Append user message
      final userMsg = Message.fromJson(response['user_message']);
      _activeChatHistory.add(userMsg);

      // Append bot message if any
      if (response['bot_message'] != null) {
        final botMsg = Message.fromJson(response['bot_message']);
        _activeChatHistory.add(botMsg);
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> pollMessages() async {
    if (_activeContactId == null) return;
    final contactId = _activeContactId!;
    try {
      final newHistory = await ApiService.getMessages(contactId);
      
      bool isDifferent = newHistory.length != _activeChatHistory.length;
      if (!isDifferent && newHistory.isNotEmpty && _activeChatHistory.isNotEmpty) {
        if (newHistory.last.id != _activeChatHistory.last.id ||
            newHistory.last.reactions.length != _activeChatHistory.last.reactions.length) {
          isDifferent = true;
        } else {
          for (int i = 0; i < newHistory.length; i++) {
            if (newHistory[i].text != _activeChatHistory[i].text ||
                newHistory[i].reactions.length != _activeChatHistory[i].reactions.length) {
              isDifferent = true;
              break;
            }
          }
        }
      }
      
      if (isDifferent) {
        _activeChatHistory = newHistory;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Polling Error: $e');
    }
  }

  Future<void> reactToMessage(int messageId, String emoji) async {
    if (_activeContactId == null) return;
    final contactId = _activeContactId!;

    final newReactions = await ApiService.reactToMessage(contactId, messageId, emoji);
    
    int index = _activeChatHistory.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final old = _activeChatHistory[index];
      _activeChatHistory[index] = Message(
        id: old.id,
        contactId: old.contactId,
        text: old.text,
        isUser: old.isUser,
        time: old.time,
        isAudio: old.isAudio,
        duration: old.duration,
        isFile: old.isFile,
        fileName: old.fileName,
        fileSize: old.fileSize,
        reactions: newReactions,
        status: old.status,
      );
      notifyListeners();
    }
  }

  Future<bool> updateContactAssignments(String contactId, String folder, List<String> tagIds) async {
    final success = await ApiService.assignContact(contactId, folder: folder, tagIds: tagIds);
    if (success) {
      // Update local state
      List<Tag> assignedTags = _tags.where((t) => tagIds.contains(t.id)).toList();
      int index = _contacts.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _contacts[index] = _contacts[index].copyWith(folder: folder, tags: assignedTags);
      }
      notifyListeners();
    }
    return success;
  }

  Future<bool> moveCustomerToStaff(String customerId, String staffId) async {
    final success = await ApiService.assignContact(customerId, assignedStaffId: staffId);
    if (success) {
      int index = _contacts.indexWhere((c) => c.id == customerId);
      if (index != -1) {
        _contacts[index] = _contacts[index].copyWith(assignedStaffId: staffId);
      }
      notifyListeners();
    }
    return success;
  }

  Future<bool> removeCustomerFromStaff(String customerId) async {
    final success = await ApiService.assignContact(customerId, assignedStaffId: "");
    if (success) {
      int index = _contacts.indexWhere((c) => c.id == customerId);
      if (index != -1) {
        _contacts[index] = _contacts[index].copyWith(assignedStaffId: "");
      }
      notifyListeners();
    }
    return success;
  }

  Future<bool> addContact({
    required String name,
    required String phone,
    required String folder,
    String role = '',
    String avatar = '',
    String email = '',
    String notes = '',
    String countryCode = '',
  }) async {
    _isLoading = true;
    notifyListeners();
    final newContact = await ApiService.createContact(
      name: name,
      phone: phone,
      folder: folder,
      role: role,
      avatar: avatar,
      email: email,
      notes: notes,
      countryCode: countryCode,
    );
    _isLoading = false;
    if (newContact != null) {
      _contacts.add(newContact);
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<bool> addStaffFolder(String name, String phone, String role) async {
    return addContact(
      name: name,
      phone: phone,
      folder: 'staff',
      role: role,
    );
  }

  Future<bool> deleteContact(String contactId) async {
    final success = await ApiService.deleteContact(contactId);
    if (success) {
      _contacts.removeWhere((c) => c.id == contactId);
      _activeChatHistory.removeWhere((m) => m.contactId == contactId);
      for (int i = 0; i < _contacts.length; i++) {
        if (_contacts[i].assignedStaffId == contactId) {
          _contacts[i] = _contacts[i].copyWith(assignedStaffId: "");
        }
      }
      notifyListeners();
    }
    return success;
  }

  Future<bool> deleteStaffFolder(String staffId) async {
    return deleteContact(staffId);
  }

  Future<bool> createAndAddTag(String name, String color) async {
    String id = name.toLowerCase().replaceAll(' ', '_');
    final newTag = await ApiService.createTag(id, name, color);
    if (newTag != null) {
      _tags.add(newTag);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> fetchProfile() async {
    final profile = await ApiService.getProfile();
    if (profile != null) {
      _currentProfile = profile;
      _userProfile = {
        'name': profile.name,
        'role': profile.role,
        'avatar': profile.avatar,
        'email': profile.email,
        'phone': profile.phone,
      };
      notifyListeners();
    }
  }

  Future<bool> updateProfile(UserProfile profile) async {
    _isLoading = true;
    notifyListeners();
    final updated = await ApiService.updateProfile(profile);
    _isLoading = false;
    if (updated != null) {
      _currentProfile = updated;
      _userProfile = {
        'name': updated.name,
        'role': updated.role,
        'avatar': updated.avatar,
        'email': updated.email,
        'phone': updated.phone,
      };
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<void> fetchBroadcastLists() async {
    _broadcastLists = await ApiService.getBroadcastLists();
    notifyListeners();
  }

  Future<bool> createBroadcastList(String name, List<String> memberIds, {String? id}) async {
    _isLoading = true;
    notifyListeners();
    final success = await ApiService.createBroadcastList(name, memberIds, id: id);
    _isLoading = false;
    if (success) {
      await fetchBroadcastLists();
    }
    notifyListeners();
    return success;
  }

  Future<bool> deleteBroadcastList(String id) async {
    _isLoading = true;
    notifyListeners();
    final success = await ApiService.deleteBroadcastList(id);
    _isLoading = false;
    if (success) {
      await fetchBroadcastLists();
    }
    notifyListeners();
    return success;
  }

  Future<void> fetchBroadcastHistory() async {
    _broadcastHistory = await ApiService.getBroadcastHistory();
    notifyListeners();
  }

  Future<bool> sendBroadcastMessage(
    List<String> recipientIds,
    String text, {
    bool isFile = false,
    String? fileName,
    String? fileSize,
  }) async {
    _isLoading = true;
    notifyListeners();

    final success = await ApiService.sendBroadcast(
      recipientIds,
      text,
      isFile: isFile,
      fileName: fileName,
      fileSize: fileSize,
    );
    _isLoading = false;
    notifyListeners();

    if (success) {
      await refreshContacts();
      await fetchBroadcastHistory();
    }
    return success;
  }

  // --- WHATSAPP PARITY STATE & ACTIONS ---
  List<ChannelModel> _channels = [];
  bool _isAppLocked = false;
  String _appLockPin = '1234';

  List<ChannelModel> get channels => _channels;
  bool get isAppLocked => _isAppLocked;

  void unlockApp() {
    _isAppLocked = false;
    notifyListeners();
  }

  void setAppLocked(bool locked) {
    _isAppLocked = locked;
    notifyListeners();
  }

  Future<void> fetchChannels() async {
    _channels = await ApiService.getChannels();
    notifyListeners();
  }

  Future<bool> followChannel(String channelId) async {
    final success = await ApiService.followChannel(channelId);
    if (success) {
      await fetchChannels();
    }
    return success;
  }

  Future<bool> createGroup(String name, String description, List<String> memberIds) async {
    _isLoading = true;
    notifyListeners();
    final res = await ApiService.createGroup(name, description, memberIds);
    _isLoading = false;
    if (res != null && res['success'] == true) {
      await refreshContacts();
      if (res['group_id'] != null) {
        await selectContact(res['group_id']);
      }
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<bool> sendLocationMessage(double lat, double lng, String locationName) async {
    if (_activeContactId == null) return false;
    final payload = {
      'text': '📍 Shared Location: $locationName',
      'latitude': lat,
      'longitude': lng,
      'location_name': locationName,
    };
    final msg = await ApiService.sendMessagePayload(_activeContactId!, payload);
    if (msg != null) {
      _activeChatHistory.add(msg);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> sendContactCardMessage(String contactId, String contactName, String contactPhone) async {
    if (_activeContactId == null) return false;
    final payload = {
      'text': '👤 Shared Contact: $contactName',
      'contact_card_id': contactId,
      'contact_card_name': contactName,
      'contact_card_phone': contactPhone,
    };
    final msg = await ApiService.sendMessagePayload(_activeContactId!, payload);
    if (msg != null) {
      _activeChatHistory.add(msg);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> toggleStarMessage(int msgId) async {
    final success = await ApiService.toggleStarMessage(msgId);
    if (success) {
      int idx = _activeChatHistory.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        final old = _activeChatHistory[idx];
        _activeChatHistory[idx] = Message(
          id: old.id,
          contactId: old.contactId,
          text: old.text,
          isUser: old.isUser,
          time: old.time,
          isAudio: old.isAudio,
          duration: old.duration,
          isFile: old.isFile,
          fileName: old.fileName,
          fileSize: old.fileSize,
          reactions: old.reactions,
          status: old.status,
          isBroadcast: old.isBroadcast,
          replyToId: old.replyToId,
          replyToText: old.replyToText,
          replyToSender: old.replyToSender,
          isEdited: old.isEdited,
          isDeleted: old.isDeleted,
          isPinned: old.isPinned,
          isStarred: !old.isStarred,
          pollId: old.pollId,
          latitude: old.latitude,
          longitude: old.longitude,
          locationName: old.locationName,
          contactCardId: old.contactCardId,
          contactCardName: old.contactCardName,
          contactCardPhone: old.contactCardPhone,
        );
        notifyListeners();
      }
    }
    return success;
  }

  // ========== PHASE 1: WhatsApp Feature Parity State Methods ==========

  /// Fetch and apply chat preferences (archived, muted, pinned, blocked)
  Future<void> fetchChatPreferences() async {
    try {
      final data = await ApiService.getChatPreferences();
      if (data != null) {
        _chatPreferences = ChatPreferences.fromJson(data);
        // Apply preferences to contact models
        for (int i = 0; i < _contacts.length; i++) {
          final c = _contacts[i];
          _contacts[i] = c.copyWith(
            isArchived: _chatPreferences.archived.contains(c.id),
            isMuted: _chatPreferences.muted.containsKey(c.id),
            isPinned: _chatPreferences.pinned.contains(c.id),
            isBlocked: _chatPreferences.blocked.contains(c.id),
            wallpaperUrl: _chatPreferences.wallpapers[c.id],
          );
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching chat preferences: $e');
    }
  }

  /// Toggle archived chats visibility
  void toggleShowArchived() {
    _showArchivedChats = !_showArchivedChats;
    notifyListeners();
  }

  /// Archive/unarchive a chat
  Future<bool> toggleArchiveChat(String contactId) async {
    final result = await ApiService.toggleArchive(contactId);
    if (result != null && result['success'] == true) {
      await fetchChatPreferences();
      return true;
    }
    return false;
  }

  /// Mute/unmute a chat
  Future<bool> toggleMuteChat(String contactId, {String? mutedUntil}) async {
    final result = await ApiService.toggleMute(contactId, mutedUntil: mutedUntil);
    if (result != null && result['success'] == true) {
      await fetchChatPreferences();
      return true;
    }
    return false;
  }

  /// Pin/unpin a chat
  Future<bool> togglePinChat(String contactId) async {
    final result = await ApiService.togglePin(contactId);
    if (result != null && result['success'] == true) {
      await fetchChatPreferences();
      return true;
    }
    return false;
  }

  /// Block/unblock a contact
  Future<bool> toggleBlockContact(String contactId) async {
    final result = await ApiService.toggleBlock(contactId);
    if (result != null && result['success'] == true) {
      await fetchChatPreferences();
      return true;
    }
    return false;
  }

  /// Clear chat history for a contact
  Future<bool> clearChatHistory(String contactId) async {
    final success = await ApiService.clearChat(contactId);
    if (success) {
      if (_activeContactId == contactId) {
        _activeChatHistory = [];
      }
      // Update the contact's last message
      final idx = _contacts.indexWhere((c) => c.id == contactId);
      if (idx != -1) {
        _contacts[idx] = _contacts[idx].copyWith(unreadCount: 0);
      }
      notifyListeners();
    }
    return success;
  }

  /// Export chat to text
  Future<String?> exportChatText(String contactId) async {
    final data = await ApiService.exportChat(contactId);
    if (data != null) {
      return data['export'] as String?;
    }
    return null;
  }

  /// Set typing indicator
  Future<void> sendTypingIndicator(String contactId, bool isTyping) async {
    await ApiService.setTyping(contactId, isTyping);
  }

  /// Get typing indicators for a contact
  Future<List<TypingIndicator>> getTypingIndicators(String contactId) async {
    final data = await ApiService.getTyping(contactId);
    return data.map((e) => TypingIndicator.fromJson(e)).toList();
  }

  /// Update user's own online presence
  Future<void> updateOnlinePresence(bool isOnline) async {
    await ApiService.updatePresence(isOnline);
  }

  /// Get presence for a specific user
  Future<UserPresence?> getUserPresence(String userId) async {
    final data = await ApiService.getPresence(userId);
    if (data != null) {
      final presence = UserPresence.fromJson(data);
      _presenceCache[userId] = presence;
      return presence;
    }
    return _presenceCache[userId];
  }

  /// Check if a contact is archived
  bool isArchived(String contactId) => _chatPreferences.archived.contains(contactId);

  /// Check if a contact is muted
  bool isMuted(String contactId) => _chatPreferences.muted.containsKey(contactId);

  /// Check if a contact is pinned
  bool isPinnedChat(String contactId) => _chatPreferences.pinned.contains(contactId);

  /// Check if a contact is blocked
  bool isBlocked(String contactId) => _chatPreferences.blocked.contains(contactId);

  /// Get wallpaper for a contact (falls back to default)
  String? getWallpaper(String contactId) {
    return _chatPreferences.wallpapers[contactId] ?? _chatPreferences.wallpapers['__default__'];
  }

  // ========== PHASE 5: Advanced WhatsApp Parity Methods ==========

  /// Toggle pin for a specific message in a chat
  Future<bool> togglePinMessage(int msgId) async {
    final success = await ApiService.togglePinMessage(msgId);
    if (success && _activeContactId != null) {
      await pollMessages();
    }
    return success;
  }

  /// Get all pinned messages for a chat
  Future<List<Message>> getPinnedMessages(String contactId) async {
    final data = await ApiService.getPinnedMessages(contactId);
    return data.map((e) => Message.fromJson(e)).toList();
  }

  /// Mark view-once media as viewed
  Future<bool> markViewOnce(int msgId) async {
    final success = await ApiService.markViewOnce(msgId);
    if (success && _activeContactId != null) {
      await pollMessages();
    }
    return success;
  }

  /// Forward messages to one or more contacts
  Future<bool> forwardMessageToContacts(List<int> msgIds, List<String> targetContactIds) async {
    final success = await ApiService.forwardMessages(msgIds, targetContactIds);
    if (success) {
      await refreshContacts();
      if (_activeContactId != null) {
        await pollMessages();
      }
    }
    return success;
  }

  /// Record status view
  Future<void> recordStatusView(String statusId) async {
    await ApiService.recordStatusView(statusId);
  }

  /// Get viewers for a status
  Future<List<Map<String, dynamic>>> getStatusViews(String statusId) async {
    return await ApiService.getStatusViews(statusId);
  }

  /// Get all starred messages across all chats
  Future<List<Message>> getStarredMessages() async {
    final data = await ApiService.getStarredMessages();
    return data.map((e) => Message.fromJson(e)).toList();
  }

  /// Create a shareable call link
  Future<Map<String, dynamic>?> createCallLink({String callType = 'video', String linkName = 'GebTalk Meeting'}) async {
    return await ApiService.createCallLink(callType: callType, linkName: linkName);
  }

  /// Get storage summary and chat breakdowns
  Future<Map<String, dynamic>?> getStorageSummary() async {
    return await ApiService.getStorageSummary();
  }

  /// Clear media for a specific chat
  Future<bool> clearChatMedia(String contactId) async {
    return await ApiService.clearChatMedia(contactId);
  }

  /// Set Account 2FA
  Future<bool> setAccount2FA(bool enabled, String pin) async {
    return await ApiService.setAccount2FA(enabled, pin);
  }

  /// Delete Account
  Future<bool> deleteAccount() async {
    return await ApiService.deleteAccount();
  }

  /// Alias for selectContact
  void openChat(String contactId) {
    selectContact(contactId);
  }

  /// Set Chat Wallpaper
  Future<void> setChatWallpaper(String contactId, String colorHex) async {
    await ApiService.setChatWallpaper(contactId, colorHex);
    await fetchChatPreferences();
  }

  /// Delete Message
  Future<void> deleteMessage(int messageId) async {
    final success = await ApiService.deleteMessage(messageId);
    if (success) {
      _activeChatHistory.removeWhere((m) => m.id == messageId);
      notifyListeners();
    }
  }

  /// Messages getter alias for active chat history
  List<Message> get messages => _activeChatHistory;

  // ========== EMAIL-FIRST STATE ACTIONS ==========

  /// Fetch emails for folder with optional search
  Future<void> fetchEmails({String? folder, String search = '', bool silent = false}) async {
    if (folder != null) _currentEmailFolder = folder;
    if (!silent) {
      _isLoadingEmails = true;
      notifyListeners();
    }

    try {
      final res = await ApiService.getEmails(folder: _currentEmailFolder, search: search);
      final rawEmails = res['emails'];
      if (rawEmails is List) {
        _emails = rawEmails.map((e) => e is EmailMessage ? e : EmailMessage.fromJson(Map<String, dynamic>.from(e))).toList();
      } else {
        _emails = [];
      }
      _unreadEmailCount = res['unread_count'] is int ? res['unread_count'] : 0;
      final rawCounts = res['counts'] != null ? Map<String, dynamic>.from(res['counts'] as Map) : <String, dynamic>{};
      _emailFolderCounts = rawCounts.map((k, v) => MapEntry(k, v is int ? v : int.tryParse(v.toString()) ?? 0));
    } catch (e) {
      debugPrint('Error in fetchEmails: $e');
    } finally {
      _isLoadingEmails = false;
      notifyListeners();
    }
  }

  /// Dispatch an email
  Future<bool> sendEmail({
    required String toEmail,
    required String subject,
    required String bodyText,
    String? bodyHtml,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final success = await ApiService.sendEmailMessage(
      toEmail: toEmail,
      subject: subject,
      bodyText: bodyText,
      bodyHtml: bodyHtml,
      attachments: attachments,
    );
    if (success) {
      await fetchEmails(silent: true);
    }
    return success;
  }

  /// Toggle star on email
  Future<void> toggleEmailStar(String emailId) async {
    final idx = _emails.indexWhere((e) => e.id == emailId);
    if (idx != -1) {
      _emails[idx].isStarred = !_emails[idx].isStarred;
      notifyListeners();
    }
    await ApiService.toggleEmailStar(emailId);
    await fetchEmails(silent: true);
  }

  /// Delete or move email to trash
  Future<void> deleteEmail(String emailId) async {
    _emails.removeWhere((e) => e.id == emailId);
    notifyListeners();
    await ApiService.deleteEmail(emailId);
    await fetchEmails(silent: true);
  }

  /// Fetch pending contact requests
  Future<void> fetchContactRequests() async {
    _isLoadingRequests = true;
    notifyListeners();
    try {
      _contactRequests = await ApiService.getContactRequests();
    } catch (e) {
      debugPrint('Error in fetchContactRequests: $e');
    } finally {
      _isLoadingRequests = false;
      notifyListeners();
    }
  }

  /// Send contact request to email or user ID
  Future<bool> sendContactRequest({String? targetEmail, String? targetId, String? message}) async {
    final res = await ApiService.sendContactRequest(
      targetEmail: targetEmail,
      targetId: targetId,
      message: message,
    );
    if (res != null && res['success'] == true) {
      await fetchContactRequests();
      return true;
    }
    return false;
  }

  /// Convenience method to trigger/refresh contacts and initial data
  void fetchContacts() {
    triggerBackgroundInitialization();
  }

  /// Respond to incoming contact request (accept/decline)
  Future<bool> respondContactRequest(int requestId, String action) async {
    final success = await ApiService.respondContactRequest(requestId, action);
    if (success) {
      _contactRequests.removeWhere((r) => r.id == requestId);
      notifyListeners();
      triggerBackgroundInitialization();
    }
    return success;
  }

  /// Convert an email thread to in-app chat
  Future<Map<String, dynamic>?> convertEmailToChat(String emailId) async {
    final res = await ApiService.convertEmailToChat(emailId);
    if (res != null && res['success'] == true) {
      triggerBackgroundInitialization();
      final contactData = res['contact'];
      if (contactData != null && contactData['id'] != null) {
        selectContact(contactData['id'].toString());
      }
    }
    return res;
  }

  /// Forward a chat transcript as an email
  Future<bool> forwardChatToEmail({
    required String toEmail,
    String? contactId,
    List<int>? messageIds,
    String? subject,
  }) async {
    final res = await ApiService.forwardChatToEmail(
      toEmail: toEmail,
      contactId: contactId ?? _activeContactId,
      messageIds: messageIds,
      subject: subject,
    );
    if (res != null && res['success'] == true) {
      await fetchEmails(silent: true);
      return true;
    }
    return false;
  }
}

