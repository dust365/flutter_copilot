import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_copilot_claw/src/binding/flutter_copilot_configuration.dart';
import 'package:flutter_copilot_claw/src/services/gesture_dispatcher.dart';
import 'package:flutter_copilot_claw/src/services/scroll_simulator.dart';
import 'package:flutter_copilot_claw/src/services/widget_finder.dart';
import 'package:flutter_copilot_claw/src/services/widget_matcher.dart';

void main() {
  testWidgets('scroll marks actual swipes without accumulating distance',
      (tester) async {
    final List<List<Offset>> paths = <List<Offset>>[];
    final GestureDispatcher dispatcher = GestureDispatcher(
      onDragPath: paths.add,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          height: 200,
          child: ListView(
            children: <Widget>[
              for (var i = 0; i < 12; i++)
                SizedBox(
                  key: ValueKey<String>('item_$i'),
                  height: 100,
                  child: Text('item $i'),
                ),
            ],
          ),
        ),
      ),
    );

    final Future<void> scroll = ScrollSimulator(
      dispatcher,
      WidgetFinder(),
    ).scrollUntilVisible(
      const KeyMatcher('item_8'),
      const FlutterCopilotConfiguration(),
    );
    // The test surface has no View, so the target never counts as hittable.
    // Listen before pumping, or the exhaustion error is reported uncaught.
    final Future<void> exhausted = expectLater(
      scroll,
      throwsA(isA<StateError>()),
    );
    await tester.pump(const Duration(seconds: 5));
    await exhausted;

    expect(paths, hasLength(100));
    expect(paths.every((List<Offset> path) => path.length >= 2), isTrue);
    expect((paths.first.last - paths.first.first).distance, 64);
    expect(
        paths.every((path) => (path.last - path.first).distance == 64), isTrue);
  });
}
