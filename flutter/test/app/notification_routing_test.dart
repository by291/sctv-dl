import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/app/app.dart';
import 'package:sctv_dl_mobile/features/downloads/downloads_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

import '../support/route_harness.dart';

void main() {
  testWidgets('a download notification tap opens downloads in SctvApp', (
    tester,
  ) async {
    final taps = StreamController<String>.broadcast(sync: true);
    final harness = RouteHarness(notificationTaps: taps.stream);
    try {
      await tester.pumpWidget(SctvApp(services: harness.services));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(DownloadsPage), findsNothing);

      taps.add('download-from-notification');
      await tester.pumpAndSettle();

      expect(find.byType(DownloadsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.services.dispose();
      await taps.close();
      await harness.user.close();
    }
  });
}
