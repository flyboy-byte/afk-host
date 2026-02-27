/// AFK CLI — bridges AI coding agents to the AFK mobile client.
/// Entry point for all subcommands (notify, setup, status, etc.)

import { notify } from "./notify.ts";
import { setup } from "./setup.ts";
import { status } from "./status.ts";

const args = process.argv.slice(2);
const command = args[0];

switch (command) {
  case "notify": {
    const message = args.slice(1).join(" ");
    if (!message) {
      console.error("Usage: afk notify <message>");
      process.exit(1);
    }
    await notify(message);
    break;
  }

  case "setup": {
    const toolSlug = args[1]; // optional: specific tool
    await setup(toolSlug);
    break;
  }

  case "status":
    await status();
    break;

  case undefined:
  case "--help":
  case "-h":
    console.log(`afk — bridge AI coding agents to AFK mobile client

Commands:
  notify <message>   Send a notification to your phone
  setup [tool]       Auto-detect and configure tool hooks
  status             Check if AFK host is running

Examples:
  afk notify "Claude Code: task complete"
  afk setup
  afk setup claude-code
  afk status`);
    break;

  default:
    console.error(`Unknown command: ${command}\nRun 'afk --help' for usage.`);
    process.exit(1);
}
