import { definePluginApp } from "@get-bb/plugin-sdk/app";
import { PotetoModeAction } from "./src/ui/PotetoModeAction";

export default definePluginApp((app) => {
  app.slots.experimental_threadHeaderAction({ id: "poteto-mode", title: "poteto-mode", component: PotetoModeAction });
});
