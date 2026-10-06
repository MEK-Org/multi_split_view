// Acceptance tests for the MEK-Org fork behaviour carried onto 3.6.2:
// pixel minima, collapse/reopen, neighbour-only resizing and resetSizes.
//
// CompatViewer is a sidebar | list | detail [| debug] split configured as the
// fork's main consumer uses it (sidebar size/min 200; list and detail flex
// 1/2 with a 400px minimum; list collapses below 200px; debug panel adds a
// third flex area with a 200px minimum; controller recreated when debug is
// toggled; sidebar filter resets the sizes). Fork API mapping:
//   Area.key            -> Area.id
//   weight + flex: true -> flex
//   minimalSize         -> min (size area) / minPixels (flex area)
//   children            -> controller.areas synced to visible ids + builder
//   resetSizes()        -> resetSizes()
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_split_view/multi_split_view.dart';

import 'compat_panels.dart';

class _Layout {
  _Layout({required bool debug}) {
    final double flex = debug ? 1 / 3 : 1 / 2;
    all = {
      'sidebar': Area(id: 'sidebar', size: 200, min: 200),
      'list': Area(id: 'list', flex: flex, minPixels: 400, collapseSize: 200),
      'detail': Area(id: 'detail', flex: flex, minPixels: 400),
      if (debug) 'debug': Area(id: 'debug', flex: 1 / 3, minPixels: 200),
    };
  }

  late final Map<String, Area> all;
  final MultiSplitViewController controller = MultiSplitViewController();

  void sync(List<String> ids) {
    final List<dynamic> current = controller.areas.map((a) => a.id).toList();
    if (current.join(',') != ids.join(',')) {
      controller.areas = [for (final String id in ids) all[id]!];
    }
  }
}

class CompatViewer extends StatefulWidget {
  const CompatViewer({Key? key}) : super(key: key);

  @override
  State<CompatViewer> createState() => CompatViewerState();
}

class CompatViewerState extends State<CompatViewer> {
  bool _debug = false;
  bool _focused = false;
  _Layout _layout = _Layout(debug: false);

  void setDebug(bool value) => setState(() {
        _debug = value;
        _layout = _Layout(debug: value);
      });

  void setFocused(bool value) => setState(() => _focused = value);

  @override
  Widget build(BuildContext context) {
    final Map<String, Widget> children = {};
    final double width = MediaQuery.of(context).size.width;
    final bool singleScreen = width < 600;
    final bool showHamburger = width < 1000;
    if (!showHamburger) {
      children['sidebar'] = KeyedSubtree(
          key: const ValueKey('sidebar'),
          child: SidebarPanel(
              onSwitchFilter: () => _layout.controller.resetSizes()));
    }
    if (!singleScreen || !_focused) {
      children['list'] =
          const KeyedSubtree(key: ValueKey('list'), child: ListPanel());
    }
    if (_focused) {
      children['detail'] =
          const KeyedSubtree(key: ValueKey('detail'), child: DetailPanel());
    }
    if (!singleScreen && _debug) {
      children['debug'] = const DebugPanel(key: ValueKey('debug'));
    }
    if (children.isEmpty) {
      return Container();
    }
    if (children.length == 1) {
      return children.values.single;
    }
    _layout.sync(children.keys.toList());
    return MultiSplitViewTheme(
        data: MultiSplitViewThemeData(dividerThickness: dividerThickness),
        child: MultiSplitView(
            controller: _layout.controller,
            flexResizePolicy: FlexResizePolicy.neighbourOnly,
            builder: (context, area) => children[area.id]!));
  }
}

Future<CompatViewerState> pumpViewer(WidgetTester tester, double width,
    {bool focused = true}) async {
  inits.clear();
  addTearDown(tester.view.reset);
  await setWindow(tester, width);
  final GlobalKey<CompatViewerState> key = GlobalKey();
  await tester
      .pumpWidget(MaterialApp(home: Scaffold(body: CompatViewer(key: key))));
  await tester.pumpAndSettle();
  key.currentState!.setFocused(focused);
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// Records the widths of [ids] at each drag stop.
class _Stops {
  _Stops(this.tester, this.ids);

  final WidgetTester tester;
  final List<String> ids;
  final Map<double, Map<String, double?>> widths = {};

  void record(double stop) =>
      widths[stop] = {for (final String id in ids) id: widthOf(tester, id)};

  double? at(double stop, String id) => widths[stop]![id];
}

void main() {
  group('Compat', () {
    testWidgets('wide initial layout', (tester) async {
      await pumpViewer(tester, 1400);
      // 1400 - 2 dividers = 1384; minus sidebar 200 = 1184 for flex
      expectWidth(tester, 'sidebar', 200);
      expectWidth(tester, 'list', 592);
      expectWidth(tester, 'detail', 592);
    });

    testWidgets('wide unfocused keeps the sidebar size', (tester) async {
      await pumpViewer(tester, 1400, focused: false);
      expectWidth(tester, 'sidebar', 200);
      expect(widthOf(tester, 'detail'), isNull);
    });

    testWidgets('drag to pixel min, collapse, reopen, reset', (tester) async {
      await pumpViewer(tester, 1400);
      final _Stops collapse = _Stops(tester, ['list', 'detail']);
      await dragThrough(tester, dividerAfter(tester, 'list'),
          [-100, -250, -450], collapse.record);
      expect(collapse.at(-100, 'list'), closeTo(492, 1.5));
      expect(collapse.at(-250, 'list'), closeTo(400, 1.5),
          reason: '342 clamps to the 400px minimum');
      expect(collapse.at(-450, 'list'), closeTo(0, 1.5),
          reason: '142 is below the 200px collapse size');
      expectWidth(tester, 'list', 0, reason: 'collapsed after release');
      expectWidth(tester, 'detail', 1184);

      final _Stops reopen = _Stops(tester, ['list', 'detail']);
      await dragThrough(
          tester, dividerAfter(tester, 'list'), [150, 300, 600], reopen.record);
      expect(reopen.at(150, 'list'), closeTo(0, 1.5),
          reason: 'stays collapsed below the collapse size');
      expect(reopen.at(300, 'list'), closeTo(400, 1.5),
          reason: 'snaps to the pixel minimum');
      expect(reopen.at(600, 'list'), closeTo(600, 1.5),
          reason: 'follows the pointer');
      expect(reopen.at(600, 'detail'), closeTo(584, 1.5));

      await tester.tap(find.byKey(const ValueKey('filter')));
      await tester.pumpAndSettle();
      expectWidth(tester, 'sidebar', 200);
      expectWidth(tester, 'list', 592);
      expectWidth(tester, 'detail', 592);
    });

    testWidgets('detail honours its pixel min', (tester) async {
      await pumpViewer(tester, 1400);
      final _Stops stops = _Stops(tester, ['list', 'detail']);
      await dragThrough(
          tester, dividerAfter(tester, 'list'), [100, 300], stops.record);
      expect(stops.at(100, 'detail'), closeTo(492, 1.5));
      expect(stops.at(300, 'detail'), closeTo(400, 1.5));
      expect(stops.at(300, 'list'), closeTo(784, 1.5));
    });

    testWidgets(
        'window resize keeps the sidebar and does not enforce '
        'pixel minima by layout', (tester) async {
      await pumpViewer(tester, 1400);
      await setWindow(tester, 1200);
      expectWidth(tester, 'sidebar', 200);
      expectWidth(tester, 'list', 492);
      expectWidth(tester, 'detail', 492);
      await setWindow(tester, 1000);
      expectWidth(tester, 'sidebar', 200);
      expectWidth(tester, 'list', 392);
      expectWidth(tester, 'detail', 392);
      await setWindow(tester, 1400);
      expectWidth(tester, 'sidebar', 200);
      expectWidth(tester, 'list', 592);
      expectWidth(tester, 'detail', 592);
    });

    testWidgets('sidebar drag resizes only its neighbour', (tester) async {
      await pumpViewer(tester, 1400);
      final _Stops stops = _Stops(tester, ['sidebar', 'list', 'detail']);
      await dragThrough(tester, dividerAfter(tester, 'sidebar'),
          [100, -50, -200], stops.record);
      expect(stops.at(100, 'sidebar'), closeTo(300, 1.5));
      expect(stops.at(100, 'list'), closeTo(492, 1.5));
      expect(stops.at(100, 'detail'), closeTo(592, 1.5));
      expect(stops.at(-200, 'sidebar'), closeTo(200, 1.5),
          reason: 'sidebar min 200');
      expect(stops.at(-200, 'list'), closeTo(592, 1.5));
      expect(stops.at(-200, 'detail'), closeTo(592, 1.5));
    });

    testWidgets('debug insert/remove keeps keyed identity, focus and scroll',
        (tester) async {
      final CompatViewerState viewer = await pumpViewer(tester, 1400);
      await tester.tap(find.byKey(const ValueKey('detail-field')));
      await tester.pumpAndSettle();
      listScroll.jumpTo(500);
      await tester.pumpAndSettle();
      final Map<String, int> before = Map.of(inits);

      viewer.setDebug(true);
      await tester.pumpAndSettle();
      expect(widthOf(tester, 'debug'), isNotNull);
      expect(inits, before, reason: 'no remount on insert');
      expect(detailFocus.hasFocus, isTrue);
      expect(listScroll.offset, 500);
      // 1400 - 3 dividers = 1376; minus sidebar 200 = 1176 / 3 = 392
      expectWidth(tester, 'sidebar', 200);
      expectWidth(tester, 'list', 392);
      expectWidth(tester, 'detail', 392);
      expectWidth(tester, 'debug', 392);

      viewer.setDebug(false);
      await tester.pumpAndSettle();
      expect(widthOf(tester, 'debug'), isNull);
      expect(inits, before, reason: 'no remount on remove');
      expect(detailFocus.hasFocus, isTrue);
      expect(listScroll.offset, 500);
      expectWidth(tester, 'list', 592);
      expectWidth(tester, 'detail', 592);
    });

    testWidgets('debug toggle after a drag starts from the configured sizes',
        (tester) async {
      final CompatViewerState viewer = await pumpViewer(tester, 1400);
      await dragThrough(tester, dividerAfter(tester, 'list'), [-100], (_) {});
      expectWidth(tester, 'list', 492);
      viewer.setDebug(true);
      await tester.pumpAndSettle();
      expectWidth(tester, 'list', 392);
      expectWidth(tester, 'detail', 392);
      viewer.setDebug(false);
      await tester.pumpAndSettle();
      expectWidth(tester, 'list', 592);
      expectWidth(tester, 'detail', 592);
    });

    testWidgets('mid 800 splits list and detail without sidebar',
        (tester) async {
      final CompatViewerState viewer = await pumpViewer(tester, 800);
      expect(widthOf(tester, 'sidebar'), isNull);
      // 800 - 8 = 792 / 2 = 396
      expectWidth(tester, 'list', 396);
      expectWidth(tester, 'detail', 396);
      viewer.setFocused(false);
      await tester.pumpAndSettle();
      expectWidth(tester, 'list', 800);
    });

    testWidgets('narrow 500 shows a single screen', (tester) async {
      final CompatViewerState viewer = await pumpViewer(tester, 500);
      expect(widthOf(tester, 'list'), isNull);
      expectWidth(tester, 'detail', 500);
      viewer.setFocused(false);
      await tester.pumpAndSettle();
      expectWidth(tester, 'list', 500);
    });

    testWidgets('wide -> narrow -> mid -> wide restores the layout',
        (tester) async {
      await pumpViewer(tester, 1400);
      await setWindow(tester, 500);
      await setWindow(tester, 800);
      await setWindow(tester, 1400);
      expectWidth(tester, 'sidebar', 200);
      expectWidth(tester, 'list', 592);
      expectWidth(tester, 'detail', 592);
    });

    testWidgets('pixel min applies on the first frame of a drag',
        (tester) async {
      await pumpViewer(tester, 1400);
      final TestGesture gesture =
          await tester.startGesture(Offset(dividerAfter(tester, 'list'), 300));
      await tester.pump();
      // cross the touch slop, then one large move proposing list 242
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await tester.pump();
      await gesture.moveBy(const Offset(-330, 0));
      await tester.pump();
      expectWidth(tester, 'list', 400, reason: 'first frame');
      await tester.pump();
      expectWidth(tester, 'list', 400, reason: 'second frame');
      await tester.pumpAndSettle();
      expectWidth(tester, 'list', 400, reason: 'settled');
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('Defaults', () {
    Widget split(MultiSplitViewController controller,
            {FlexResizePolicy policy = FlexResizePolicy.proportional}) =>
        MaterialApp(
            home: Scaffold(
                body: MultiSplitViewTheme(
                    data: MultiSplitViewThemeData(
                        dividerThickness: dividerThickness),
                    child: MultiSplitView(
                        controller: controller,
                        flexResizePolicy: policy,
                        builder: (context, area) => SizedBox.expand(
                            key: ValueKey('${area.id}-content'))))));

    List<Area> plainAreas() => [
          Area(id: 'sidebar', size: 200, min: 200),
          Area(id: 'list', flex: 1 / 2),
          Area(id: 'detail', flex: 1 / 2),
        ];

    testWidgets('size|flex divider shares the change across flex areas',
        (tester) async {
      addTearDown(tester.view.reset);
      await setWindow(tester, 1400);
      await tester
          .pumpWidget(split(MultiSplitViewController(areas: plainAreas())));
      await tester.pumpAndSettle();
      await dragThrough(tester, dividerAfter(tester, 'sidebar'), [100], (_) {});
      expectWidth(tester, 'sidebar', 300);
      expectWidth(tester, 'list', 542);
      expectWidth(tester, 'detail', 542);
    });

    testWidgets('neighbourOnly without pixel limits resizes the neighbour',
        (tester) async {
      addTearDown(tester.view.reset);
      await setWindow(tester, 1400);
      await tester.pumpWidget(split(
          MultiSplitViewController(areas: plainAreas()),
          policy: FlexResizePolicy.neighbourOnly));
      await tester.pumpAndSettle();
      await dragThrough(tester, dividerAfter(tester, 'sidebar'), [100], (_) {});
      expectWidth(tester, 'sidebar', 300);
      expectWidth(tester, 'list', 492);
      expectWidth(tester, 'detail', 592);
    });

    testWidgets('flex|flex divider without pixel limits is unchanged',
        (tester) async {
      addTearDown(tester.view.reset);
      await setWindow(tester, 1400);
      await tester
          .pumpWidget(split(MultiSplitViewController(areas: plainAreas())));
      await tester.pumpAndSettle();
      await dragThrough(tester, dividerAfter(tester, 'list'), [-450], (_) {});
      expectWidth(tester, 'list', 142);
      expectWidth(tester, 'detail', 1042);
    });
  });

  group('Area', () {
    test('minPixels and collapseSize default to null', () {
      final Area area = Area();
      expect(area.minPixels, isNull);
      expect(area.collapseSize, isNull);
    });

    test('minPixels and collapseSize reject negative values', () {
      expect(() => Area(minPixels: -1), throwsArgumentError);
      expect(() => Area(collapseSize: -1), throwsArgumentError);
    });

    test('copyWith keeps and replaces minPixels and collapseSize', () {
      final Area area = Area(flex: 1, minPixels: 400, collapseSize: 200);
      final Area copy = area.copyWith();
      expect(copy.minPixels, 400);
      expect(copy.collapseSize, 200);
      final Area changed =
          area.copyWith(minPixels: () => null, collapseSize: () => 50);
      expect(changed.minPixels, isNull);
      expect(changed.collapseSize, 50);
    });
  });

  group('MultiSplitViewController.resetSizes', () {
    test('restores constructor size and flex and notifies', () {
      final Area sized = Area(size: 200, min: 100);
      final Area flexed = Area(flex: 0.5);
      final Area other = Area(flex: 0.5);
      final MultiSplitViewController controller =
          MultiSplitViewController(areas: [sized, flexed, other]);
      sized.size = 300;
      flexed.flex = 0.2;
      other.flex = 0.8;
      int notified = 0;
      controller.addListener(() => notified++);
      controller.resetSizes();
      expect(sized.size, 200);
      expect(flexed.flex, 0.5);
      expect(other.flex, 0.5);
      expect(notified, 1);
    });

    test('defaulted flex resets to 1', () {
      final Area area = Area();
      final MultiSplitViewController controller =
          MultiSplitViewController(areas: [area, Area()]);
      area.flex = 3;
      controller.resetSizes();
      expect(area.flex, 1);
    });
  });
}
