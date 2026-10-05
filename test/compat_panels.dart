// Stand-in panels and measurement helpers for compat_test.dart. Each panel
// counts State inits so tests can observe remounts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Map<String, int> inits = {};
final ScrollController listScroll = ScrollController();
final FocusNode detailFocus = FocusNode();

class ListPanel extends StatefulWidget {
  const ListPanel({Key? key}) : super(key: key);

  @override
  State<ListPanel> createState() => _ListPanelState();
}

class _ListPanelState extends State<ListPanel> {
  @override
  void initState() {
    super.initState();
    inits['list'] = (inits['list'] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
      key: const ValueKey('list-content'),
      controller: listScroll,
      itemCount: 200,
      itemExtent: 40,
      itemBuilder: (_, i) => Text('goal $i'));
}

class DetailPanel extends StatefulWidget {
  const DetailPanel({Key? key}) : super(key: key);

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  final TextEditingController text = TextEditingController(text: 'detail');

  @override
  void initState() {
    super.initState();
    inits['detail'] = (inits['detail'] ?? 0) + 1;
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
      key: const ValueKey('detail-content'),
      child: Align(
          alignment: Alignment.topLeft,
          child: TextField(
              key: const ValueKey('detail-field'),
              controller: text,
              focusNode: detailFocus)));
}

class SidebarPanel extends StatelessWidget {
  const SidebarPanel({Key? key, required this.onSwitchFilter})
      : super(key: key);

  final VoidCallback onSwitchFilter;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
      key: const ValueKey('sidebar-content'),
      child: Column(children: [
        TextButton(
            key: const ValueKey('filter'),
            onPressed: onSwitchFilter,
            child: const Text('filter')),
      ]));
}

class DebugPanel extends StatelessWidget {
  const DebugPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('debug-content'));
}

const double dividerThickness = 8;

double? widthOf(WidgetTester tester, String id) {
  final Finder finder = find.byKey(ValueKey('$id-content'));
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.getRect(finder).width;
}

void expectWidth(WidgetTester tester, String id, double expected,
    {String? reason}) {
  expect(widthOf(tester, id), closeTo(expected, 1.5),
      reason: reason ?? '$id width');
}

Future<void> setWindow(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  await tester.pumpAndSettle();
}

/// The x coordinate of the middle of the divider after area [id].
double dividerAfter(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey('$id-content'))).right +
    dividerThickness / 2;

/// Drags one pointer through each cumulative offset in [stops], calling
/// [atStop] after each, then releases.
Future<void> dragThrough(WidgetTester tester, double startX, List<double> stops,
    void Function(double offset) atStop) async {
  final TestGesture gesture = await tester.startGesture(Offset(startX, 300));
  await tester.pump();
  double current = 0;
  for (final double stop in stops) {
    // small increments so the drag recognizer accepts the gesture
    const int steps = 10;
    final double delta = (stop - current) / steps;
    for (int i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(delta, 0));
      await tester.pump();
    }
    current = stop;
    await tester.pumpAndSettle();
    atStop(stop);
  }
  await gesture.up();
  await tester.pumpAndSettle();
}
