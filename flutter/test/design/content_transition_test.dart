import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/content_transition.dart';

Future<List<int>> expectCovered(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rgba = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  });
  // The three fixture surfaces are pure RGB primaries. Any exposure of the
  // white backing increases the channel sum above their opaque colour mixture.
  // Allow integer alpha rounding across three composited layers.
  final centre = (10 * 20 + 10) * 4;
  expect(rgba![centre] + rgba[centre + 1] + rgba[centre + 2], closeTo(255, 4));
  expect(rgba[centre + 3], 255);
  return rgba.sublist(centre, centre + 3);
}

void main() {
  testWidgets(
    'directional branches keep their positions when a switch is interrupted',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: selected,
            builder: (context, index, _) => RetainedFadeStack(
              index: index,
              travelDistance: 20,
              children: const [
                Center(child: Text('Page A')),
                Center(child: Text('Page B')),
                Center(child: Text('Page C')),
              ],
            ),
          ),
        ),
      );
      final settled = tester.getTopLeft(find.text('Page A'));
      selected.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final departing = tester.getTopLeft(find.text('Page A'));
      final arriving = tester.getTopLeft(find.text('Page B'));
      expect(departing.dx, lessThan(settled.dx));
      expect(arriving.dx, greaterThan(settled.dx));
      expect(departing.dy, settled.dy);
      selected.value = 2;
      await tester.pump();
      expect(tester.getTopLeft(find.text('Page A')), departing);
      expect(tester.getTopLeft(find.text('Page B')), arriving);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Page C')), settled);
      selected.value = 0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(find.text('Page A')).dx, lessThan(settled.dx));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Page A')), settled);
    },
  );

  testWidgets(
    'rapid branch switches retain an opaque surface at every sampled frame',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 20,
                height: 20,
                child: ValueListenableBuilder<int>(
                  valueListenable: selected,
                  builder: (context, index, _) => RetainedFadeStack(
                    index: index,
                    children: const [
                      ColoredBox(color: Color(0xFFFF0000)),
                      ColoredBox(color: Color(0xFF0000FF)),
                      ColoredBox(color: Color(0xFF00FF00)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final target in [1, 2, 0, 2]) {
        selected.value = target;
        await tester.pump();
        await expectCovered(tester, boundary);
        await tester.pump(const Duration(milliseconds: 60));
        await expectCovered(tester, boundary);
      }
      await tester.pumpAndSettle();
      await expectCovered(tester, boundary);
    },
  );

  testWidgets(
    'rapid content replacements preserve their current visible blend',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      final boundary = GlobalKey();
      const colours = [Color(0xFFFF0000), Color(0xFF0000FF), Color(0xFF00FF00)];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: ValueListenableBuilder<int>(
                valueListenable: selected,
                builder: (context, index, _) => ContentTransition(
                  background: Colors.white,
                  child: SizedBox(
                    key: ValueKey(index),
                    width: 20,
                    height: 20,
                    child: ColoredBox(color: colours[index]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final target in [1, 2, 0, 1]) {
        final before = await expectCovered(tester, boundary);
        selected.value = target;
        await tester.pump();
        final after = await expectCovered(tester, boundary);
        for (var channel = 0; channel < 3; channel++) {
          expect(after[channel], closeTo(before[channel], 2));
        }
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
      await expectCovered(tester, boundary);
    },
  );

  testWidgets(
    'only the selected retained child is interactive and motion can be disabled',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      final created = <int>[];
      final tapped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ValueListenableBuilder<int>(
              valueListenable: selected,
              builder: (context, index, _) => RetainedFadeStack(
                index: index,
                children: [
                  for (var i = 0; i < 3; i++)
                    _Pane(id: i, created: created, tapped: tapped),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final target in [1, 2, 0]) {
        selected.value = target;
        await tester.pump();
        expect(find.byType(TextButton), findsOneWidget);
        expect(find.byType(TextButton).hitTestable(), findsOneWidget);
        await tester.tap(find.text('Page $target'));
      }
      expect(created, unorderedEquals([0, 1, 2]));
      expect(tapped, [1, 2, 0]);
    },
  );
}

class _Pane extends StatefulWidget {
  const _Pane({required this.id, required this.created, required this.tapped});
  final int id;
  final List<int> created;
  final List<int> tapped;
  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  @override
  void initState() {
    super.initState();
    widget.created.add(widget.id);
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => widget.tapped.add(widget.id),
      child: Text('Page ${widget.id}'),
    ),
  );
}
