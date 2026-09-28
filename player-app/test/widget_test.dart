import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:player_app/main.dart';

void main() {
  testWidgets('Splash screen smoke test', (WidgetTester tester) async {
    // Unit-test environment: no platform channels, no network fonts.
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const AthletePOVPlayerApp());

    // Verify splash screen content starts up.
    expect(find.text("Athlete's POV"), findsOneWidget);

    // Let the splash auth delay elapse and settle navigation.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
