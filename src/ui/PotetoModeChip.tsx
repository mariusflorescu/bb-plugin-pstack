import {
  useRealtime,
  useRealtimeConnectionState,
  useSdk,
  type PluginThreadHeaderActionProps,
} from "@get-bb/plugin-sdk/app";
import { queryOptions, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { Button } from "../../components/ui/button";
import { Icon } from "../../components/ui/icon";
import { Tooltip, TooltipContent, TooltipTrigger } from "../../components/ui/tooltip";
import { cn } from "../../lib/utils";
import {
  POTETO_MODE_CHANNEL,
  parsePotetoMode,
  potetoModeSignal,
  type PotetoMode,
  type PotetoModeMetadata,
} from "../poteto-mode";

const CHIPS: Record<PotetoMode, { text: string; next: PotetoMode; className: string }> = {
  on: { text: "poteto-mode", next: "off", className: "bg-secondary text-secondary-foreground" },
  off: { text: "poteto-mode off", next: "on", className: "border border-border text-muted-foreground" },
};

export function PotetoModeChip({ threadId, isCompactViewport }: PluginThreadHeaderActionProps) {
  const sdk = useSdk();
  const queryClient = useQueryClient();
  const query = queryOptions({
    queryKey: ["poteto-mode", threadId],
    queryFn: async ({ signal }) => parsePotetoMode(await sdk.threads.getPluginMetadata({ threadId, signal })),
  });
  const mode = useQuery(query);
  const toggle = useMutation({
    mutationFn: (potetoMode: PotetoMode) =>
      sdk.threads.updatePluginMetadata({ threadId, set: { potetoMode } satisfies PotetoModeMetadata }),
    onSuccess: (metadata) => queryClient.setQueryData(query.queryKey, parsePotetoMode(metadata)),
    onError: (_error, potetoMode) => toast.error(`Couldn't turn poteto-mode ${potetoMode}. Try again.`),
  });

  useRealtime(POTETO_MODE_CHANNEL, (payload) => {
    const signal = potetoModeSignal.safeParse(payload);
    if (signal.success && signal.data.threadId === threadId) {
      void queryClient.invalidateQueries({ queryKey: query.queryKey });
    }
  });

  const connection = useRealtimeConnectionState();
  const disconnected = useRef(false);
  useEffect(() => {
    if (connection === "reconnecting") disconnected.current = true;
    if (connection === "connected" && disconnected.current) {
      disconnected.current = false;
      void queryClient.invalidateQueries({ queryKey: query.queryKey });
    }
  }, [connection, queryClient, threadId]);

  useEffect(() => {
    if (mode.error !== null) {
      console.warn("[pstack poteto-mode] couldn't read the thread's poteto-mode", { threadId, error: mode.error });
    }
  }, [mode.error, threadId]);

  if (!mode.data) return null;
  const chip = CHIPS[mode.data];

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          variant="ghost"
          aria-label={`poteto-mode ${mode.data}. Turn it ${chip.next}.`}
          aria-busy={toggle.isPending}
          disabled={toggle.isPending}
          onClick={() => toggle.mutate(chip.next)}
          className={cn(
            "h-7 rounded-full text-xs",
            isCompactViewport ? "w-7 p-0" : "px-2.5",
            chip.className,
          )}
        >
          {isCompactViewport ? <Icon name="Layers" aria-hidden /> : chip.text}
        </Button>
      </TooltipTrigger>
      <TooltipContent>Click to turn poteto-mode {chip.next}. Applies from the next message.</TooltipContent>
    </Tooltip>
  );
}
