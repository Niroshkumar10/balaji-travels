import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redtaxi/app.dart';
import 'package:redtaxi/core/auth/session.dart';
import 'package:redtaxi/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots to a MaterialApp', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = await Session.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(session)],
        child: const RedTaxiApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
