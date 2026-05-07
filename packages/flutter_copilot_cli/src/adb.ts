import { spawn } from 'node:child_process';

export interface AdbResult {
  success: boolean;
  stderr: string;
}

function runAdb(args: string[]): Promise<{ code: number | null; stderr: string }> {
  return new Promise((resolve) => {
    const proc = spawn('adb', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    proc.stderr?.on('data', (d) => (stderr += d.toString()));
    proc.on('error', () => resolve({ code: null, stderr: 'adb not found' }));
    proc.on('close', (code) => resolve({ code, stderr: stderr.trim() }));
  });
}

export class AdbHelper {
  async isAvailable(): Promise<boolean> {
    const r = await runAdb(['version']);
    return r.code === 0;
  }

  async setupReverse(port: number): Promise<AdbResult> {
    const r = await runAdb(['reverse', `tcp:${port}`, `tcp:${port}`]);
    return { success: r.code === 0, stderr: r.stderr };
  }

  async removeReverse(port: number): Promise<AdbResult> {
    const r = await runAdb(['reverse', '--remove', `tcp:${port}`]);
    return { success: r.code === 0, stderr: r.stderr };
  }
}
