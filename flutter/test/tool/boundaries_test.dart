import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_boundaries.dart';

void main() {
  late Directory fixture;

  setUp(
    () => fixture = Directory.systemTemp.createTempSync('flutter-boundaries-'),
  );
  tearDown(() => fixture.deleteSync(recursive: true));

  void source(String path, String contents) {
    final file = File('${fixture.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  test('permits feature contracts and composition while ignoring commented imports', () {
    source(
      'features/player/page.dart',
      "import '../../domain/player.dart';\n// import '../../data/player.dart';",
    );
    source('app/bootstrap.dart', "import '../data/player.dart';");
    expect(checkBoundaries(fixture), isEmpty);
  });

  test('rejects conditional native adapters, exports and sibling features', () {
    source(
      'features/player/page.dart',
      "import 'stub.dart' if (dart.library.io) '../../platform/player.dart';\nexport '../downloads/page.dart';",
    );
    source('domain/model.dart', "import 'package:flutter/widgets.dart';");
    source(
      'design/common.dart',
      "export 'package:sctv_dl_mobile/features/player/page.dart';",
    );
    expect(checkBoundaries(fixture), hasLength(4));
  });

  test('rejects internal references that escape the owned library tree', () {
    source('domain/model.dart', "import '../../external.dart';");
    expect(checkBoundaries(fixture).single, contains('outside lib'));
  });
}
