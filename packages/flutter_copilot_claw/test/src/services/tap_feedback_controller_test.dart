import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';

void main() {
  group('TapFeedbackController', () {
    testWidgets('default lifetime is 1.2 seconds', (tester) async {
      final controller = TapFeedbackController();
      addTearDown(controller.dispose);
      controller.showAt(const Offset(20, 20));

      await tester.pump(const Duration(milliseconds: 1199));
      expect(controller.state.value, isNotNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.state.value, isNull);
    });

    testWidgets('showTap stores the hit point', (tester) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );

      controller.showTap(position: const Offset(60, 20));

      final TapFeedbackState state = controller.state.value!;
      expect(state.position, const Offset(60, 20));
      expect(state.path, isEmpty);
      expect(state.isDrag, isFalse);
      controller.dispose();
    });

    testWidgets('showAt keeps the point-only call working', (tester) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );

      controller.showAt(const Offset(3, 4));

      expect(controller.state.value!.position, const Offset(3, 4));
      expect(controller.state.value!.path, isEmpty);
      controller.dispose();
    });

    testWidgets('showDrag stores the polyline and ignores an empty path', (
      tester,
    ) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );

      controller.showDrag(const <Offset>[Offset(1, 2), Offset(1, 40)]);
      expect(controller.state.value!.isDrag, isTrue);
      expect(controller.state.value!.path, <Offset>[
        const Offset(1, 2),
        const Offset(1, 40),
      ]);

      controller.showDrag(const <Offset>[]);
      expect(controller.state.value!.path, hasLength(2));
      controller.dispose();
    });

    testWidgets('a path that does not move is not a drag stroke', (
      tester,
    ) async {
      final TapFeedbackState state = TapFeedbackState(
        position: Offset.zero,
        path: const <Offset>[Offset.zero, Offset.zero],
      );

      expect(state.isDrag, isFalse);
    });

    testWidgets('the mark stays up for the full window after it is shown', (
      tester,
    ) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(milliseconds: 1200),
      );
      addTearDown(controller.dispose);

      controller.showTap(position: const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 1199));
      expect(controller.state.value, isNotNull);

      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.state.value, isNull);
    });

    testWidgets('showing again restarts the visible window', (tester) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(milliseconds: 1200),
      );
      addTearDown(controller.dispose);

      controller.showTap(position: const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 1000));
      controller.showDrag(const <Offset>[Offset(0, 0), Offset(0, 80)]);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(controller.state.value!.isDrag, isTrue);

      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.state.value, isNull);
    });

    testWidgets('clear removes the mark immediately', (tester) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);

      controller.showTap(position: const Offset(1, 1));
      controller.clear();
      expect(controller.state.value, isNull);

      await tester.pump(const Duration(seconds: 5));
      expect(controller.state.value, isNull);
    });
  });
}
