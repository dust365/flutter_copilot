import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';
import 'package:flutter_copilot_claw/src/widgets/tap_feedback_navigation_guard.dart';
import 'package:flutter_copilot_claw/src/widgets/tap_feedback_overlay.dart';

void main() {
  group('TapFeedbackOverlay', () {
    testWidgets('paints a translucent hit point without a widget border',
        (tester) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );
      await _pumpOverlay(tester, controller);

      final _Shot blank = await _capture(tester);
      expect(blank.at(8, 8).a, 0);

      controller.showTap(position: const Offset(100, 80));
      await tester.pump();

      final _Shot image = await _capture(tester);
      expect(_isErrorRed(image.at(100, 80)), isTrue);
      expect(image.at(100, 80).a, closeTo(191, 1));
      expect(image.at(40, 50).a, 0);
      expect(image.at(30, 80).a, 0);
      expect(image.at(100, 40).a, 0);
      expect(image.at(170, 80).a, 0);
      expect(image.at(8, 8).a, 0);
      expect(find.byType(IgnorePointer), findsOneWidget);
      controller.dispose();
    });

    testWidgets('paints a drag trail that a screenshot can capture', (
      tester,
    ) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );
      await _pumpOverlay(tester, controller);

      controller.showDrag(const <Offset>[Offset(20, 100), Offset(180, 100)]);
      await tester.pump();

      final _Shot image = await _capture(tester);
      expect(_isErrorRed(image.at(100, 100)), isTrue);
      expect(image.at(100, 30).a, 0);
      controller.dispose();
    });

    testWidgets('clears the painted mark when the controller clears', (
      tester,
    ) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );
      await _pumpOverlay(tester, controller);

      controller.showTap(position: const Offset(100, 100));
      await tester.pump();
      controller.clear();
      await tester.pump();

      final _Shot image = await _capture(tester);
      expect(image.at(100, 100).a, 0);
      controller.dispose();
    });

    testWidgets('keeps the ring readable in a short landscape window', (
      tester,
    ) async {
      final controller = TapFeedbackController();
      addTearDown(controller.dispose);
      await _pumpOverlay(tester, controller, size: const Size(812, 375));

      controller.showAt(const Offset(100, 100));
      await tester.pump();

      final image = await _capture(tester);
      expect(_isErrorRed(image.at(116, 100)), isTrue);
      expect(image.at(117, 100).a, greaterThan(180));
      expect(image.at(108, 100).a, 0);
      controller.dispose();
    });

    testWidgets('aligns global marks inside an inset overlay', (tester) async {
      final controller = TapFeedbackController();
      addTearDown(controller.dispose);
      await _pumpOverlay(
        tester,
        controller,
        inset: const EdgeInsets.only(left: 24, top: 60),
      );

      controller.showTap(position: const Offset(100, 100));
      await tester.pump();

      final image = await _capture(tester);
      expect(_isErrorRed(image.at(100, 100)), isTrue);
      expect(image.at(40, 100).a, 0);
      expect(image.at(124, 160).a, 0);

      controller.showDrag(const [Offset(100, 100), Offset(100, 250)]);
      await tester.pump();
      final drag = await _capture(tester);
      expect(_isErrorRed(drag.at(100, 180)), isTrue);
      expect(_isErrorRed(drag.at(104, 243)), isTrue);
      expect(drag.at(124, 200).a, 0);
      controller.dispose();
    });
  });

  group('TapFeedbackNavigationGuard', () {
    testWidgets('clears the mark when a route is pushed or popped', (
      tester,
    ) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        TapFeedbackNavigationGuard(
          controller: controller,
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                return TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => const Text('next'),
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      controller.showTap(position: const Offset(10, 10));
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(controller.state.value, isNull);

      await tester.pumpAndSettle();
      controller.showTap(position: const Offset(10, 10));
      Navigator.of(tester.element(find.text('next'))).pop();
      await tester.pump();
      expect(controller.state.value, isNull);
      controller.dispose();
    });

    testWidgets('keeps the mark when the route stack does not change', (
      tester,
    ) async {
      final TapFeedbackController controller = TapFeedbackController(
        duration: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        TapFeedbackNavigationGuard(
          controller: controller,
          child: const MaterialApp(home: Text('home')),
        ),
      );
      await tester.pump();

      controller.showTap(position: const Offset(10, 10));
      await tester.pump();
      expect(controller.state.value, isNotNull);
      controller.dispose();
    });
  });
}

Future<void> _pumpOverlay(
  WidgetTester tester,
  TapFeedbackController controller, {
  Size size = const Size(375, 812),
  EdgeInsets inset = EdgeInsets.zero,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: Padding(
          padding: inset,
          child: TapFeedbackOverlay(controller: controller),
        ),
      ),
    ),
  );
}

Future<_Shot> _capture(WidgetTester tester) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
  final _Shot? shot = await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final _Shot captured = _Shot(data!, image.width, image.height);
    image.dispose();
    return captured;
  });
  return shot!;
}

class _Shot {
  _Shot(this.bytes, this.width, this.height);

  final ByteData bytes;
  final int width;
  final int height;

  _Pixel at(int x, int y) {
    final int o = (y * width + x) * 4;
    return _Pixel(
      bytes.getUint8(o),
      bytes.getUint8(o + 1),
      bytes.getUint8(o + 2),
      bytes.getUint8(o + 3),
    );
  }
}

class _Pixel {
  const _Pixel(this.r, this.g, this.b, this.a);

  final int r;
  final int g;
  final int b;
  final int a;
}

bool _isErrorRed(_Pixel pixel) {
  return (pixel.r - 244).abs() < 40 &&
      (pixel.g - 67).abs() < 40 &&
      (pixel.b - 54).abs() < 40 &&
      pixel.a > 180;
}
