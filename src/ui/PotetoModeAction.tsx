import type { PluginThreadHeaderActionProps } from "@get-bb/plugin-sdk/app";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { TooltipProvider } from "../../components/ui/tooltip";
import { PotetoModeChip } from "./PotetoModeChip";

// One client for every header, so two panes showing the same thread share its cache entry.
const queryClient = new QueryClient();

export function PotetoModeAction(props: PluginThreadHeaderActionProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider delayDuration={300}>
        <PotetoModeChip {...props} />
      </TooltipProvider>
    </QueryClientProvider>
  );
}
