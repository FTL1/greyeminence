# Grey Conseil Grok plugin

Read-only access to the meeting library for the **local** Secretary (Grok TUI / Grok Build on this Mac). grok.com and Grok on X cannot see this folder.

Install (auto-trusted):

```
rsync -a Tools/grey-conseil-grok/ ~/.grok/plugins/grey-conseil/
```

Grey Conseil 0.28.4-ftl44+ writes:

`~/Library/Application Support/com.ftl1.greyeminence/grok-library/`

That path is the installed bundle ID on purpose (library + TCC). Do not rename it without a migrator. Override with `GRAY_CONSEIL_LIBRARY` if you need a different tree.

Paste-ready agent prompt: [AGENT.md](AGENT.md)

MCP tools: `search_meetings`, `list_meetings`, `get_transcript`, `get_intel`, `get_actions`.
