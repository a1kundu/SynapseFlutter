import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:synapse/main.dart';

void main() {
  testWidgets('App renders Synapse title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Synapse'), findsOneWidget);
  });
}
