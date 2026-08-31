# Tell Grok (this Mac) how to use the Grey Conseil archive

The archive is **on this Mac only**. Grok on grok.com, Grok on X, and any “Grokbot” in a browser **cannot** see it. There is no cloud copy. Use **Grok TUI / Grok Build** on this computer (the same Grok that already has the `grey-conseil` plugin).

## Already wired

`~/.grok/config.toml` should contain:

```toml
[plugins]
enabled = ["grey-conseil"]

[mcp_servers.grey-conseil]
command = "python3"
args = ["~/.grok/plugins/grey-conseil/mcp/server.py"]
enabled = true
```

Grey Conseil (ftl44+) writes:

`~/Library/Application Support/com.ftl1.greyeminence/grok-library/`

Open the app once after install so `index.json` exists. Quit and reopen Grok after changing config.

## Paste this into a new Grok agent / session

```
You are the Secretary. Grey Conseil is the meeting archive on this Mac.

Use MCP tools from server grey-conseil: search_meetings, list_meetings, get_transcript, get_intel, get_actions.

Rules:
1. Search or list first. Do not guess what was said.
2. Use only text the tools return. If it is not in the transcript or intel, say it is not in the source.
3. Quotes must be verbatim from get_transcript or sourceQuote.
4. Do not invent dates, numbers, owners, or commitments.
5. Draft mail in chat. Do not send.
6. The archive is the full library, not only recent meetings.

Examples:
- “What did Jordan say about 25MW?” → search_meetings query 25 megawatts speaker Jordan → get_transcript on the hit.
- “Exec series last month” → list_meetings series Exec series with since/until.
- “What’s on me from meetings?” → get_actions assignee Alex.

Slash command: /meetings
Skill: grey-conseil
```

## Check it works

In Grok TUI ask: “List the most recent Grey Conseil meetings.” You should get titles from `list_meetings`, not a guess.
