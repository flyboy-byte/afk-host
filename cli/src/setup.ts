/// `afk setup` command — auto-detect and configure agent tool hooks.
/// Patches tool configs to call `afk notify` on relevant events.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

interface Tool {
  name: string;
  slug: string;
  detect: () => boolean;
  setup: () => void;
}

const home = homedir();

/** Resolve the absolute path to the `afk` CLI script. */
function getAfkPath(): string {
  // Use the directory this source file lives in to find the CLI root
  const cliDir = dirname(dirname(decodeURIComponent(new URL(import.meta.url).pathname)));
  return join(cliDir, "afk");
}

// ── Claude Code ──────────────────────────────────────────────

function detectClaudeCode(): boolean {
  return existsSync(join(home, ".claude"));
}

function setupClaudeCode(): void {
  const settingsPath = join(home, ".claude", "settings.json");
  let settings: Record<string, any> = {};

  if (existsSync(settingsPath)) {
    try {
      settings = JSON.parse(readFileSync(settingsPath, "utf-8"));
    } catch {
      console.error(`  ✗ Failed to parse ${settingsPath}`);
      return;
    }
  }

  const afk = getAfkPath();
  const hooks = settings.hooks ?? {};

  const stopCommand = `${afk} notify 'Claude Code: response ready'`;
  const notificationCommand = `${afk} notify 'Claude Code: needs permission'`;

  const upsertAfkHook = (eventName: string, entries: any[] | undefined, command: string) => {
    const list = [...(entries ?? [])];
    for (const entry of list) {
      const commandHook = entry?.hooks?.find((h: any) => h.command?.includes("afk notify"));
      if (commandHook) {
        const previous = String(commandHook.command ?? "");
        if (previous != command) {
          console.warn(
            `  ⚠ Claude Code ${eventName}: replacing existing afk notify hook\n` +
              `    old: ${previous}\n` +
              `    new: ${command}`,
          );
          commandHook.type = "command";
          commandHook.command = command;
        }
        return list;
      }
    }

    list.push({
      matcher: "",
      hooks: [{ type: "command", command }],
    });
    return list;
  };

  hooks.Stop = upsertAfkHook("Stop", hooks.Stop, stopCommand);
  hooks.Notification = upsertAfkHook("Notification", hooks.Notification, notificationCommand);

  settings.hooks = hooks;
  writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
  console.log("  ✓ Claude Code — added hooks to ~/.claude/settings.json");
}

// ── Pi Coding Agent ─────────────────────────────────────────

function detectPi(): boolean {
  return existsSync(join(home, ".pi"));
}

function setupPi(): void {
  const extDir = join(home, ".pi", "agent", "extensions");
  const extPath = join(extDir, "afk-notify.ts");

  mkdirSync(extDir, { recursive: true });

  const content = `/// AFK notification bridge for Pi Coding Agent.
/// Sends a local socket notification when the agent finishes a response.

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { connect } from "node:net";
import { tmpdir } from "node:os";

const DEFAULT_SOCKET_NAMESPACE = "app.afkdev.macos";
const DEV_SOCKET_NAMESPACE = "app.afkdev.macos.dev";

function getSocketBaseDir(): string {
  const xdgRuntime = process.env.XDG_RUNTIME_DIR;
  if (xdgRuntime) return \`\${xdgRuntime}/afk\`;
  return \`\${tmpdir()}/afk\`;
}

function socketPathForNamespace(namespace: string): string {
  return \`\${getSocketBaseDir()}/\${namespace}.sock\`;
}

function getSocketCandidates(): string[] {
  const requestedNamespace = process.env.AFK_SOCKET_NAMESPACE?.trim();
  if (requestedNamespace) {
    return [socketPathForNamespace(requestedNamespace)];
  }
  return [
    socketPathForNamespace(DEFAULT_SOCKET_NAMESPACE),
    socketPathForNamespace(DEV_SOCKET_NAMESPACE),
    \`\${getSocketBaseDir()}/afk.sock\`, // legacy
  ];
}

function notify(message: string) {
  const payload = JSON.stringify({
    type: "notify",
    message,
    ts: new Date().toISOString(),
  }) + "\\n";

  const candidates = getSocketCandidates();
  const tryNext = (index: number) => {
    if (index >= candidates.length) return;
    const sock = connect(candidates[index]);
    sock.once("error", () => tryNext(index + 1));
    sock.once("connect", () => sock.end(payload));
  };

  tryNext(0);
}

export default function (pi: ExtensionAPI) {
  pi.on("agent_end", async () => {
    notify("Pi: response ready");
  });
}
`;

  if (existsSync(extPath)) {
    const previous = readFileSync(extPath, "utf-8");
    if (previous !== content) {
      console.warn(
        `  ⚠ Pi: replacing existing extension at ~/.pi/agent/extensions/afk-notify.ts`,
      );
    }
  }

  writeFileSync(extPath, content);
  console.log("  ✓ Pi Coding Agent — installed ~/.pi/agent/extensions/afk-notify.ts");
}

// ── Tool Registry ────────────────────────────────────────────

const tools: Tool[] = [
  { name: "Claude Code", slug: "claude-code", detect: detectClaudeCode, setup: setupClaudeCode },
  { name: "Pi Coding Agent", slug: "pi", detect: detectPi, setup: setupPi },
  // More tools added here incrementally
];

// ── Main ─────────────────────────────────────────────────────

export async function setup(toolSlug?: string): Promise<void> {
  if (toolSlug) {
    // Set up a specific tool
    const tool = tools.find((t) => t.slug === toolSlug);
    if (!tool) {
      console.error(`Unknown tool: ${toolSlug}`);
      console.error(`Available: ${tools.map((t) => t.slug).join(", ")}`);
      process.exit(1);
    }
    if (!tool.detect()) {
      console.error(`${tool.name} not detected on this system.`);
      process.exit(1);
    }
    tool.setup();
    return;
  }

  // Auto-detect all tools
  const detected = tools.filter((t) => t.detect());
  const notFound = tools.filter((t) => !t.detect());

  console.log("Detected coding tools:");
  for (const t of detected) console.log(`  ✓ ${t.name}`);
  for (const t of notFound) console.log(`  ✗ ${t.name} (not found)`);
  console.log();

  if (detected.length === 0) {
    console.log("No supported tools detected.");
    return;
  }

  for (const t of detected) {
    t.setup();
  }

  console.log("\nDone. Notifications will appear on your phone when agents finish tasks.");
}
