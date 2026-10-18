enum VideoQuality {
  standard('标准'),
  smooth('流畅');

  const VideoQuality(this.label);

  final String label;
}

class Programme {
  const Programme({required this.id, required this.name, this.cover});

  final String id;
  final String name;
  final String? cover;
}

class BroadcastDate {
  const BroadcastDate({required this.id, required this.date});

  final String id;
  final String date;
}

class ProgrammeContent {
  const ProgrammeContent({
    required this.id,
    required this.title,
    this.cover,
    this.video,
    this.smoothVideo,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String? cover;
  final String? video;
  final String? smoothVideo;
  final String? publishedAt;
}

class ContentRef {
  const ContentRef({
    required this.programmeId,
    required this.dateId,
    required this.contentId,
  });

  final String programmeId;
  final String dateId;
  final String contentId;

  String get key => '$programmeId/$dateId/$contentId';

  @override
  bool operator ==(Object other) => other is ContentRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class ProgrammeSelection {
  const ProgrammeSelection({
    required this.programme,
    required this.broadcast,
    required this.content,
  });

  final Programme programme;
  final BroadcastDate broadcast;
  final ProgrammeContent content;

  ContentRef get ref => ContentRef(
    programmeId: programme.id,
    dateId: broadcast.id,
    contentId: content.id,
  );
}

class VideoSource {
  const VideoSource({required this.quality, required this.url});

  final VideoQuality quality;
  final String url;
}
