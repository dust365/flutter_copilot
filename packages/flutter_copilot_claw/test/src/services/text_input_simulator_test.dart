import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_copilot_claw/src/binding/flutter_copilot_configuration.dart';
import 'package:flutter_copilot_claw/src/services/text_input_simulator.dart';
import 'package:flutter_copilot_claw/src/services/widget_finder.dart';
import 'package:flutter_copilot_claw/src/services/widget_matcher.dart';

void main() {
  testWidgets('enterText updates the controller and calls onChanged',
      (tester) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    final List<String> changes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            key: const ValueKey<String>('name'),
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await TextInputSimulator(WidgetFinder()).enterText(
      const KeyMatcher('name'),
      'hello',
      const FlutterCopilotConfiguration(),
    );
    await tester.pump();

    expect(controller.text, 'hello');
    // Controller writes alone do not fire onChanged; enterText must notify it
    // so validation and form state see the automated value.
    expect(changes, ['hello']);
  });
}
