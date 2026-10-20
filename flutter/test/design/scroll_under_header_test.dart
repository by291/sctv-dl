import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/scroll_under_header.dart';

void main() {
  testWidgets('Header stays blurred while either pane is scrolled', (
    tester,
  ) async {
    final left = ScrollController();
    final right = ScrollController();
    addTearDown(left.dispose);
    addTearDown(right.dispose);

    await tester.pumpWidget(_panes(left: left, right: right));
    await tester.pumpAndSettle();
    expect(_blurEnabled(tester), isFalse);

    right.jumpTo(120);
    await tester.pumpAndSettle();
    expect(_blurEnabled(tester), isTrue);

    left.jumpTo(80);
    await tester.pumpAndSettle();
    left.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_blurEnabled(tester), isTrue);

    right.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_blurEnabled(tester), isFalse);
  });

  testWidgets('Removing a scrolled pane clears its header blur state', (
    tester,
  ) async {
    final left = ScrollController();
    final right = ScrollController();
    addTearDown(left.dispose);
    addTearDown(right.dispose);

    await tester.pumpWidget(_panes(left: left, right: right));
    await tester.pumpAndSettle();
    right.jumpTo(120);
    await tester.pumpAndSettle();
    expect(_blurEnabled(tester), isTrue);

    await tester.pumpWidget(_panes(left: left));
    await tester.pumpAndSettle();
    expect(_blurEnabled(tester), isFalse);
  });
}

bool _blurEnabled(WidgetTester tester) =>
    tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled;

Widget _panes({required ScrollController left, ScrollController? right}) =>
    MaterialApp(
      home: Scaffold(
        body: ScrollUnderHeader(
          height: 56,
          color: Colors.white,
          child: Row(
            children: [
              Expanded(child: _list('left', left)),
              if (right != null) Expanded(child: _list('right', right)),
            ],
          ),
        ),
      ),
    );

Widget _list(String key, ScrollController controller) => ListView.builder(
  key: ValueKey(key),
  controller: controller,
  itemCount: 50,
  itemExtent: 60,
  itemBuilder: (context, index) => Text('Item $index'),
);
