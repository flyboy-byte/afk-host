/// `afk status` command — checks if the AFK host is listening on the socket.

import { sendToSocket, getSocketPath } from "./socket.ts";

export async function status(): Promise<void> {
  const socketPath = getSocketPath();
  const namespace = process.env.AFK_SOCKET_NAMESPACE?.trim();
  console.log(`Socket: ${socketPath}`);
  if (namespace) {
    console.log(`Namespace: ${namespace} (from AFK_SOCKET_NAMESPACE)`);
  }

  try {
    await sendToSocket({ type: "ping" });
    console.log("Status: host is running ✓");
  } catch {
    console.log("Status: host is not running ✗");
    process.exitCode = 1;
  }
}
