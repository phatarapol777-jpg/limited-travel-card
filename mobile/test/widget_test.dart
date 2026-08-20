import 'package:flutter_test/flutter_test.dart';

import 'package:travel_card/main.dart';

void main() {
  testWidgets('App boots to login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const TravelCardApp());
    expect(find.text('Limited Travel Card'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });
}
