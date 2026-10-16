import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/programmes/programme_parser.dart';

void main() {
  test(
    'content parsing matches shared URL and optional-field fixtures',
    () async {
      final fixtures = jsonDecode(
        await File('../shared/fixtures/programmes.json').readAsString(),
      ) as List;

      for (final fixture in fixtures.cast<Map<String, Object?>>()) {
        final actual = ProgrammeParser.contents(fixture['raw']);
        expect(
          actual
              .map(
                (row) => {
                  'id': row.id,
                  'title': row.title,
                  'cover': row.cover,
                  'video': row.video,
                  'smoothVideo': row.smoothVideo,
                  'publishedAt': row.publishedAt,
                },
              )
              .toList(),
          fixture['expected'],
          reason: fixture['name'] as String,
        );
      }
    },
  );

  test(
    'date parsing rejects impossible dates and keeps the last calendar record',
    () {
      final dates = ProgrammeParser.dates([
        {'id': 1, 'date': '2024-02-29'},
        {'id': 2, 'date': '2025-01-01'},
        {'id': 3, 'date': '2024-02-29'},
      ]);

      expect(dates.map((date) => date.id).toList(), ['2', '3']);
      for (final date in [
        '2023-02-29',
        '2024-04-31',
        '2024-13-01',
        '2024-1-01',
      ]) {
        expect(
          () => ProgrammeParser.dates([
            {'id': 1, 'date': date},
          ]),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'unsafe numeric IDs and malformed payloads fail before entering cache',
    () {
      for (final id in [9007199254740992, -1, 1.5, true, 'x', '']) {
        expect(
          () => ProgrammeParser.programmes({
            'records': [
              {'id': id, 'name': 'News'},
            ],
          }),
          throwsFormatException,
        );
      }
      expect(
        ProgrammeParser.programmes({
          'records': [
            {'id': '9007199254740992'},
          ],
        }).single.id,
        '9007199254740992',
      );
      expect(
        () => ProgrammeParser.contents({'records': []}),
        throwsFormatException,
      );
    },
  );
}
