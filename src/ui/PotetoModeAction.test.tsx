// @vitest-environment jsdom
import type { PluginBoundThreadsArea, PluginRealtimeConnectionState } from "@get-bb/plugin-sdk/app";
import { loadPluginApp, renderSlot, type RenderedSlot } from "@get-bb/plugin-sdk/testing/app";
import { act, cleanup, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Toaster } from "sonner";
import { afterEach, expect, it, vi } from "vitest";
import { POTETO_MODE_CHANNEL } from "../poteto-mode";

type Metadata = Awaited<ReturnType<PluginBoundThreadsArea["getPluginMetadata"]>>;
type Threads = Pick<PluginBoundThreadsArea, "getPluginMetadata" | "updatePluginMetadata">;

globalThis.ResizeObserver ??= class {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
};

const app = await loadPluginApp(() => import("../../app"));
const action = app.threadHeaderActions.find((registration) => registration.id === "poteto-mode");
if (action === undefined) throw new Error("app.tsx registers no poteto-mode header action");
const { component } = action;

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

function backend(metadata: Record<string, Metadata>) {
  const threads: Threads = {
    getPluginMetadata: async ({ threadId }) => metadata[threadId] ?? {},
    updatePluginMetadata: async ({ threadId, set }) => {
      const next = { ...metadata[threadId], ...set };
      metadata[threadId] = next;
      return next;
    },
  };
  return { metadata, threads };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((settle) => {
    resolve = settle;
  });
  return { promise, resolve };
}

function renderChip({
  threadId,
  threads,
  isCompactViewport = false,
  realtimeConnectionState,
}: {
  threadId: string;
  threads: Threads;
  isCompactViewport?: boolean;
  realtimeConnectionState?: PluginRealtimeConnectionState;
}) {
  return renderSlot(
    { component },
    { threadId, projectId: "proj_pstack", isCompactViewport },
    { sdk: { threads }, realtimeConnectionState },
  );
}

const findChip = (slot: RenderedSlot, name: string) => within(slot.container).findByRole("button", { name });
const reads = (slot: RenderedSlot) =>
  slot.inspection.sdkCalls.filter((call) => call.method === "threads.getPluginMetadata").length;

it("shows the on and off chips, and nothing for a thread that never enabled the mode", async () => {
  const { threads } = backend({ thr_on: { potetoMode: "on" }, thr_off: { potetoMode: "off" } });
  const never = renderChip({ threadId: "thr_never", threads });
  const on = renderChip({ threadId: "thr_on", threads });
  const off = renderChip({ threadId: "thr_off", threads });

  expect((await findChip(on, "poteto-mode on. Turn it off.")).textContent).toBe("poteto-mode");
  expect((await findChip(off, "poteto-mode off. Turn it on.")).textContent).toBe("poteto-mode off");
  expect(never.container.innerHTML).toBe("");
});

it("renders nothing while the first read loads, since most threads never enable the mode", async () => {
  const read = deferred<Metadata>();
  const slot = renderChip({
    threadId: "thr_loading",
    threads: { ...backend({}).threads, getPluginMetadata: () => read.promise },
  });

  await waitFor(() => expect(reads(slot)).toBe(1));
  expect(slot.container.innerHTML).toBe("");

  await act(async () => read.resolve({ potetoMode: "on" }));
  expect((await findChip(slot, "poteto-mode on. Turn it off.")).textContent).toBe("poteto-mode");
});

it("turns the mode off from the on chip and back on from the off chip", async () => {
  const user = userEvent.setup();
  const server = backend({ thr_toggle: { potetoMode: "on" } });
  const slot = renderChip({ threadId: "thr_toggle", threads: server.threads });

  await user.click(await findChip(slot, "poteto-mode on. Turn it off."));
  const off = await findChip(slot, "poteto-mode off. Turn it on.");
  expect(off.textContent).toBe("poteto-mode off");
  expect(server.metadata.thr_toggle).toEqual({ potetoMode: "off" });

  await user.click(off);
  expect((await findChip(slot, "poteto-mode on. Turn it off.")).textContent).toBe("poteto-mode");
  expect(server.metadata.thr_toggle).toEqual({ potetoMode: "on" });
});

it("disables the chip and marks it busy while the write is pending", async () => {
  const user = userEvent.setup();
  const write = deferred<Metadata>();
  const slot = renderChip({
    threadId: "thr_pending",
    threads: { ...backend({ thr_pending: { potetoMode: "on" } }).threads, updatePluginMetadata: () => write.promise },
  });

  const chip = await findChip(slot, "poteto-mode on. Turn it off.");
  await user.click(chip);
  expect(chip.getAttribute("aria-busy")).toBe("true");
  expect(chip).toHaveProperty("disabled", true);

  await act(async () => write.resolve({ potetoMode: "off" }));
  const off = await findChip(slot, "poteto-mode off. Turn it on.");
  expect(off.getAttribute("aria-busy")).toBe("false");
  expect(off).toHaveProperty("disabled", false);
});

it("keeps the old state and shows a toast when the write fails", async () => {
  const user = userEvent.setup();
  render(<Toaster />);
  const server = backend({ thr_failed_write: { potetoMode: "on" } });
  const slot = renderChip({
    threadId: "thr_failed_write",
    threads: {
      ...server.threads,
      updatePluginMetadata: async () => {
        throw new Error("metadata write rejected");
      },
    },
  });

  await user.click(await findChip(slot, "poteto-mode on. Turn it off."));
  expect((await screen.findByText(/^Couldn't turn poteto-mode/)).textContent).toBe(
    "Couldn't turn poteto-mode off. Try again.",
  );
  const chip = await findChip(slot, "poteto-mode on. Turn it off.");
  expect(chip.textContent).toBe("poteto-mode");
  expect(chip).toHaveProperty("disabled", false);
  expect(server.metadata.thr_failed_write).toEqual({ potetoMode: "on" });
});

it("renders nothing and logs the thread id when the read fails", async () => {
  vi.useFakeTimers();
  const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
  const error = new Error("metadata read rejected");
  const slot = renderChip({
    threadId: "thr_failed_read",
    threads: {
      ...backend({}).threads,
      getPluginMetadata: async () => {
        throw error;
      },
    },
  });

  await act(() => vi.advanceTimersByTimeAsync(60_000));
  expect(warn.mock.calls).toEqual([
    ["[pstack poteto-mode] couldn't read the thread's poteto-mode", { threadId: "thr_failed_read", error }],
  ]);
  expect(slot.container.innerHTML).toBe("");
});

it("refetches when the server signals this thread and ignores other threads", async () => {
  const server = backend({});
  const slot = renderChip({ threadId: "thr_signal", threads: server.threads });
  await waitFor(() => expect(reads(slot)).toBe(1));

  server.metadata.thr_signal = { potetoMode: "on" };
  await slot.behavior.emitRealtime(POTETO_MODE_CHANNEL, { threadId: "thr_other" });
  expect(reads(slot)).toBe(1);

  await slot.behavior.emitRealtime(POTETO_MODE_CHANNEL, { threadId: "thr_signal" });
  expect((await findChip(slot, "poteto-mode on. Turn it off.")).textContent).toBe("poteto-mode");
});

it("refetches when the realtime connection comes back, but not on the first connection", async () => {
  const server = backend({});
  const slot = renderChip({ threadId: "thr_reconnect", threads: server.threads, realtimeConnectionState: "connecting" });
  await waitFor(() => expect(reads(slot)).toBe(1));

  server.metadata.thr_reconnect = { potetoMode: "on" };
  await slot.behavior.setRealtimeConnectionState("connected");
  expect(reads(slot)).toBe(1);

  await slot.behavior.setRealtimeConnectionState("reconnecting");
  await slot.behavior.setRealtimeConnectionState("connected");
  expect((await findChip(slot, "poteto-mode on. Turn it off.")).textContent).toBe("poteto-mode");
});

it("collapses to an icon-sized control named by its state on compact viewports", async () => {
  const slot = renderChip({
    threadId: "thr_compact",
    threads: backend({ thr_compact: { potetoMode: "off" } }).threads,
    isCompactViewport: true,
  });

  const chip = await findChip(slot, "poteto-mode off. Turn it on.");
  expect(chip.textContent).toBe("");
  expect(chip.querySelector("[data-icon]")?.getAttribute("data-icon")).toBe("Layers");
});

it("explains in a tooltip that a switch waits for the thread's next session rebuild", async () => {
  const user = userEvent.setup();
  const on = renderChip({ threadId: "thr_tooltip_on", threads: backend({ thr_tooltip_on: { potetoMode: "on" } }).threads });

  await findChip(on, "poteto-mode on. Turn it off.");
  await user.tab();
  expect((await screen.findByRole("tooltip")).textContent).toBe(
    "Click to turn poteto-mode off at this thread's next session rebuild, such as a BB restart. To stop sooner, tell the agent to stop poteto-mode.",
  );
  cleanup();

  const off = renderChip({ threadId: "thr_tooltip_off", threads: backend({ thr_tooltip_off: { potetoMode: "off" } }).threads });
  await findChip(off, "poteto-mode off. Turn it on.");
  await user.tab();
  expect((await screen.findByRole("tooltip")).textContent).toBe(
    "Click to turn poteto-mode on at this thread's next session rebuild, such as a BB restart.",
  );
});
