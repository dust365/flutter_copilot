import { VmServiceClient, VmConnectionError } from './client.js';

/**
 * Finds the first Flutter isolate that exposes the flutter_copilot_claw
 * extensions. Detects by the presence of `ext.flutter.flutter_copilot.getLogs`
 * which is registered unconditionally by `FlutterCopilotBinding.initServiceExtensions`.
 */
export async function findFlutterCopilotIsolate(client: VmServiceClient): Promise<string> {
  const vm = await client.getVM();
  if (!vm.isolates || vm.isolates.length === 0) {
    throw new VmConnectionError('VM has no isolates');
  }
  for (const ref of vm.isolates) {
    try {
      const isolate = await client.getIsolate(ref.id);
      if (isolate.extensionRPCs?.includes('ext.flutter.flutter_copilot.getLogs')) {
        return ref.id;
      }
    } catch {
      continue;
    }
  }
  throw new VmConnectionError(
    'No isolate exposes ext.flutter.flutter_copilot.getLogs. ' +
      'Make sure the Flutter app initialised FlutterCopilotBinding (from flutter_copilot_claw).',
  );
}
