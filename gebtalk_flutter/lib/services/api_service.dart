import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_models.dart';
import '../models/email_models.dart';
import '../utils/error_handler.dart';

class ApiService {
  static String? authenticatedPhone;

  static const String defaultFallbackUrl = 'https://anniversary-mini-virgin-amongst.trycloudflare.com/api';
  static String? _customBaseUrl;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('saved_custom_base_url');
      if (saved != null && saved.isNotEmpty) {
        _customBaseUrl = saved;
      }
    } catch (_) {}
  }

  static void logDebug(String message) {
    try {
      final t = DateTime.now().millisecondsSinceEpoch;
      http.get(Uri.parse('$baseUrl/debug/log?msg=${Uri.encodeComponent(message)}&_t=$t'));
    } catch (_) {}
  }

  static const String _envApiUrl = String.fromEnvironment('API_URL', defaultValue: '');

  static String get baseUrl {
    if (_customBaseUrl != null) return _customBaseUrl!;
    if (_envApiUrl.isNotEmpty) return _envApiUrl;
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
      if (host != 'localhost' && host != '127.0.0.1' && !host.startsWith('192.168.') && !host.startsWith('10.')) {
        // Production web deployment: route directly to active cloud tunnel
        return defaultFallbackUrl;
      }
      return 'http://$host:5000/api';
    } else {
      try {
        if (Platform.isAndroid) {
          return 'http://10.0.2.2:5000/api';
        }
      } catch (_) {}
      return 'http://127.0.0.1:5000/api';
    }
  }

  static set baseUrl(String value) {
    _customBaseUrl = value;
    try {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('saved_custom_base_url', value);
      });
    } catch (_) {}
  }

  static Map<String, String> _authHeaders({bool json = false}) {
    final headers = <String, String>{
      'Bypass-Tunnel-Reminder': 'true',
      'bypass-tunnel-reminder': 'true',
      'ngrok-skip-browser-warning': 'true',
    };
    if (json) headers['Content-Type'] = 'application/json';
    if (authenticatedPhone != null) {
      headers['Authorization'] = 'Bearer $authenticatedPhone';
      headers['x-user-phone'] = authenticatedPhone!;
    }
    return headers;
  }

  static String resolveUrl(String url) {
    if (!url.startsWith('http')) return url;
    try {
      final currentBase = baseUrl;
      final backendUri = Uri.parse(currentBase);
      final targetUri = Uri.parse(url);
      
      if ((targetUri.host == 'localhost' || targetUri.host == '127.0.0.1') &&
          (backendUri.host != 'localhost' && backendUri.host != '127.0.0.1' && backendUri.host.isNotEmpty)) {
        return targetUri.replace(host: backendUri.host, port: backendUri.port).toString();
      }
    } catch (_) {}
    return url;
  }


  static Future<String?> uploadFile(List<int> bytes, String fileName) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      request.headers.addAll(_authHeaders());
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'];
      }
    } catch (e) {
      debugPrint('Upload Error: $e');
    }
    return null;
  }

  static String? lastAuthError;

  static dynamic _parseJsonResponse(http.Response response, {String? defaultErrorMessage}) {
    if (response.statusCode >= 500) {
      lastAuthError = 'SERVER_ERROR';
      ErrorHandler.showError('Backend Server Unavailable (HTTP ${response.statusCode}). Please check server status.');
      return null;
    }
    final body = response.body.trim();
    if (body.isEmpty || body.startsWith('<') || (!body.startsWith('{') && !body.startsWith('['))) {
      lastAuthError = 'SERVER_ERROR';
      ErrorHandler.showError('Backend server returned unexpected response (HTTP ${response.statusCode}). Check server endpoint in Settings (⚙️).');
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      if (response.statusCode >= 400) {
        lastAuthError = (decoded is Map && decoded['error'] != null) ? decoded['error'].toString() : 'AUTH_FAILED';
        ErrorHandler.showError(lastAuthError ?? defaultErrorMessage ?? 'Request failed (${response.statusCode})');
        return null;
      }
      lastAuthError = null;
      return decoded;
    } catch (e) {
      lastAuthError = 'PARSE_ERROR';
      ErrorHandler.showError('Malformed response from server. Check backend status.');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> sendOtp(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 30));
      final data = _parseJsonResponse(response, defaultErrorMessage: 'Failed to send OTP');
      if (data != null && data is Map<String, dynamic>) {
        return data;
      }
    } catch (e) {
      debugPrint('API Error: $e');
      lastAuthError = 'NETWORK_ERROR';
      ErrorHandler.showError('Network Error: Unable to reach backend server.');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> sendEmailOtp(String email, {String name = ''}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/send-email-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'name': name}),
      ).timeout(const Duration(seconds: 30));
      final data = _parseJsonResponse(response, defaultErrorMessage: 'Failed to send Email OTP');
      if (data != null && data is Map<String, dynamic>) {
        return data;
      }
    } catch (e) {
      debugPrint('API Error: $e');
      lastAuthError = 'NETWORK_ERROR';
      ErrorHandler.showError('Network Error: Unable to reach backend server.');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> verifyEmailOtp(String email, String otp, {String name = ''}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-email-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
          'name': name,
        }),
      ).timeout(const Duration(seconds: 30));
      final data = _parseJsonResponse(response, defaultErrorMessage: 'Invalid Email OTP');
      if (data != null && data is Map<String, dynamic>) {
        if (data['token'] != null) {
          authenticatedPhone = data['token'];
        }
        return data;
      }
    } catch (e) {
      debugPrint('API Error: $e');
      lastAuthError = 'NETWORK_ERROR';
      ErrorHandler.showError('Network Error: Unable to reach backend server.');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> loginWithEmail(String identifier, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login-email'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'identifier': identifier.trim(),
          'email': identifier.trim(),
          'username': identifier.trim(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 500 && baseUrl != defaultFallbackUrl) {
        final fallbackRes = await http.post(
          Uri.parse('$defaultFallbackUrl/auth/login-email'),
          headers: _authHeaders(json: true),
          body: jsonEncode({
            'identifier': identifier.trim(),
            'email': identifier.trim(),
            'username': identifier.trim(),
            'password': password,
          }),
        ).timeout(const Duration(seconds: 15));
        final fallbackData = _parseJsonResponse(fallbackRes, defaultErrorMessage: 'Invalid username/email or password');
        if (fallbackData != null && fallbackData is Map<String, dynamic>) {
          baseUrl = defaultFallbackUrl;
          if (fallbackData['token'] != null) {
            authenticatedPhone = fallbackData['token'];
          }
          return fallbackData;
        }
      }

      final data = _parseJsonResponse(response, defaultErrorMessage: 'Invalid username/email or password');
      if (data != null && data is Map<String, dynamic>) {
        if (data['token'] != null) {
          authenticatedPhone = data['token'];
        }
        return data;
      }
    } catch (e) {
      debugPrint('API Error: $e');
      if (baseUrl != defaultFallbackUrl) {
        try {
          final fallbackRes = await http.post(
            Uri.parse('$defaultFallbackUrl/auth/login-email'),
            headers: _authHeaders(json: true),
            body: jsonEncode({
              'identifier': identifier.trim(),
              'email': identifier.trim(),
              'username': identifier.trim(),
              'password': password,
            }),
          ).timeout(const Duration(seconds: 15));
          final fallbackData = _parseJsonResponse(fallbackRes, defaultErrorMessage: 'Invalid username/email or password');
          if (fallbackData != null && fallbackData is Map<String, dynamic>) {
            baseUrl = defaultFallbackUrl;
            if (fallbackData['token'] != null) {
              authenticatedPhone = fallbackData['token'];
            }
            return fallbackData;
          }
        } catch (_) {}
      }
      lastAuthError = 'NETWORK_ERROR';
      ErrorHandler.showError('Network Error: Unable to reach backend server.');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> verifyOtp(
    String phone,
    String otp, {
    String name = '',
    String countryCode = '',
    String countryName = '',
    String countryFlag = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'otp': otp,
          'name': name,
          'country_code': countryCode,
          'country_name': countryName,
          'country_flag': countryFlag,
        }),
      ).timeout(const Duration(seconds: 30));
      final data = _parseJsonResponse(response, defaultErrorMessage: 'Invalid OTP code');
      if (data != null && data is Map<String, dynamic>) {
        if (data['token'] != null) {
          authenticatedPhone = data['token'];
        }
        return data;
      }
    } catch (e) {
      debugPrint('API Error: $e');
      lastAuthError = 'NETWORK_ERROR';
      ErrorHandler.showError('Network Error: Unable to reach backend server.');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getInitData(String? phone) async {
    try {
      final uri = Uri.parse('$baseUrl/init').replace(
        queryParameters: phone != null ? {'phone': phone} : null,
      );
      final response = await http.get(uri, headers: _authHeaders()).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 530 && baseUrl != defaultFallbackUrl) {
        final fallbackUri = Uri.parse('$defaultFallbackUrl/init').replace(
          queryParameters: phone != null ? {'phone': phone} : null,
        );
        final fallbackRes = await http.get(fallbackUri, headers: _authHeaders()).timeout(const Duration(seconds: 15));
        if (fallbackRes.statusCode == 200) {
          baseUrl = defaultFallbackUrl;
          return jsonDecode(fallbackRes.body);
        }
      }
    } catch (e) {
      debugPrint('API Error (getInitData): $e');
      if (baseUrl != defaultFallbackUrl) {
        try {
          final fallbackUri = Uri.parse('$defaultFallbackUrl/init').replace(
            queryParameters: phone != null ? {'phone': phone} : null,
          );
          final fallbackRes = await http.get(fallbackUri, headers: _authHeaders()).timeout(const Duration(seconds: 15));
          if (fallbackRes.statusCode == 200) {
            baseUrl = defaultFallbackUrl;
            return jsonDecode(fallbackRes.body);
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<List<Folder>> getFolders() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/folders'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => Folder.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error (getFolders): $e');
    }
    return [];
  }

  static Future<List<Tag>> getTags() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/tags'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => Tag.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error (getTags): $e');
    }
    return [];
  }

  static Future<Tag?> createTag(String id, String name, String color) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/tags'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'id': id, 'name': name, 'color': color}),
      );
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        // Find newly created tag in returned list
        for (var item in data) {
          if (item['id'] == id) {
            return Tag.fromJson(item);
          }
        }
      }
    } catch (e) {
      debugPrint('API Error (createTag): $e');
    }
    return null;
  }

  static Future<List<Contact>> getContacts() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/contacts'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => Contact.fromJson(item)).toList();
      }
      if (response.statusCode == 530 && baseUrl != defaultFallbackUrl) {
        final fallbackRes = await http.get(Uri.parse('$defaultFallbackUrl/contacts'), headers: _authHeaders());
        if (fallbackRes.statusCode == 200) {
          baseUrl = defaultFallbackUrl;
          List data = jsonDecode(fallbackRes.body);
          return data.map((item) => Contact.fromJson(item)).toList();
        }
      }
    } catch (e) {
      debugPrint('API Error (getContacts): $e');
      if (baseUrl != defaultFallbackUrl) {
        try {
          final fallbackRes = await http.get(Uri.parse('$defaultFallbackUrl/contacts'), headers: _authHeaders());
          if (fallbackRes.statusCode == 200) {
            baseUrl = defaultFallbackUrl;
            List data = jsonDecode(fallbackRes.body);
            return data.map((item) => Contact.fromJson(item)).toList();
          }
        } catch (_) {}
      }
    }
    return [];
  }

  static Future<bool> assignContact(String contactId, {String? folder, List<String>? tagIds, String? assignedStaffId}) async {
    try {
      final Map<String, dynamic> body = {};
      if (folder != null) body['folder'] = folder;
      if (tagIds != null) body['tags'] = tagIds;
      if (assignedStaffId != null) body['assigned_staff_id'] = assignedStaffId;

      final response = await http.post(
        Uri.parse('$baseUrl/contacts/$contactId/assign'),
        headers: _authHeaders(json: true),
        body: jsonEncode(body),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
      return false;
    }
  }

  static Future<Contact?> createContact({
    required String name,
    required String phone,
    required String folder,
    String role = '',
    String avatar = '',
    String email = '',
    String notes = '',
    String countryCode = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'folder': folder,
          'role': role,
          'avatar': avatar,
          'email': email,
          'notes': notes,
          'country_code': countryCode,
        }),
      );
      if (response.statusCode == 200) {
        return Contact.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return null;
  }

  static Future<Contact?> createStaffFolder(String name, String phone, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/staff'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'role': role,
        }),
      );
      if (response.statusCode == 200) {
        return Contact.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return null;
  }

  static Future<bool> deleteContact(String contactId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/contacts/$contactId'),
        headers: _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
      return false;
    }
  }

  static Future<List<Message>> getMessages(String contactId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/contacts/$contactId/messages'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => Message.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error (getMessages): $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> sendMessage(
    String contactId, {
    String text = '',
    bool isAudio = false,
    String? duration,
    bool isFile = false,
    String? fileName,
    String? fileSize,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/$contactId/messages'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'text': text,
          'is_audio': isAudio,
          'duration': duration,
          'is_file': isFile,
          'file_name': fileName,
          'file_size': fileSize,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return null;
  }

  static Future<List<String>> reactToMessage(String contactId, int messageId, String emoji) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/$contactId/messages/$messageId/react'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'emoji': emoji}),
      );
      if (response.statusCode == 200) {
        Map<String, dynamic> body = jsonDecode(response.body);
        List reactList = body['reactions'] ?? [];
        return reactList.map((r) => r.toString()).toList();
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return [];
  }

  static Future<bool> sendBroadcast(
    List<String> recipientIds,
    String text, {
    bool isFile = false,
    String? fileName,
    String? fileSize,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/broadcast'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'recipients': recipientIds,
          'text': text,
          'is_file': isFile,
          'file_name': fileName,
          'file_size': fileSize,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
      return false;
    }
  }

  static Future<UserProfile?> getProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/profile'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return UserProfile.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return null;
  }

  static Future<UserProfile?> updateProfile(UserProfile profile) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'name': profile.name,
          'role': profile.role,
          'phone': profile.phone,
          'avatar': profile.avatar,
          'email': profile.email,
          'notifications_enabled': profile.notificationsEnabled,
          'notification_sound': profile.notificationSound,
          'notification_vibration': profile.notificationVibration,
          'security_2fa': profile.security2fa,
          'read_receipts': profile.readReceipts,
          'last_seen_visible': profile.lastSeenVisible,
          'country_code': profile.countryCode,
          'country_name': profile.countryName,
          'country_flag': profile.countryFlag,
        }),
      );
      if (response.statusCode == 200) {
        return UserProfile.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile/account/change-password'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Password changed successfully'};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed to change password'};
    } catch (e) {
      debugPrint('API Error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> adminUpdateCredentials({
    required String targetUserId,
    String? newEmail,
    String? newPassword,
    String? newName,
  }) async {
    try {
      final bodyMap = <String, dynamic>{
        'target_user_id': targetUserId,
      };
      if (newEmail != null && newEmail.trim().isNotEmpty) {
        bodyMap['email'] = newEmail.trim();
      }
      if (newPassword != null && newPassword.trim().isNotEmpty) {
        bodyMap['password'] = newPassword.trim();
      }
      if (newName != null && newName.trim().isNotEmpty) {
        bodyMap['name'] = newName.trim();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/admin/users/update-credentials'),
        headers: _authHeaders(json: true),
        body: jsonEncode(bodyMap),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Credentials updated successfully by CEO'};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed to update credentials'};
    } catch (e) {
      debugPrint('API Error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<List<BroadcastList>> getBroadcastLists() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/broadcast/lists'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => BroadcastList.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return [];
  }

  static Future<bool> createBroadcastList(String name, List<String> memberIds, {String? id}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/broadcast/lists'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          if (id != null) 'id': id,
          'name': name,
          'members': memberIds,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
      return false;
    }
  }

  static Future<bool> deleteBroadcastList(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/broadcast/lists/$id'),
        headers: _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
      return false;
    }
  }

  static Future<List<UserStatus>> getStatuses() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/statuses'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => UserStatus.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error: $e');
    }
    return [];
  }

  static Future<bool> createStatus(String text, {String? mediaUrl, String? caption}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/status/create'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'content_text': text,
          'media_url': mediaUrl,
          'caption': caption,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      return false;
    }
  }

  static Future<List<CallLog>> getCallLogs() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/calls'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => CallLog.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error: $e');
    }
    return [];
  }

  static Future<bool> logCall(String contactId, String contactName, String avatar, String callType, String direction, {String? duration}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calls/log'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'contact_id': contactId,
          'contact_name': contactName,
          'contact_avatar': avatar,
          'call_type': callType,
          'direction': direction,
          'duration': duration ?? '00:00',
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      return false;
    }
  }

  static Future<bool> editMessage(int messageId, String newText) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/edit'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'message_id': messageId, 'text': newText}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      return false;
    }
  }

  static Future<bool> deleteMessage(int messageId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/delete'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'message_id': messageId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      return false;
    }
  }

  static Future<bool> createPoll(String chatId, String question, List<String> options) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/polls/create'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'chat_id': chatId,
          'question': question,
          'options': options,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error: $e');
      return false;
    }
  }
  static Future<List<BroadcastHistoryItem>> getBroadcastHistory() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/broadcast/history'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => BroadcastHistoryItem.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error: $e');
      ErrorHandler.showError('Network Error: $e');
    }
    return [];
  }

  // --- WHATSAPP PARITY & ADVANCED FEATURES API METHODS ---

  static Future<Message?> sendMessagePayload(String contactId, Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/$contactId/messages'),
        headers: _authHeaders(json: true),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data['user_message'] != null) {
          return Message.fromJson(data['user_message']);
        }
      }
    } catch (e) {
      debugPrint('API Error (sendMessagePayload): $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> createGroup(String name, String description, List<String> memberIds) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/groups/create'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'name': name,
          'description': description,
          'member_ids': memberIds,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (createGroup): $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/groups/$groupId/members'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getGroupMembers): $e');
    }
    return [];
  }

  static Future<List<ChannelModel>> getChannels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/channels'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => ChannelModel.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error (getChannels): $e');
    }
    return [];
  }

  static Future<bool> followChannel(String channelId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/channels/$channelId/follow'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (followChannel): $e');
      return false;
    }
  }

  static Future<List<ChannelPost>> getChannelPosts(String channelId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/channels/$channelId/posts'), headers: _authHeaders());
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((item) => ChannelPost.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('API Error (getChannelPosts): $e');
    }
    return [];
  }

  static Future<bool> toggleStarMessage(int msgId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/$msgId/star'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (toggleStarMessage): $e');
      return false;
    }
  }

  static Future<bool> forwardMessages(List<int> msgIds, List<String> targetContactIds) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/forward'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'msg_ids': msgIds,
          'target_contact_ids': targetContactIds,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (forwardMessages): $e');
      return false;
    }
  }

  static Future<bool> setDisappearingTimer(String contactId, int timerSeconds) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/$contactId/disappearing'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'disappearing_timer': timerSeconds}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (setDisappearingTimer): $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> globalSearch(String query, {String filter = 'all'}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/search?q=${Uri.encodeComponent(query)}&filter=$filter'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (globalSearch): $e');
    }
    return null;
  }

  static Future<String?> translateMessage(String text, String targetLanguage) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/ai/translate'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'text': text,
          'target_language': targetLanguage,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['translated_text'];
      }
    } catch (e) {
      debugPrint('API Error (translateMessage): $e');
    }
    return null;
  }

  static Future<String?> summarizeChat(String contactId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/ai/summarize'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'contact_id': contactId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['summary'];
      }
    } catch (e) {
      debugPrint('API Error (summarizeChat): $e');
    }
    return null;
  }

  static Future<bool> setAppLock(bool enabled, String pin) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile/app-lock'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'enabled': enabled, 'pin': pin}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (setAppLock): $e');
      return false;
    }
  }

  // ========== PHASE 1: WhatsApp Feature Parity API Methods ==========

  // --- Typing Indicators ---

  static Future<bool> setTyping(String contactId, bool isTyping) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/typing'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'contact_id': contactId, 'is_typing': isTyping}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (setTyping): $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getTyping(String contactId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/typing/$contactId'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getTyping): $e');
    }
    return [];
  }

  // --- Online Presence ---

  static Future<bool> updatePresence(bool isOnline) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/presence/update'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'is_online': isOnline}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (updatePresence): $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getPresence(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/presence/$userId'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (getPresence): $e');
    }
    return null;
  }

  // --- Archive Chat ---

  static Future<Map<String, dynamic>?> toggleArchive(String contactId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/$contactId/archive'),
        headers: _authHeaders(json: true),
        body: jsonEncode({}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (toggleArchive): $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getArchivedChats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/chats/archived'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getArchivedChats): $e');
    }
    return [];
  }

  // --- Mute Chat ---

  static Future<Map<String, dynamic>?> toggleMute(String contactId, {String? mutedUntil}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/$contactId/mute'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'muted_until': mutedUntil}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (toggleMute): $e');
    }
    return null;
  }

  // --- Pin Chat ---

  static Future<Map<String, dynamic>?> togglePin(String contactId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/$contactId/pin'),
        headers: _authHeaders(json: true),
        body: jsonEncode({}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (togglePin): $e');
    }
    return null;
  }

  // --- Block Contact ---

  static Future<Map<String, dynamic>?> toggleBlock(String contactId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/$contactId/block'),
        headers: _authHeaders(json: true),
        body: jsonEncode({}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (toggleBlock): $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getBlockedContacts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/contacts/blocked'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getBlockedContacts): $e');
    }
    return [];
  }

  // --- Chat Wallpaper ---

  static Future<bool> setWallpaper(String contactId, String wallpaperUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/$contactId/wallpaper'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'wallpaper_url': wallpaperUrl}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (setWallpaper): $e');
      return false;
    }
  }

  // --- Chat Preferences ---

  static Future<Map<String, dynamic>?> getChatPreferences() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/chats/preferences'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (getChatPreferences): $e');
    }
    return null;
  }

  // --- Message Read Receipts ---

  static Future<List<Map<String, dynamic>>> getMessageReceipts(int messageId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/$messageId/receipts'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getMessageReceipts): $e');
    }
    return [];
  }

  // --- Chat Media Gallery ---

  static Future<List<Map<String, dynamic>>> getChatMedia(String contactId, {String filter = 'all'}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/chats/$contactId/media?filter=$filter'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getChatMedia): $e');
    }
    return [];
  }

  // --- Clear Chat History ---

  static Future<bool> clearChat(String contactId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/$contactId/clear'),
        headers: _authHeaders(json: true),
        body: jsonEncode({}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (clearChat): $e');
      return false;
    }
  }

  // --- Export Chat ---

  static Future<Map<String, dynamic>?> exportChat(String contactId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/chats/$contactId/export'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (exportChat): $e');
    }
    return null;
  }

  // ========== PHASE 2: Stickers & GIFs API Methods ==========

  static Future<List<Map<String, dynamic>>> getStickerPacks() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/stickers/packs'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getStickerPacks): $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getPackStickers(String packId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/stickers/packs/$packId/stickers'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getPackStickers): $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> searchGifs(String query) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/gifs/search?q=$query'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (searchGifs): $e');
    }
    return [];
  }

  // ========== PHASE 3: Communities, Payments & Newsletters API Methods ==========

  // --- Communities ---

  static Future<List<Map<String, dynamic>>> getCommunities() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/communities'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getCommunities): $e');
    }
    return [];
  }

  static Future<bool> createCommunity(String name, String description) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/communities'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'name': name, 'description': description}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (createCommunity): $e');
      return false;
    }
  }

  // --- Payments & Wallet ---

  static Future<Map<String, dynamic>?> getWalletBalance() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wallet/balance'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (getWalletBalance): $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> sendPayment(String receiverId, double amount, String note) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/payments/send'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'receiver_id': receiverId,
          'amount': amount,
          'note': note,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (sendPayment): $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/payments/history'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getPaymentHistory): $e');
    }
    return [];
  }

  // --- Newsletters ---

  static Future<List<Map<String, dynamic>>> getNewsletters() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/newsletters'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getNewsletters): $e');
    }
    return [];
  }

  static Future<bool> followNewsletter(String id) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/newsletters/$id/follow'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (followNewsletter): $e');
      return false;
    }
  }

  // ========== PHASE 4: Linked Devices, Report & Settings API Methods ==========

  // --- Linked Devices ---

  static Future<List<Map<String, dynamic>>> getLinkedDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/devices'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getLinkedDevices): $e');
    }
    return [];
  }

  static Future<bool> linkDevice(String deviceName, {String deviceType = 'web'}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices/link'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'device_name': deviceName, 'device_type': deviceType}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (linkDevice): $e');
      return false;
    }
  }

  static Future<bool> unlinkDevice(String did) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices/$did/unlink'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (unlinkDevice): $e');
      return false;
    }
  }

  // --- Report Contact ---

  static Future<bool> reportContact(String reportedId, {String reportType = 'spam', String reason = ''}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/report'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'reported_id': reportedId,
          'report_type': reportType,
          'reason': reason,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (reportContact): $e');
      return false;
    }
  }

  // ========== PHASE 5: Advanced WhatsApp Parity API Methods ==========

  // --- Pinned Messages in Chat ---
  static Future<bool> togglePinMessage(int msgId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/$msgId/pin'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (togglePinMessage): $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getPinnedMessages(String contactId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/chats/$contactId/pinned'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getPinnedMessages): $e');
    }
    return [];
  }

  // --- Starred Messages List ---
  static Future<List<Map<String, dynamic>>> getStarredMessages() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/starred'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getStarredMessages): $e');
    }
    return [];
  }

  // --- View Once ---
  static Future<bool> markViewOnce(int msgId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/$msgId/view-once'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (markViewOnce): $e');
      return false;
    }
  }

  // --- Status Views ---
  static Future<bool> recordStatusView(String statusId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/statuses/$statusId/view'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (recordStatusView): $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getStatusViews(String statusId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/statuses/$statusId/views'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('API Error (getStatusViews): $e');
    }
    return [];
  }

  // --- Call Links ---
  static Future<Map<String, dynamic>?> createCallLink({String callType = 'video', String linkName = 'GebTalk Meeting'}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calls/link'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'call_type': callType, 'link_name': linkName}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (createCallLink): $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getCallLink(String linkId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/calls/link/$linkId'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (getCallLink): $e');
    }
    return null;
  }

  // --- Storage & Data Manager ---
  static Future<Map<String, dynamic>?> getStorageSummary() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/storage/summary'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('API Error (getStorageSummary): $e');
    }
    return null;
  }

  static Future<bool> clearChatMedia(String contactId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/storage/chat/$contactId'),
        headers: _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (clearChatMedia): $e');
      return false;
    }
  }

  // --- Account 2FA and Deletion ---
  static Future<bool> setAccount2FA(bool enabled, String pin) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile/account/2fa'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'enabled': enabled, 'pin': pin}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (setAccount2FA): $e');
      return false;
    }
  }

  static Future<bool> deleteAccount() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile/account/delete'),
        headers: _authHeaders(json: true),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (deleteAccount): $e');
      return false;
    }
  }

  // --- Privacy Settings ---
  static Future<bool> updatePrivacySettings(Map<String, dynamic> settings) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile/privacy'),
        headers: _authHeaders(json: true),
        body: jsonEncode(settings),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (updatePrivacySettings): $e');
      return false;
    }
  }

  // --- Chat Wallpaper ---
  static Future<bool> setChatWallpaper(String contactId, String wallpaper) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/$contactId/wallpaper'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'wallpaper': wallpaper}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (setChatWallpaper): $e');
      return false;
    }
  }

  // --- Google Meet-Style Email Calling ---
  static Future<Map<String, dynamic>?> startEmailCall({
    required String recipientEmail,
    String? recipientName,
    String? contactId,
    String? subject,
    String callType = 'video',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calls/email/start'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'recipient_email': recipientEmail,
          'recipient_name': recipientName ?? '',
          'contact_id': contactId,
          'subject': subject ?? 'GebTalk HD Video Meeting',
          'call_type': callType,
        }),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('API Error (startEmailCall): $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getEmailMeetingInfo(String meetingId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/calls/email/meeting/$meetingId'),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('API Error (getEmailMeetingInfo): $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> joinEmailMeeting({
    required String meetingId,
    required String guestName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calls/email/meeting/$meetingId/join'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'guest_name': guestName}),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('API Error (joinEmailMeeting): $e');
      return null;
    }
  }

  static Future<bool> endEmailMeeting(String meetingId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calls/email/meeting/$meetingId/end'),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (endEmailMeeting): $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getEmailCallsHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/calls/email/history'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('API Error (getEmailCallsHistory): $e');
      return [];
    }
  }

  // --- Email Identity, OTP Verification & Missed Call Alerts ---

  static Future<Map<String, dynamic>?> sendProfileEmailOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile/email/send-otp'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'email': email}),
      );
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      debugPrint('API Error (sendProfileEmailOtp): $e');
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> verifyProfileEmailOtp(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/profile/email/verify-otp'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      debugPrint('API Error (verifyProfileEmailOtp): $e');
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> lookupCallTarget(String target) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calls/lookup-target'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'target': target}),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('API Error (lookupCallTarget): $e');
      return null;
    }
  }

  static Future<bool> notifyMissedCall({
    required String calleeEmail,
    required String callType,
    String? callbackUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calls/notify-missed'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'callee_email': calleeEmail,
          'call_type': callType,
          'callback_url': callbackUrl ?? 'http://127.0.0.1:3000/#/calls',
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (notifyMissedCall): $e');
      return false;
    }
  }

  // ========== EMAIL-FIRST UNIFIED COMMUNICATIONS API ==========

  static Future<List<DirectoryUser>> searchUsers(String query) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/search?q=${Uri.encodeComponent(query)}'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['users'] as List? ?? [];
        return list.map((u) => DirectoryUser.fromJson(Map<String, dynamic>.from(u))).toList();
      }
    } catch (e) {
      debugPrint('API Error (searchUsers): $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> sendContactRequest({
    String? targetEmail,
    String? targetId,
    String? message,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/request'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'target_email': targetEmail,
          'target_id': targetId,
          'message': message ?? 'Would love to connect on GEBTALK.',
        }),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error (sendContactRequest): $e');
    }
    return null;
  }

  static Future<List<ContactRequest>> getContactRequests() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/contacts/requests'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final incoming = data['incoming'] as List? ?? [];
        return incoming.map((r) => ContactRequest.fromJson(Map<String, dynamic>.from(r))).toList();
      }
    } catch (e) {
      debugPrint('API Error (getContactRequests): $e');
    }
    return [];
  }

  static Future<bool> respondContactRequest(int requestId, String action) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/respond'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'request_id': requestId,
          'action': action, // 'accept' or 'decline'
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (respondContactRequest): $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getEmails({String folder = 'inbox', String search = ''}) async {
    try {
      final uri = Uri.parse('$baseUrl/emails?folder=$folder&search=${Uri.encodeComponent(search)}');
      final response = await http.get(uri, headers: _authHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['emails'] as List? ?? [];
        final emails = list.map((e) => EmailMessage.fromJson(Map<String, dynamic>.from(e))).toList();
        return {
          'emails': emails,
          'unread_count': data['unread_count'] ?? 0,
          'counts': data['counts'] != null ? Map<String, dynamic>.from(data['counts']) : <String, dynamic>{},
        };
      }
    } catch (e) {
      debugPrint('API Error (getEmails): $e');
    }
    return {'emails': <EmailMessage>[], 'unread_count': 0, 'counts': {}};
  }

  static Future<Map<String, dynamic>?> getEmailDetail(String emailId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/emails/$emailId'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error (getEmailDetail): $e');
    }
    return null;
  }

  static Future<bool> sendEmailMessage({
    required String toEmail,
    required String subject,
    required String bodyText,
    String? bodyHtml,
    List<Map<String, dynamic>>? attachments,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/emails/send'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'to_email': toEmail,
          'subject': subject,
          'body_text': bodyText,
          'body_html': bodyHtml,
          'attachments': attachments ?? [],
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (sendEmailMessage): $e');
      return false;
    }
  }

  static Future<bool> toggleEmailStar(String emailId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/emails/$emailId/star'),
        headers: _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (toggleEmailStar): $e');
      return false;
    }
  }

  static Future<bool> deleteEmail(String emailId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/emails/$emailId'),
        headers: _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (deleteEmail): $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> convertEmailToChat(String emailId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/emails/convert-to-chat'),
        headers: _authHeaders(json: true),
        body: jsonEncode({'email_id': emailId}),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error (convertEmailToChat): $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> forwardChatToEmail({
    required String toEmail,
    String? contactId,
    List<int>? messageIds,
    String? subject,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/forward-to-email'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'to_email': toEmail,
          'contact_id': contactId,
          'message_ids': messageIds,
          'subject': subject ?? 'GEBTALK Chat Transcript',
        }),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('API Error (forwardChatToEmail): $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> createManagedAccount({
    required String name,
    required String email,
    required String role,
    String? password,
    String? phone,
    String? assignedStaffId,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/accounts/create'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'name': name,
          'email': email,
          'role': role,
          'password': password ?? 'password123',
          'phone': phone,
          'assigned_staff_id': assignedStaffId,
          'notes': notes,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        final err = jsonDecode(response.body);
        ErrorHandler.showError(err['error'] ?? 'Failed to create account');
      }
    } catch (e) {
      debugPrint('API Error (createManagedAccount): $e');
      ErrorHandler.showError('Network error creating account: $e');
    }
    return null;
  }

  static Future<bool> reassignCustomerContact({
    required String contactId,
    required String? assignedStaffId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/contacts/$contactId/assign'),
        headers: _authHeaders(json: true),
        body: jsonEncode({
          'assigned_staff_id': assignedStaffId,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API Error (reassignCustomerContact): $e');
      return false;
    }
  }
}




