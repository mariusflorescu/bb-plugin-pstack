import type { ReadonlyJsonValue } from "@get-bb/plugin-sdk";
import { z } from "zod";

// This plugin's thread metadata. A thread whose metadata does not parse never
// turned poteto-mode on, so it gets neither the standing note nor the chip.
const potetoModeMetadata = z.object({ potetoMode: z.enum(["on", "off"]) });

export type PotetoModeMetadata = z.infer<typeof potetoModeMetadata>;
export type PotetoMode = PotetoModeMetadata["potetoMode"];

export function parsePotetoMode(metadata: ReadonlyJsonValue): PotetoMode | null {
  const parsed = potetoModeMetadata.safeParse(metadata);
  return parsed.success ? parsed.data.potetoMode : null;
}

// Claude Code threads run the skill as /poteto-mode, Codex threads as $poteto-mode.
export function invokesPotetoMode(text: string): boolean {
  return /^[/$]poteto-mode(?![\w-])/m.test(text);
}

// The server publishes this after a message turns the mode on, so an open
// header chip refetches instead of waiting for a reload.
export const POTETO_MODE_CHANNEL = "poteto-mode";
export const potetoModeSignal = z.object({ threadId: z.string() });
