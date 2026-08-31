---
name: grey-conseil
description: Search Grey Conseil meeting transcripts and intelligence. Use when the user asks what was said in a call, a series (Exec series), a speaker, past meetings, action items from meetings, or needs facts from meetings to draft a message or proposal.
---

# Grey Conseil (Secretary source)

Grey Conseil is the meeting library on this Mac. You search it with MCP tools `grey-conseil__search_meetings`, `list_meetings`, `get_transcript`, `get_intel`, `get_actions`.

## Rules

1. Search or list first. Do not guess meeting content.
2. Use only text the tools return. If it is not in the transcript or intel, say it is not in the source.
3. Quotes must be verbatim from `get_transcript` or `sourceQuote`.
4. Do not invent dates, numbers, owners, or commitments.
5. Draft mail or messages in the chat. Do not send.
6. The archive is the full library, not only recent meetings.

## How to look things up

- "What did Jordan say about 25MW?" → `search_meetings` query `25 megawatts` speaker `Jordan` → `get_transcript` on the hit.
- "Exec series last month" → `list_meetings` series `Exec series` with since/until, or `search_meetings` series `Exec series`.
- "What's on me from meetings?" → `get_actions` assignee `Alex` (or Me).
- Then Outlook/calendar if the user also wants mail or schedule. Meetings and mail are separate sources; say which one a fact came from.
