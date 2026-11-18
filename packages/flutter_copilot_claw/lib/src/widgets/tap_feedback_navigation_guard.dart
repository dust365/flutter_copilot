import 'package:flutter/widgets.dart';

import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';
import 'package:flutter_copilot_claw/src/widgets/tap_feedback_overlay.dart';

/// Clears the gesture mark as soon as the route stack changes.
///
/// The mark is painted in the root [Overlay], and [Navigator] keeps that entry
/// above every route. [WidgetsApp] also consumes [NavigationNotification], so
/// this guard watches overlay entry keys instead. Those keys stay stable for
/// the life of a route: a push or pop changes the list, and a [PopScope]
/// update does not.
///
/// [FlutterCopilotBinding] wraps the root widget with this guard.
class TapFeedbackNavigationGuard extends StatefulWidget {
  const TapFeedbackNavigationGuard({
    super.key,
    required this.controller,
    required this.child,
    this.onRouteChanged,
  });

  /// Mark to clear when navigation happens.
  final TapFeedbackController controller;

  /// Called when the route stack changes, before the mark is cleared.
  ///
  /// Gestures use this generation to avoid drawing the mark again after the
  /// page that was touched has already been replaced.
  final VoidCallback? onRouteChanged;

  /// Application below this guard. Must contain the [Navigator].
  final Widget child;

  @override
  State<TapFeedbackNavigationGuard> createState() =>
      _TapFeedbackNavigationGuardState();
}

class _TapFeedbackNavigationGuardState
    extends State<TapFeedbackNavigationGuard> {
  List<OverlayState> _overlays = <OverlayState>[];
  List<Key?>? _stack;
  Key? _feedbackEntryKey;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _onFrame(Duration _) {
    if (_disposed || !mounted) {
      return;
    }
    if (!_overlaysMounted) {
      _overlays = _findOverlays();
    }
    final List<Key?> next = _entryKeys();
    final List<Key?>? previous = _stack;
    if (previous != null && !_sameStack(previous, next)) {
      widget.onRouteChanged?.call();
      widget.controller.clear();
      // A new page may contain another navigator. Pick it up before the next
      // comparison so the following frame does not clear again.
      _overlays = _findOverlays();
      _stack = _entryKeys();
      return;
    }
    _stack = next;
  }

  bool get _overlaysMounted =>
      _overlays.isNotEmpty &&
      _overlays.every((OverlayState overlay) => overlay.mounted);

  List<OverlayState> _findOverlays() {
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return <OverlayState>[];
    }
    final List<OverlayState> overlays = <OverlayState>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is OverlayState) {
        final OverlayState overlay = element.state as OverlayState;
        if (overlay.mounted) {
          overlays.add(overlay);
        }
      }
      element.visitChildren(visit);
    }

    visit(root);
    return overlays;
  }

  List<Key?> _entryKeys() {
    final List<Key?> keys = <Key?>[];
    for (final OverlayState overlay in _overlays) {
      if (!overlay.mounted) {
        continue;
      }
      overlay.context.visitChildElements((Element theater) {
        theater.visitChildElements((Element entry) {
          final Key? key = entry.widget.key;
          if (key != null && key == _feedbackEntryKey) {
            return;
          }
          if (_feedbackEntryKey == null && _containsTapFeedback(entry)) {
            _feedbackEntryKey = key;
            return;
          }
          keys.add(key);
        });
      });
    }
    return keys;
  }

  bool _containsTapFeedback(Element element) {
    var found = false;
    void visit(Element candidate) {
      if (found) {
        return;
      }
      if (candidate.widget is TapFeedbackOverlay) {
        found = true;
        return;
      }
      candidate.visitChildren(visit);
    }

    visit(element);
    return found;
  }

  bool _sameStack(List<Key?> previous, List<Key?> next) {
    if (previous.length != next.length) {
      return false;
    }
    for (var i = 0; i < previous.length; i++) {
      if (previous[i] != next[i]) {
        return false;
      }
    }
    return true;
  }
}
