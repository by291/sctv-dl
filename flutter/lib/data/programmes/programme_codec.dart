import '../../domain/programmes/programme.dart';
import 'programme_parser.dart';

Map<String, Object?> encodeProgramme(Programme row) => {
  'id': row.id,
  'name': row.name,
  'cover': row.cover,
};

Map<String, Object?> encodeBroadcast(BroadcastDate row) => {
  'id': row.id,
  'date': row.date,
};

Map<String, Object?> encodeContent(ProgrammeContent row) => {
  'id': row.id,
  'title': row.title,
  'cover': row.cover,
  'video': row.video,
  'videoStandard': row.smoothVideo,
  'pubTime': row.publishedAt,
};

Map<String, Object?> encodeSelection(ProgrammeSelection selection) => {
  'programme': encodeProgramme(selection.programme),
  'broadcast': encodeBroadcast(selection.broadcast),
  'content': encodeContent(selection.content),
};

ProgrammeSelection decodeSelection(Map<String, Object?> row) =>
    ProgrammeSelection(
      programme: ProgrammeParser.programmes({
        'records': [row['programme']],
      }).single,
      broadcast: ProgrammeParser.dates([row['broadcast']]).single,
      content: ProgrammeParser.contents([row['content']]).single,
    );
