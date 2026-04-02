import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/views/home_view.dart';

void main() {
  testWidgets('HomeView shows title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeView()),
    );
    expect(find.text('Quiz Admin'), findsOneWidget);
  });
}
