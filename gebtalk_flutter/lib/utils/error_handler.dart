import 'package:flutter/material.dart';
import '../screens/settings/server_settings_screen.dart';

class ErrorHandler {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static void showError(String message) {
    final isConnectionError = message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('Network Error') ||
        message.contains('Timeout') ||
        message.contains('timed out') ||
        message.contains('Connection failed') ||
        message.contains('Future not completed') ||
        message.contains('SERVER OFFLINE');

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontFamily: 'Product Sans')),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: isConnectionError ? const Duration(seconds: 8) : const Duration(seconds: 4),
        action: isConnectionError
            ? SnackBarAction(
                label: 'Change Server',
                textColor: Colors.amberAccent,
                onPressed: () {
                  final nav = navigatorKey.currentState;
                  if (nav != null) {
                    nav.push(MaterialPageRoute(builder: (_) => const ServerSettingsScreen()));
                  }
                },
              )
            : null,
      ),
    );
  }

  static void showSuccess(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontFamily: 'Product Sans')),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
