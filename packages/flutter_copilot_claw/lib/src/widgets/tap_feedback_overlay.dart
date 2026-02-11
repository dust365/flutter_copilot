import 'package:flutter/widgets.dart';

import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';

/// Radius of the tap feedback dot in logical pixels.
const double _kTapFeedbackRadius = 28.0;

/// Widget that shows a red radial-gradient dot at the last MCP tap position.
///
/// Typically used internally by [FlutterCopilotBinding] which auto-injects it
/// via [OverlayEntry]. You do NOT need to add this to your widget tree.
class TapFeedbackOverlay extends StatelessWidget {
  const TapFeedbackOverlay({super.key, required this.controller});

  /// The controller that provides the tap position to display.
  final TapFeedbackController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<TapFeedbackState?>(
        valueListenable: controller.state,
        builder: (BuildContext context, TapFeedbackState? state, Widget? child) {
          if (state == null) return const SizedBox.shrink();
          final double r = _kTapFeedbackRadius;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              const SizedBox.expand(),
              Positioned(
                left: state.position.dx - r,
                top: state.position.dy - r,
                width: r * 2,
                height: r * 2,
                child: CustomPaint(
                  painter: _RedDotPainter(radius: r),
                  size: Size(r * 2, r * 2),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RedDotPainter extends CustomPainter {
  _RedDotPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    const RadialGradient gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: <Color>[
        Color(0xE6FF0000), // center: red, ~90% opacity
        Color(0x00FF0000), // edge: red, fully transparent
      ],
    );
    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final Paint paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
