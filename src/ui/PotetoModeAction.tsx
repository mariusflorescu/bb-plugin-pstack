import type { PluginThreadHeaderActionProps } from "@get-bb/plugin-sdk/app";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { TooltipProvider } from "../../components/ui/tooltip";
import { PotetoModeChip } from "./PotetoModeChip";

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
