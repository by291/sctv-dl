import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';

/// Validates untrusted upstream values before constructing domain records.
abstract final class ProgrammeParser {
  static String id(Object? value) {
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) return value;
    if (value is num &&
        value.isFinite &&
        value >= 0 &&
        value <= 9007199254740991 &&
        value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    throw const FormatException('Invalid or unsafe programme ID');
  }

  static List<Programme> programmes(Object? value) => List.unmodifiable(
    _list(_map(value)['records']).map((raw) {
      final row = _map(raw);
      return Programme(
        id: id(row['id']),
        name: row['name'] is String ? row['name'] as String : '未命名栏目',
        cover: _cover(row['cover']),
      );
    }),
  );

  static List<BroadcastDate> dates(Object? value) {
    final dates = <String, BroadcastDate>{};
    for (final raw in _list(value)) {
      final row = _map(raw);
      final date = _calendarDate(row['date']);
      // A later service record supersedes an earlier record for the same day.
      dates[date] = BroadcastDate(id: id(row['id']), date: date);
    }
    return List.unmodifiable(
      dates.values.toList()..sort((a, b) => b.date.compareTo(a.date)),
    );
  }

  static List<ProgrammeContent> contents(Object? value) => List.unmodifiable(
    _list(value).map((raw) {
      final row = _map(raw);
      return ProgrammeContent(
        id: id(row['id']),
        title: row['title'] is String ? row['title'] as String : '未命名节目',
        cover: _cover(row['cover']),
        video: _url(row['video'], 'https://fscgc.scgchc.com/'),
        smoothVideo: _url(row['videoStandard'], 'https://fscgc.scgchc.com/'),
        publishedAt: row['pubTime'] is String ? row['pubTime'] as String : null,
      );
    }),
  );

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Expected an object');
    }
    return value;
  }

  static List<Object?> _list(Object? value) {
    if (value is! List) throw const FormatException('Expected a list');
    return value;
  }

  static String _calendarDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid broadcast date');
    }
    final fields = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(fields[0], fields[1], fields[2]);
    if (date.year != fields[0] ||
        date.month != fields[1] ||
        date.day != fields[2]) {
      throw const FormatException('Invalid broadcast date');
    }
    return value;
  }

  static String? _cover(Object? value) {
    final url = _url(value, 'https://kscgc.sctv.com/');
    return url != null && isAllowedCoverUrl(url) ? url : null;
  }

  static String? _url(Object? value, String base) {
    if (value is! String) return null;
    // Dart trim includes U+0085, while ECMAScript trim includes BOM instead.
    final trimmed = value.replaceAll(
      RegExp(
        r'^[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+$',
      ),
      '',
    );
    if (trimmed.isEmpty) return null;

    try {
      final url = Uri.parse(base).resolve(
        trimmed.replaceAll(RegExp(r'[\t\r\n]'), '').replaceAll('\\', '/'),
      );
      return url.scheme == 'https' || url.scheme == 'http'
          ? url.toString()
          : null;
    } on FormatException {
      return null;
    }
  }
}
