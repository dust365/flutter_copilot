import 'package:flutter/widgets.dart';

import '../services/widget_rebuild_tracker.dart';

/// A [FocusManager] that skips global handler registration.
///
/// When a second [BuildOwner] is created, its constructor calls
/// [FocusManager.registerGlobalHandlers], which asserts that the global key
/// handler has not been registered yet. This subclass overrides
/// [registerGlobalHandlers] to be a no-op, avoiding the assertion.
///
/// The real [FocusManager] (from the default [BuildOwner]) is exposed via
/// [CopilotBuildOwner.focusManager] getter override.
class _NoOpRegisterFocusManager extends FocusManager {
  @override
  void registerGlobalHandlers() {
    // Intentionally empty — global handlers are already registered by the
    // default BuildOwner's FocusManager created during super.initInstances().
  }
}

/// A [BuildOwner] that records each [Element] scheduled for rebuild via
/// [WidgetRebuildTracker], for global repaint monitoring without wrapping widgets.
///
/// Used by [FlutterCopilotBinding] when [FlutterCopilotConfiguration.enableGlobalRebuildHook]
/// is true. Overrides [scheduleBuildFor] to call [WidgetRebuildTracker.recordBuild]
/// with [element.widget]'s type and key before delegating to the superclass.
///
/// A [_NoOpRegisterFocusManager] is passed to the super constructor to avoid
/// the FocusManager global handler double-registration assertion. The real
/// [FocusManager] is exposed via the overridden [focusManager] getter.
class CopilotBuildOwner extends BuildOwner {
  CopilotBuildOwner({
    VoidCallback? onBuildScheduled,
    required FocusManager realFocusManager,
  })  : _realFocusManager = realFocusManager,
        super(
          onBuildScheduled: onBuildScheduled,
          focusManager: _NoOpRegisterFocusManager(),
        );

  final FocusManager _realFocusManager;

  /// Returns the real [FocusManager] from the default [BuildOwner], not the
  /// no-op placeholder passed to super.
  @override
  FocusManager get focusManager => _realFocusManager;

  @override
  void scheduleBuildFor(Element element) {
    WidgetRebuildTracker.instance?.recordBuild(
      element.widget.runtimeType.toString(),
      element.widget.key?.toString(),
    );
    super.scheduleBuildFor(element);
  }
}
