import chalk from 'chalk';

export type OutputMode = 'tty' | 'json';

let outputMode: OutputMode = 'tty';

export function setOutputMode(m: OutputMode): void {
  outputMode = m;
}

export function getOutputMode(): OutputMode {
  return outputMode;
}

/** Prints a human-readable success line (TTY) or a JSON `{ok: true, ...}` payload. */
export function ok(message: string, payload?: Record<string, unknown>): void {
  if (outputMode === 'json') {
    process.stdout.write(JSON.stringify({ ok: true, message, ...(payload ?? {}) }) + '\n');
  } else {
    process.stdout.write(`${chalk.green('✓')} ${message}\n`);
  }
}

/** Prints an error; non-fatal (does not exit). */
export function err(message: string, payload?: Record<string, unknown>): void {
  if (outputMode === 'json') {
    process.stderr.write(JSON.stringify({ ok: false, error: message, ...(payload ?? {}) }) + '\n');
  } else {
    process.stderr.write(`${chalk.red('✗')} ${message}\n`);
  }
}

/** Dumps raw data. In JSON mode: pretty JSON. In TTY mode: callback chooses. */
export function data(value: unknown, pretty?: () => void): void {
  if (outputMode === 'json') {
    process.stdout.write(JSON.stringify(value, null, 2) + '\n');
  } else if (pretty) {
    pretty();
  } else {
    process.stdout.write(JSON.stringify(value, null, 2) + '\n');
  }
}

export function info(message: string): void {
  if (outputMode === 'json') return;
  process.stderr.write(`${chalk.blueBright('ℹ')} ${message}\n`);
}

export function dim(message: string): void {
  if (outputMode === 'json') return;
  process.stderr.write(`${chalk.gray(message)}\n`);
}
