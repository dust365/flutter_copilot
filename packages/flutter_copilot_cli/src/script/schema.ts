import { z } from 'zod';

const Matcher = z.object({
  key: z.string().optional(),
  text: z.string().optional(),
  type: z.string().optional(),
  x: z.number().optional(),
  y: z.number().optional(),
  focused: z.boolean().optional(),
});

const Retry = z
  .object({
    attempts: z.number().int().positive().default(3),
    delay: z.number().int().nonnegative().default(500),
  })
  .partial()
  .optional();

const BaseStep = z.object({
  name: z.string().optional(),
  retry: Retry,
});

const Step = z.discriminatedUnion('action', [
  BaseStep.extend({ action: z.literal('tap') }).merge(Matcher),
  BaseStep.extend({ action: z.literal('double-tap') }).merge(Matcher),
  BaseStep.extend({
    action: z.literal('long-press'),
    duration: z.number().int().positive().optional(),
  }).merge(Matcher),
  BaseStep.extend({
    action: z.literal('enter-text'),
    input: z.string(),
  }).merge(Matcher),
  BaseStep.extend({ action: z.literal('scroll-to') }).merge(Matcher),
  BaseStep.extend({
    action: z.literal('swipe'),
    direction: z.enum(['up', 'down', 'left', 'right']),
    distance: z.number().positive().optional(),
  }).merge(Matcher),
  BaseStep.extend({
    action: z.literal('drag'),
    dx: z.number().optional(),
    dy: z.number().optional(),
    fromX: z.number().optional(),
    fromY: z.number().optional(),
    toX: z.number().optional(),
    toY: z.number().optional(),
  }).merge(Matcher),
  BaseStep.extend({
    action: z.literal('navigate'),
    op: z.enum(['push', 'pop', 'replace', 'pushReplacement', 'popUntil']),
    route: z.string().optional(),
    arguments: z.record(z.unknown()).optional(),
  }),
  BaseStep.extend({
    action: z.literal('hot-reload'),
  }),
  BaseStep.extend({
    action: z.literal('screenshot'),
    output: z.string(),
    numbered: z.boolean().optional(),
  }),
  BaseStep.extend({
    action: z.literal('wait'),
    ms: z.number().int().positive(),
  }),
  BaseStep.extend({
    action: z.literal('assert-element'),
    exists: z.boolean().default(true),
  }).merge(Matcher),
]);

export const Script = z.object({
  name: z.string().optional(),
  stopOnFailure: z.boolean().default(true),
  steps: z.array(Step).min(1),
});

export type ScriptT = z.infer<typeof Script>;
export type StepT = z.infer<typeof Step>;
