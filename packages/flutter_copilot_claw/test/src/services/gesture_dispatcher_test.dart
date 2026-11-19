import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_copilot_claw/src/binding/flutter_copilot_configuration.dart';
import 'package:flutter_copilot_claw/src/services/gesture_dispatcher.dart';
import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';
import 'package:flutter_copilot_claw/src/services/widget_finder.dart';
import 'package:flutter_copilot_claw/src/services/widget_matcher.dart';

void main() {
  const FlutterCopilotConfiguration configuration =
      FlutterCopilotConfiguration();
  final WidgetFinder finder = WidgetFinder();

  group('GestureDispatcher feedback', () {
    testWidgets('tap marks the center of the widget', (tester) async {
      final List<Offset> taps = <Offset>[];
      final GestureDispatcher dispatcher = GestureDispatcher(
        onTapAt: (Offset position, TapFeedbackKind kind) => taps.add(position),
      );
      await tester.pumpWidget(_targetBox());
      final Rect rect = tester.getRect(
        find.byKey(const ValueKey<String>('target')),
      );

      final Future<void> gesture = dispatcher.tap(
        const KeyMatcher('target'),
        finder,
        configuration,
      );
      expect(taps, hasLength(1));
      expect(taps.single, rect.center);

      await tester.pump(const Duration(milliseconds: 400));
      await gesture;
      expect(taps, hasLength(2));
      expect(taps.last, rect.center);
    });

    testWidgets('a coordinate tap marks the given point', (tester) async {
      final List<Offset> taps = <Offset>[];
      final GestureDispatcher dispatcher = GestureDispatcher(
        onTapAt: (Offset position, TapFeedbackKind kind) => taps.add(position),
      );
      await tester.pumpWidget(const SizedBox.shrink());

      final Future<void> gesture = dispatcher.tap(
        const CoordinatesMatcher(12, 34),
        finder,
        configuration,
      );
      expect(taps.single, const Offset(12, 34));

      await tester.pump(const Duration(milliseconds: 400));
      await gesture;
      expect(taps, hasLength(2));
    });

    testWidgets('a route change drops the mark drawn after the tap', (
      tester,
    ) async {
      var epoch = 0;
      final List<Offset> taps = <Offset>[];
      final GestureDispatcher dispatcher = GestureDispatcher(
        onTapAt: (Offset position, TapFeedbackKind kind) => taps.add(position),
        routeEpoch: () => epoch,
      );
      await tester.pumpWidget(const SizedBox.shrink());

      final Future<void> gesture = dispatcher.tap(
        const CoordinatesMatcher(12, 34),
        finder,
        configuration,
      );
      expect(taps, hasLength(1));
      epoch = 1;

      await tester.pump(const Duration(milliseconds: 400));
      await gesture;
      expect(taps, hasLength(1));
    });

    testWidgets('drag reports the pointer polyline before and after', (
      tester,
    ) async {
      final List<List<Offset>> paths = <List<Offset>>[];
      final GestureDispatcher dispatcher = GestureDispatcher(
        onDragPath: paths.add,
      );
      await tester.pumpWidget(const SizedBox.shrink());

      final Future<void> gesture = dispatcher.drag(
        const Offset(10, 10),
        const Offset(90, 10),
      );
      expect(paths, hasLength(1));
      expect(paths.single, <Offset>[
        const Offset(10, 10),
        const Offset(50, 10),
        const Offset(90, 10),
      ]);

      await tester.pump(const Duration(milliseconds: 80));
      await gesture;
      expect(paths, hasLength(2));
      expect(paths.last, paths.first);
    });

    testWidgets('swipe reports a trail from the target center', (
      tester,
    ) async {
      final List<List<Offset>> paths = <List<Offset>>[];
      final GestureDispatcher dispatcher = GestureDispatcher(
        onDragPath: paths.add,
      );
      await tester.pumpWidget(_targetBox());
      final Offset center =
          tester.getRect(find.byKey(const ValueKey<String>('target'))).center;

      final Future<void> gesture = dispatcher.swipe(
        const KeyMatcher('target'),
        'down',
        80,
        finder,
        configuration,
      );
      expect(paths.single.first, center);
      expect(paths.single.last, center + const Offset(0, 80));

      await tester.pump(const Duration(milliseconds: 50));
      await gesture;
      expect(paths, hasLength(2));
    });

    testWidgets('tap marks the visible box center past a container margin', (
      tester,
    ) async {
      final List<Offset> taps = <Offset>[];
      final GestureDispatcher dispatcher = GestureDispatcher(
        onTapAt: (Offset position, TapFeedbackKind kind) => taps.add(position),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              key: const ValueKey<String>('card'),
              width: 100,
              height: 40,
              margin: const EdgeInsets.only(left: 80),
              color: const Color(0xFF2196F3),
            ),
          ),
        ),
      );

      final Future<void> gesture = dispatcher.tap(
        const KeyMatcher('card'),
        finder,
        configuration,
      );
      expect(taps.single, const Offset(130, 20));

      await tester.pump(const Duration(milliseconds: 400));
      await gesture;
    });

    testWidgets('a keyed padding marks its own box center', (tester) async {
      final List<Offset> taps = <Offset>[];
      final GestureDispatcher dispatcher = GestureDispatcher(
        onTapAt: (Offset position, TapFeedbackKind kind) => taps.add(position),
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              key: ValueKey<String>('pad'),
              padding: EdgeInsets.only(left: 80),
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );

      final Future<void> gesture = dispatcher.tap(
        const KeyMatcher('pad'),
        finder,
        configuration,
      );
      expect(taps.single, const Offset(90, 20));

      await tester.pump(const Duration(milliseconds: 400));
      await gesture;
    });
  });
}

Widget _targetBox() {
  return const Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: ValueKey<String>('target'),
        width: 120,
        height: 40,
      ),
    ),
  );
}
