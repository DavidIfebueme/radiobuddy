import 'package:flutter_test/flutter_test.dart';
import 'package:radiobuddy/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const RadioBuddyApp());
    expect(find.text('Radio Buddy'), findsOneWidget);
  });
}
