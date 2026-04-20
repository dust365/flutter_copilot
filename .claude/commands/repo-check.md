---
description: Run the smallest useful analyze/test suite for the current Flutter Copilot changes
argument-hint: "[optional package, file path, or scope]"
allowed-tools: Bash, Read, Glob, Grep
---

Review the current changes and run the smallest set of checks that gives confidence.

Use this repository's real workflows:
- `dart tool/generate_version.dart` if either published package version changed or if `packages/flutter_copilot_mcp/lib/src/version.g.dart` may be stale.
- `cd packages/flutter_copilot_mcp && dart analyze --fatal-infos lib bin`
- `cd packages/flutter_copilot_claw && flutter analyze --fatal-infos lib`
- `cd packages/flutter_copilot_claw && flutter test`
- `cd example && flutter analyze`
- `cd example && flutter test`
- `cd tool && dart analyze .`

Prefer targeted checks based on the changed files or the optional argument instead of running everything blindly.

At the end, summarize:
1. what you checked,
2. what passed,
3. what failed,
4. what still needs manual verification.
