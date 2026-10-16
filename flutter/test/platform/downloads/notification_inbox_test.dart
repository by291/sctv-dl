import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/platform/downloads/notification_inbox.dart';

void main() {
  test('cold tap waits for navigation owner and is consumed once', () async {
    final inbox = NotificationInbox();
    addTearDown(inbox.dispose);
    inbox.add('cold-task');
    expect(await inbox.events.first, 'cold-task');
    final later = <String>[];
    final subscription = inbox.events.listen(later.add);
    await Future<void>.delayed(Duration.zero);
    expect(later, isEmpty);
    inbox.add('fresh-task');
    await Future<void>.delayed(Duration.zero);
    expect(later, ['fresh-task']);
    await subscription.cancel();
  });

  test('only newest pending navigation intent is retained', () async {
    final inbox = NotificationInbox();
    addTearDown(inbox.dispose);
    inbox.add('old-task');
    inbox.add('latest-task');
    expect(await inbox.events.first, 'latest-task');
  });
}
