---
description: Validate the example Flutter app and its Copilot integration paths
argument-hint: "[optional page, route, or file]"
allowed-tools: Bash, Read, Glob, Grep, Edit
---

Focus on the `example/` app.

Check the app entrypoint, routing, and any changed demo pages relevant to the user's request. Use the repository's actual commands when verifying:
- `flutter analyze example/lib/main.dart`
- `cd example && flutter analyze`
- `cd example && flutter test`

If the change touches Flutter Copilot initialization, verify that the example uses the current supported API from `flutter_copilot_claw` instead of stale binding calls.

If you make edits, re-run the smallest relevant checks and report any remaining manual app-run verification that should still be done in `cd example && flutter run`.
