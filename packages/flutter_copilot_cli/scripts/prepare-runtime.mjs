import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import YAML from 'yaml';

const cli = fileURLToPath(new URL('../', import.meta.url));
const mcp = path.resolve(cli, '../flutter_copilot_mcp');
const output = path.join(cli, 'runtime');
const pubspec = YAML.parse(await readFile(path.join(mcp, 'pubspec.yaml'), 'utf8'));
const npm = JSON.parse(await readFile(path.join(cli, 'package.json'), 'utf8'));
if (pubspec.version !== npm.version) throw new Error('MCP/CLI versions must match before bundling');
await rm(output, { recursive: true, force: true });
await mkdir(path.join(output, 'lib/src/vm_service'), { recursive: true });
await mkdir(path.join(output, 'bin'), { recursive: true });
for (const directory of ['session', 'dtd', 'process']) {
  await cp(path.join(mcp, 'lib/src', directory), path.join(output, 'lib/src', directory), { recursive: true });
}
for (const file of ['vm_service/vm_service_connector.dart', 'version.g.dart']) {
  await cp(path.join(mcp, 'lib/src', file), path.join(output, 'lib/src', file));
}
await cp(path.join(mcp, 'bin/flutter_copilot_session.dart'), path.join(output, 'bin/flutter_copilot_session.dart'));
const dependencies = Object.fromEntries(['crypto', 'dtd', 'logging', 'path', 'vm_service'].map((name) => [name, pubspec.dependencies[name]]));
await writeFile(path.join(output, 'pubspec.yaml'), YAML.stringify({
  name: pubspec.name, version: pubspec.version, publish_to: 'none',
  environment: pubspec.environment, dependencies,
}));
try {
  execFileSync(process.env.DART_EXECUTABLE ?? 'dart', ['pub', 'get', '--no-precompile'], { cwd: output, stdio: 'pipe' });
} finally { await rm(path.join(output, '.dart_tool'), { recursive: true, force: true }); }
const hash = createHash('sha256');
async function visit(directory) {
  for (const entry of (await readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await visit(file);
    else { hash.update(path.relative(output, file)); hash.update(await readFile(file)); }
  }
}
await visit(output);
await writeFile(path.join(output, 'manifest.json'), JSON.stringify({ version: npm.version, hash: hash.digest('hex') }));
