/// Unix domain socket client for communicating with the AFK host app.
/// Resolves a namespaced socket path and provides send-and-disconnect helper.
///
/// Namespace resolution order:
///   1. AFK_SOCKET_NAMESPACE env var (explicit override)
///   2. .socket-namespace stamp file (set by the app's build phase when bundled)
///   3. Fallback candidates: production → dev → legacy

import { connect } from "node:net";
import { readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const DEFAULT_SOCKET_NAMESPACE = "app.afkdev.macos";
const DEV_SOCKET_NAMESPACE = "app.afkdev.macos.dev";

function getSocketBaseDir(): string {
  const xdgRuntime = process.env.XDG_RUNTIME_DIR;
  if (xdgRuntime) return `${xdgRuntime}/afk`;
  return `${tmpdir()}/afk`;
}

function socketPathForNamespace(namespace: string): string {
  return `${getSocketBaseDir()}/${namespace}.sock`;
}

function legacySocketPath(): string {
  return `${getSocketBaseDir()}/afk.sock`;
}

/**
 * Read the .socket-namespace stamp file placed by the build phase.
 * Returns the namespace if found next to this script, or undefined.
 */
function readStampedNamespace(): string | undefined {
  try {
    // Resolve relative to the CLI root (parent of src/)
    const cliDir = dirname(dirname(decodeURIComponent(new URL(import.meta.url).pathname)));
    const stampPath = join(cliDir, ".socket-namespace");
    if (existsSync(stampPath)) {
      const ns = readFileSync(stampPath, "utf-8").trim();
      if (ns) return ns;
    }
  } catch {}
  return undefined;
}

/** Resolve the effective namespace. */
function resolveNamespace(): string | undefined {
  return process.env.AFK_SOCKET_NAMESPACE?.trim() || readStampedNamespace();
}

/** Resolve the preferred socket path for status output and diagnostics. */
export function getSocketPath(): string {
  const ns = resolveNamespace();
  if (ns) return socketPathForNamespace(ns);
  return socketPathForNamespace(DEFAULT_SOCKET_NAMESPACE);
}

/** Candidate socket paths in priority order. */
function getSocketCandidates(): string[] {
  const ns = resolveNamespace();
  if (ns) {
    return [socketPathForNamespace(ns)];
  }

  return [
    socketPathForNamespace(DEFAULT_SOCKET_NAMESPACE),
    socketPathForNamespace(DEV_SOCKET_NAMESPACE),
    legacySocketPath(),
  ];
}

function sendToSingleSocket(socketPath: string, payload: Record<string, unknown>): Promise<void> {
  return new Promise((resolve, reject) => {
    const sock = connect(socketPath, () => {
      sock.end(JSON.stringify(payload) + "\n", () => resolve());
    });
    sock.on("error", (err) => reject(err));
    // Timeout after 2 seconds to avoid blocking the agent
    sock.setTimeout(2000, () => {
      sock.destroy();
      reject(new Error("Socket timeout"));
    });
  });
}

/**
 * Send a JSON message to the AFK host socket and disconnect.
 * Resolves when the message is flushed. Rejects on connection error.
 */
export async function sendToSocket(payload: Record<string, unknown>): Promise<void> {
  let lastError: unknown;

  for (const socketPath of getSocketCandidates()) {
    try {
      await sendToSingleSocket(socketPath, payload);
      return;
    } catch (err) {
      lastError = err;
    }
  }

  throw (lastError ?? new Error("No AFK socket candidates available"));
}
