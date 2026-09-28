import type { ReadonlyJsonValue } from "@get-bb/plugin-sdk";
import { z } from "zod";

const potetoModeMetadata = z.object({ potetoMode: z.enum(["on", "off"]) });

export type PotetoModeMetadata = z.infer<typeof potetoModeMetadata>;
export type PotetoMode = PotetoModeMetadata["potetoMode"];

export function parsePotetoMode(metadata: ReadonlyJsonValue): PotetoMode | null {
  const parsed = potetoModeMetadata.safeParse(metadata);
  return parsed.success ? parsed.data.potetoMode : null;
}

export function invokesPotetoMode(text: string): boolean {
  return /^[/$]poteto-mode(?![\w-])/m.test(text);
}

export const POTETO_MODE_CHANNEL = "poteto-mode";
export const potetoModeSignal = z.object({ threadId: z.string() });
