import '../programmes/programme.dart';

enum AppThemeMode { system, light, dark }

class Preferences {
  const Preferences({
    this.theme = AppThemeMode.system,
    this.quality = VideoQuality.standard,
    this.wifiOnly = false,
    this.dynamicColour = false,
  });

  final AppThemeMode theme;
  final VideoQuality quality;
  final bool wifiOnly;
  final bool dynamicColour;

  Preferences copyWith({
    AppThemeMode? theme,
    VideoQuality? quality,
    bool? wifiOnly,
    bool? dynamicColour,
  }) => Preferences(
    theme: theme ?? this.theme,
    quality: quality ?? this.quality,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    dynamicColour: dynamicColour ?? this.dynamicColour,
  );
}
