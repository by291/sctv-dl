import 'dart:convert';

import 'programme.dart';

const _mediaHosts = {'fscgc.scgchc.com', 'fscgc.sctv-tf.com'};
const _coverHosts = {'kscgc.sctv.com', 'kscgc.scgchc.com', 'kscgc.sctv-tf.com'};
final _titleWhitespace = RegExp(
  r'[\s\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]',
);

bool _allowedHttps(Uri? uri, Set<String> hosts) =>
    uri != null &&
    uri.scheme == 'https' &&
    hosts.contains(uri.host.toLowerCase()) &&
    uri.userInfo.isEmpty &&
    uri.port == 443;

bool isAllowedMediaUrl(String value) {
  final uri = Uri.tryParse(value);
  return _allowedHttps(uri, _mediaHosts) &&
      uri!.path.toLowerCase().endsWith('.mp4');
}

bool isAllowedCoverUrl(String value) =>
    _allowedHttps(Uri.tryParse(value), _coverHosts);

List<VideoSource> videoSources(ProgrammeContent content) {
  final result = <VideoSource>[];
  final seen = <String>{};
  for (final source in [
    if (content.video case final String url)
      VideoSource(quality: VideoQuality.standard, url: url),
    if (content.smoothVideo case final String url)
      VideoSource(quality: VideoQuality.smooth, url: url),
  ]) {
    if (isAllowedMediaUrl(source.url) && seen.add(source.url)) {
      result.add(source);
    }
  }
  return List.unmodifiable(result);
}

VideoSource? resolveVideo(ProgrammeContent content, VideoQuality quality) {
  final sources = videoSources(content);
  for (final source in sources) {
    if (source.quality == quality) return source;
  }
  return sources.firstOrNull;
}

bool isFullEpisode(String title, String programmeName, String date) {
  if (programmeName.isEmpty || date.isEmpty) return false;
  final normalized = title.replaceAll(_titleWhitespace, '');
  final broadcast = date.replaceAll('-', '.');
  return normalized == '$programmeName（$broadcast）' ||
      normalized == '$programmeName($broadcast)';
}

DateTime? publicationTime(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final value = text.trim().replaceFirst(' ', 'T');
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(value);
  if (parts == null) return null;
  final fields = [for (var i = 1; i <= 6; i++) int.parse(parts[i] ?? '0')];
  final calendar = DateTime.utc(fields[0], fields[1], fields[2]);
  if (calendar.year != fields[0] ||
      calendar.month != fields[1] ||
      calendar.day != fields[2] ||
      fields[3] > 23 ||
      fields[4] > 59 ||
      fields[5] > 59) {
    return null;
  }
  // Offset-free upstream wall times belong to Sichuan, regardless of the device zone.
  return DateTime.tryParse(parts[7] == null ? '$value+08:00' : value)?.toUtc();
}

List<ProgrammeContent> orderClips(
  List<ProgrammeContent> items, {
  bool ascending = true,
}) {
  final indexed = items.indexed.toList();
  indexed.sort((a, b) {
    final left = publicationTime(a.$2.publishedAt);
    final right = publicationTime(b.$2.publishedAt);
    if (left == null) return right == null ? a.$1.compareTo(b.$1) : 1;
    if (right == null) return -1;
    final comparison = left.compareTo(right) * (ascending ? 1 : -1);
    return comparison == 0 ? a.$1.compareTo(b.$1) : comparison;
  });
  return [for (final pair in indexed) pair.$2];
}

String publicationLabel(String? text, String broadcastDate) {
  final time = publicationTime(text)?.add(const Duration(hours: 8));
  if (time == null) return '发布时间未知';
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${time.year}-${two(time.month)}-${two(time.day)}';
  final clock = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  return date == broadcastDate ? clock : '$date $clock';
}

String downloadFilename(
  ProgrammeSelection selection,
  VideoQuality quality, {
  required String suffix,
}) {
  String sanitize(String text) => text
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  final date = sanitize(selection.broadcast.date);
  final tail = '_${quality.label}_${sanitize(suffix)}.mp4';
  final prefix = '${date}_';
  final budget = 255 - utf8.encode('$prefix$tail').length;
  if (budget < 1) throw const FormatException('Filename suffix is too long');
  final title = sanitize(selection.content.title);
  final buffer = StringBuffer();
  var bytes = 0;
  for (final rune in (title.isEmpty ? '节目' : title).runes) {
    final character = String.fromCharCode(rune);
    final size = utf8.encode(character).length;
    if (bytes + size > budget) break;
    buffer.write(character);
    bytes += size;
  }
  return '$prefix$buffer$tail';
}
