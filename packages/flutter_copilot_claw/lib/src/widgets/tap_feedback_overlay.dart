import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';

const Color _kError = Color(0xFFF44336);
const Color _kHalo = Color(0xFFFFFFFF);

/// Paints the latest copilot gesture on top of the app.
///
/// Paints a red ring and translucent center dot at the hit point, and a
/// straight arrow for a drag or swipe. Long press and double tap add a
/// second ring.
/// The overlay is [IgnorePointer], so the mark does not receive the synthetic
/// pointer events. It is part of the layer tree and shows up in screenshots
/// taken while it is visible.
///
/// [FlutterCopilotBinding] inserts this automatically. Do not add it yourself.
class TapFeedbackOverlay extends StatelessWidget {
  const TapFeedbackOverlay({super.key, required this.controller});

  /// Source of the mark to paint.
  final TapFeedbackController controller;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ValueListenableBuilder<TapFeedbackState?>(
          valueListenable: controller.state,
          builder:
              (BuildContext context, TapFeedbackState? state, Widget? child) {
            if (state == null) {
              return const SizedBox.shrink();
            }
            return CustomPaint(
              painter: _GestureFeedbackPainter(state, context),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _GestureFeedbackPainter extends CustomPainter {
  _GestureFeedbackPainter(this.state, this.context);

  final TapFeedbackState state;
  final BuildContext context;

  @override
  void paint(Canvas canvas, Size size) {
    // Match the reference in logical pixels. Scaling by the window's height
    // shrinks the mark in landscape and in short desktop windows.
    const double stroke = 2;
    const double radius = 16;

    // Gesture positions are global logical coordinates. Cancel the overlay's
    // transform so insets or a transformed Navigator cannot move the mark.
    final renderBox = context.findRenderObject() as RenderBox;
    final transform = renderBox.getTransformTo(null);
    if (transform.invert() == 0) {
      return;
    }
    canvas.save();
    canvas.transform(transform.storage);

    if (state.kind == TapFeedbackKind.drag && state.path.length >= 2) {
      _paintArrow(canvas, state.path.first, state.path.last, stroke);
    }

    final Offset point = state.position;
    _circle(canvas, point, radius, stroke);
    if (state.kind == TapFeedbackKind.longPress ||
        state.kind == TapFeedbackKind.doubleTap) {
      _circle(canvas, point, radius * 1.4, stroke);
    }
    canvas.drawCircle(point, 3, Paint()..color = _kError.withAlpha(191));
    canvas.restore();
  }

  void _paintArrow(Canvas canvas, Offset from, Offset to, double stroke) {
    final Offset delta = to - from;
    if (delta.distance <= 1) {
      return;
    }
    final Offset unit = delta / delta.distance;
    final double head = math.min(12, delta.distance / 2);
    final Offset base = to - unit * head;
    final Offset side = Offset(-unit.dy, unit.dx) * head * 0.6;
    _outline(
      canvas,
      Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy)
        ..moveTo((base + side).dx, (base + side).dy)
        ..lineTo(to.dx, to.dy)
        ..lineTo((base - side).dx, (base - side).dy),
      stroke,
    );
  }

  void _circle(Canvas canvas, Offset center, double radius, double stroke) {
    _outline(
      canvas,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      stroke,
    );
  }

  void _outline(
    Canvas canvas,
    Path path,
    double stroke,
  ) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _kHalo
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.5,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _kError
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _GestureFeedbackPainter oldDelegate) {
    final TapFeedbackState previous = oldDelegate.state;
    return previous.kind != state.kind ||
        previous.position != state.position ||
        !listEquals(previous.path, state.path);
  }
}
