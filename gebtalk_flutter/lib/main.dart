import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/splash_screen.dart';
import 'screens/guest_meet_screen.dart';
import 'theme/colors.dart';
import 'theme/titan_theme.dart';
import 'utils/error_handler.dart';

import 'services/webrtc_service.dart';
import 'services/api_service.dart';
import 'widgets/call_overlay.dart';
import 'utils/call_audio_tone_player.dart';
import 'utils/call_audio_manager.dart';
import 'dart:ui';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  CallAudioTonePlayer.unlockAudio();
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('FLUTTER ERROR DETECTED: ${details.exception}');
    debugPrint(details.stack?.toString());
    try {
      ApiService.logDebug('FLUTTER_ERROR: ${details.exception}\n${details.stack}');
    } catch (_) {}
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PLATFORM DISPATCHER ERROR: $error');
    debugPrint(stack.toString());
    try {
      ApiService.logDebug('PLATFORM_ERROR: $error\n$stack');
    } catch (_) {}
    return true;
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF7F1D1D),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'RENDER EXCEPTION DETECTED',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                details.exception.toString(),
                style: const TextStyle(color: Color(0xFFFDE047), fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'STACK TRACE:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SelectableText(
                details.stack?.toString() ?? 'No stack trace available',
                style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    );
  };
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AppState()),
        ChangeNotifierProvider(create: (context) => WebRtcService()),
      ],
      child: const GebTalkApp(),
    ),
  );
}


class GebTalkApp extends StatelessWidget {
  const GebTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GEBTALK',
      scaffoldMessengerKey: ErrorHandler.scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: TitanTheme.dark,
      builder: (context, child) {
        ApiService.logDebug('MaterialApp builder: childNull=${child == null}');
        final double width = MediaQuery.of(context).size.width;
        final bool isMobileDevice = width < 600;

        final Widget wrappedChild = Stack(
          children: [
            if (child != null)
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) {
                  CallAudioManager.initializeAudio();
                },
                child: child,
              ),
            const CallOverlay(),
          ],
        );

        Widget body;
        if (isMobileDevice) {
          body = Scaffold(
            backgroundColor: AppColors.background,
            body: wrappedChild,
          );
        } else {
          body = Scaffold(
            backgroundColor: AppColors.deepSpaceBlack,
            body: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                width: double.infinity,
                height: double.infinity,
                constraints: const BoxConstraints(
                  maxWidth: 460,
                  maxHeight: 860,
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(36.0),
                  boxShadow: [
                    // Primary holographic glow
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 60,
                      spreadRadius: 4,
                      offset: const Offset(0, 8),
                    ),
                    // Purple accent glow
                    BoxShadow(
                      color: AppColors.nebulaPurple.withValues(alpha: 0.08),
                      blurRadius: 50,
                      spreadRadius: 0,
                      offset: const Offset(-10, 0),
                    ),
                    // Quantum violet accent
                    BoxShadow(
                      color: AppColors.quantumViolet.withValues(alpha: 0.04),
                      blurRadius: 40,
                      spreadRadius: 0,
                      offset: const Offset(10, 4),
                    ),
                    // Deep shadow for depth
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 40,
                      spreadRadius: 0,
                      offset: const Offset(0, 16),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                ),
                child: wrappedChild,
              ),
            ),
          );
        }

        return body;
      },
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');
        if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'meet') {
          final meetingId = uri.pathSegments.length >= 2
              ? uri.pathSegments[1]
              : (uri.queryParameters['id'] ?? '');
          if (meetingId.isNotEmpty) {
            return MaterialPageRoute(
              builder: (_) => GuestMeetScreen(meetingId: meetingId),
            );
          }
        }
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      },
      home: const SplashScreen(),
    );
  }
}
