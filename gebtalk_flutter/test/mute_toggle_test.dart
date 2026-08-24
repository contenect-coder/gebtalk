import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebtalk_flutter/services/webrtc_service.dart';
import 'package:gebtalk_flutter/widgets/call_overlay.dart';
import 'package:provider/provider.dart';

void main() {
  test('WebRtcService toggleMute state and notifications', () {
    final service = WebRtcService();
    expect(service.isMuted, false);

    int notifications = 0;
    service.addListener(() {
      notifications++;
    });

    // 1. Toggle mute ON
    service.toggleMute();
    expect(service.isMuted, true);
    expect(notifications, 1);

    // 2. Toggle mute OFF (Unmute)
    service.toggleMute();
    expect(service.isMuted, false);
    expect(notifications, 2);
  });

  testWidgets('CallOverlay renders Mute and toggles on tap', (WidgetTester tester) async {
    final service = WebRtcService();
    service.currentUserId = 'test_caller';
    service.currentPeerName = 'Franklin Victor';
    service.callState = 'calling'; // Outgoing call
    service.isCaller = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<WebRtcService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                CallOverlay(),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    // Verify 'Mute' label exists
    expect(find.text('Mute'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

    // Tap Mute button
    await tester.tap(find.text('Mute'));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify it switched to 'Unmute' and mic_off icon
    expect(service.isMuted, true);
    expect(find.text('Unmute'), findsOneWidget);
    expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);

    // Tap Unmute button to unmute
    await tester.tap(find.text('Unmute'));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify it switched back to 'Mute'
    expect(service.isMuted, false);
    expect(find.text('Mute'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });
}
