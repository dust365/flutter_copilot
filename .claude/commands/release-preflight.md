---
description: Run publish-oriented checks for flutter_copilot_claw and flutter_copilot_mcp
argument-hint: "[optional package name]"
allowed-tools: Bash, Read, Glob, Grep
---

Prepare this repository for release or publish.

Always consider these repository-specific checks:
- the two published packages must share the same version in their `pubspec.yaml` files,
- `dart tool/generate_version.dart` must leave `packages/flutter_copilot_mcp/lib/src/version.g.dart` up to date,
- `packages/flutter_copilot_mcp` should pass `dart analyze --fatal-infos lib bin`,
- `packages/flutter_copilot_claw` should pass `flutter analyze --fatal-infos lib`,
- relevant tests should pass before publish,
- `tool/publish.sh` publishes from temporary copied package directories after removing `resolution: workspace`.

If the user is not explicitly publishing yet, stop at a preflight report and do not run the force publish path.

Return a concise punch list of release blockers and ready items.
