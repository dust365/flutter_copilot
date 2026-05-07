import { Command } from 'commander';
import { InstanceRegistry } from '../registry/instance_registry.js';
import * as log from '../logging.js';

export function registerCommand(program: Command, registry: InstanceRegistry): void {
  program
    .command('register <name> <uri>')
    .description('Save a Flutter app instance so you can target it later with `-i <name>`.')
    .action(async (name: string, uri: string) => {
      const overwritten = await registry.register(name, uri);
      log.ok(
        overwritten ? `Updated instance "${name}".` : `Registered instance "${name}".`,
        { name, uri, overwritten },
      );
    })
    .addHelpText(
      'after',
      `
Registry lives under ~/.flutter-copilot/instances/<name>.json (one file per
instance, written atomically) and survives across shells. Useful when you juggle
multiple devices/apps simultaneously.

Example:
  fcc register demo ws://127.0.0.1:8181/abc/ws
  fcc -i demo tap --text "Increment"
`,
    );

  program
    .command('unregister <name>')
    .description('Remove a registered Flutter app instance.')
    .action(async (name: string) => {
      const removed = await registry.unregister(name);
      if (!removed) {
        log.err(`Instance "${name}" not found.`);
        process.exitCode = 1;
        return;
      }
      log.ok(`Unregistered instance "${name}".`, { name });
    });

  program
    .command('list')
    .description('List all registered Flutter app instances.')
    .action(async () => {
      const all = await registry.listAll();
      if (all.length === 0) {
        log.info('No instances registered. Use `fcc register <name> <uri>`.');
        log.data({ instances: [] });
        return;
      }
      log.data(
        { instances: all },
        () => {
          for (const i of all) {
            process.stdout.write(`${i.name}\t${i.uri}\t${i.registeredAt}\n`);
          }
        },
      );
    });
}
