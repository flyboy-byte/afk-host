/// `afk notify` command — sends a notification string to the AFK host.
/// Silent failure if host is not running (never blocks the agent).

import { sendToSocket } from "./socket.ts";

export async function notify(message: string): Promise<void> {
  try {
    await sendToSocket({
      type: "notify",
      message,
      ts: new Date().toISOString(),
    });
  } catch {
    // Host not running or socket error — exit silently.
    // We never block the agent.
  }
}
