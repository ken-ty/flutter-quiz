import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/views/login_view.dart';

void main() {
  testWidgets('LoginView shows title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginView()),
    );
    expect(find.text('Client Login'), findsOneWidget);
  });
}
