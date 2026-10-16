import '../programmes/programme_repository.dart';

abstract interface class DownloadMediaProbe {
  Future<void> validate(String url, {required RequestScope scope});
  void dispose();
}
