#!/usr/bin/env python3
"""Read-only MCP for the Grey Conseil grok-library (transcripts + intel)."""

from __future__ import annotations

import json
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any

PROTOCOL = "2024-11-05"
MAX_SEARCH = 12
SNIPPET = 240


def library_root() -> Path:
    # Bundle ID / Application Support folder stays com.ftl1.greyeminence
    # so the meeting library and TCC grants are not orphaned.
    override = os.environ.get("GRAY_CONSEIL_LIBRARY")
    if override:
        return Path(override).expanduser()
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "com.ftl1.greyeminence"
        / "grok-library"
    )


def send(msg: dict[str, Any]) -> None:
    body = json.dumps(msg, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body)
    sys.stdout.buffer.flush()


def read_message() -> dict[str, Any] | None:
    headers: dict[str, str] = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        line = line.decode("utf-8")
        if line in ("\r\n", "\n"):
            break
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    length = int(headers.get("content-length") or "0")
    if length <= 0:
        return None
    raw = sys.stdin.buffer.read(length)
    return json.loads(raw.decode("utf-8"))


def load_index(root: Path) -> dict[str, Any]:
    path = root / "index.json"
    if not path.exists():
        return {"meetings": [], "meetingCount": 0, "error": "library not built yet — open Grey Conseil once"}
    return json.loads(path.read_text(encoding="utf-8"))


def meeting_dir(root: Path, meeting_id: str) -> Path:
    return root / "meetings" / meeting_id


def read_file(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def ensure_fts(root: Path) -> sqlite3.Connection:
    db_path = root / "search.sqlite"
    index_path = root / "index.json"
    need = True
    if db_path.exists() and index_path.exists():
        need = db_path.stat().st_mtime < index_path.stat().st_mtime
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    if not need:
        try:
            conn.execute("SELECT id FROM meetings_fts LIMIT 1")
            return conn
        except sqlite3.Error:
            need = True
    conn.execute("DROP TABLE IF EXISTS meetings_fts")
    conn.execute(
        """CREATE VIRTUAL TABLE meetings_fts USING fts5(
            id UNINDEXED, title, series, speakers, transcript, intel, actions
        )"""
    )
    index = load_index(root)
    for rec in index.get("meetings") or []:
        mid = rec.get("id") or ""
        folder = meeting_dir(root, mid)
        transcript = read_file(folder / "transcript.md")
        intel = read_file(folder / "intel.md")
        meta = json.loads(read_file(folder / "meta.json") or "{}")
        actions = "\n".join(
            a.get("text") or ""
            for a in (meta.get("actions") or rec.get("actions") or [])
        )
        conn.execute(
            "INSERT INTO meetings_fts (id, title, series, speakers, transcript, intel, actions) VALUES (?,?,?,?,?,?,?)",
            (
                mid,
                rec.get("title") or "",
                rec.get("series") or "",
                " ".join(rec.get("speakers") or []),
                transcript,
                intel,
                actions,
            ),
        )
    conn.commit()
    return conn


def snippet(text: str, query: str) -> str:
    if not text:
        return ""
    lower = text.lower()
    q = query.lower().strip()
    idx = lower.find(q) if q else -1
    if idx < 0:
        return text[:SNIPPET].replace("\n", " ")
    start = max(0, idx - 80)
    chunk = text[start : start + SNIPPET].replace("\n", " ")
    return ("…" if start else "") + chunk


def filter_meetings(index: dict[str, Any], args: dict[str, Any]) -> list[dict[str, Any]]:
    meetings = list(index.get("meetings") or [])
    series = (args.get("series") or "").strip().lower()
    speaker = (args.get("speaker") or "").strip().lower()
    since = (args.get("since") or "").strip()
    until = (args.get("until") or "").strip()
    out = []
    for rec in meetings:
        if series and series not in (rec.get("series") or "").lower() and series not in (rec.get("title") or "").lower():
            continue
        if speaker:
            names = " ".join(rec.get("speakers") or []).lower()
            if speaker not in names:
                continue
        date = rec.get("date") or ""
        if since and date < since:
            continue
        if until and date > until:
            continue
        out.append(rec)
    return out


def tool_list_meetings(args: dict[str, Any]) -> dict[str, Any]:
    root = library_root()
    index = load_index(root)
    if index.get("error"):
        return index
    rows = filter_meetings(index, args)
    limit = min(int(args.get("limit") or 20), 40)
    offset = max(int(args.get("offset") or 0), 0)
    slice_ = rows[offset : offset + limit]
    return {
        "total": len(rows),
        "offset": offset,
        "meetings": [
            {
                "id": r.get("id"),
                "title": r.get("title"),
                "date": r.get("date"),
                "duration": r.get("duration"),
                "series": r.get("series"),
                "speakers": r.get("speakers"),
                "openActionCount": r.get("openActionCount"),
            }
            for r in slice_
        ],
    }


def tool_search(args: dict[str, Any]) -> dict[str, Any]:
    query = (args.get("query") or "").strip()
    if not query:
        return {"error": "query is required"}
    root = library_root()
    index = load_index(root)
    if index.get("error"):
        return index
    by_id = {m["id"]: m for m in index.get("meetings") or [] if m.get("id")}
    try:
        conn = ensure_fts(root)
        fts_q = " ".join(w + "*" if w.isalnum() else w for w in query.split())
        rows = conn.execute(
            "SELECT id, snippet(meetings_fts, 4, '', '', ' … ', 12) AS snip FROM meetings_fts WHERE meetings_fts MATCH ? LIMIT ?",
            (fts_q, MAX_SEARCH),
        ).fetchall()
    except sqlite3.Error:
        rows = []
        q = query.lower()
        for rec in index.get("meetings") or []:
            folder = meeting_dir(root, rec["id"])
            blob = (
                (rec.get("title") or "")
                + " "
                + (rec.get("series") or "")
                + " "
                + read_file(folder / "transcript.md")
                + " "
                + read_file(folder / "intel.md")
            ).lower()
            if q in blob:
                rows.append({"id": rec["id"], "snip": snippet(blob, query)})
            if len(rows) >= MAX_SEARCH:
                break
    hits = []
    speaker = (args.get("speaker") or "").strip().lower()
    series = (args.get("series") or "").strip().lower()
    for row in rows:
        mid = row["id"] if not isinstance(row, sqlite3.Row) else row["id"]
        rec = by_id.get(mid)
        if not rec:
            continue
        if series and series not in (rec.get("series") or "").lower() and series not in (rec.get("title") or "").lower():
            continue
        if speaker and speaker not in " ".join(rec.get("speakers") or []).lower():
            continue
        snip = row["snip"] if not isinstance(row, sqlite3.Row) else row["snip"]
        hits.append(
            {
                "id": rec.get("id"),
                "title": rec.get("title"),
                "date": rec.get("date"),
                "series": rec.get("series"),
                "speakers": rec.get("speakers"),
                "snippet": (snip or "")[:SNIPPET],
            }
        )
    return {"query": query, "hits": hits}


def tool_get_transcript(args: dict[str, Any]) -> dict[str, Any]:
    mid = (args.get("id") or "").strip()
    if not mid:
        return {"error": "id is required"}
    root = library_root()
    rec = next((m for m in load_index(root).get("meetings") or [] if m.get("id") == mid), None)
    text = read_file(meeting_dir(root, mid) / "transcript.md")
    speaker = (args.get("speaker") or "").strip().lower()
    if speaker and text:
        kept = []
        block: list[str] = []
        keep = False
        for line in text.splitlines():
            if line.startswith("**"):
                if block and keep:
                    kept.extend(block)
                block = [line]
                keep = speaker in line.lower()
            else:
                block.append(line)
        if block and keep:
            kept.extend(block)
        text = "\n".join(kept)
    max_chars = int(args.get("max_chars") or 16000)
    truncated = len(text) > max_chars
    return {
        "id": mid,
        "title": rec.get("title") if rec else None,
        "date": rec.get("date") if rec else None,
        "truncated": truncated,
        "transcript": text[:max_chars],
    }


def tool_get_intel(args: dict[str, Any]) -> dict[str, Any]:
    mid = (args.get("id") or "").strip()
    if not mid:
        return {"error": "id is required"}
    root = library_root()
    rec = next((m for m in load_index(root).get("meetings") or [] if m.get("id") == mid), None)
    text = read_file(meeting_dir(root, mid) / "intel.md")
    max_chars = int(args.get("max_chars") or 12000)
    return {
        "id": mid,
        "title": rec.get("title") if rec else None,
        "date": rec.get("date") if rec else None,
        "series": rec.get("series") if rec else None,
        "speakers": rec.get("speakers") if rec else None,
        "purpose": rec.get("purpose") if rec else None,
        "truncated": len(text) > max_chars,
        "intel": text[:max_chars],
    }


def tool_get_actions(args: dict[str, Any]) -> dict[str, Any]:
    root = library_root()
    index = load_index(root)
    if index.get("error"):
        return index
    assignee = (args.get("assignee") or "").strip().lower()
    series = (args.get("series") or "").strip().lower()
    open_only = bool(args.get("open_only", True))
    items = []
    for rec in filter_meetings(index, {"series": series} if series else {}):
        meta_path = meeting_dir(root, rec["id"]) / "meta.json"
        meta = json.loads(read_file(meta_path) or "{}")
        for action in meta.get("actions") or rec.get("actions") or []:
            if open_only and action.get("isCompleted"):
                continue
            who = (action.get("assignee") or "").lower()
            text = action.get("text") or ""
            if assignee and assignee not in who and assignee not in text.lower():
                continue
            items.append(
                {
                    "meetingId": rec.get("id"),
                    "title": rec.get("title"),
                    "date": rec.get("date"),
                    "text": text,
                    "assignee": action.get("assignee"),
                    "sourceQuote": action.get("sourceQuote"),
                }
            )
            if len(items) >= 40:
                break
        if len(items) >= 40:
            break
    return {"count": len(items), "actions": items}


TOOLS = {
    "search_meetings": {
        "description": "Search Grey Conseil transcripts and intel (full archive). Returns ids + snippets. Then call get_transcript or get_intel.",
        "schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Keywords, names, or phrases"},
                "speaker": {"type": "string"},
                "series": {"type": "string", "description": "e.g. Weekly Standup"},
            },
            "required": ["query"],
        },
        "fn": tool_search,
    },
    "list_meetings": {
        "description": "List Grey Conseil meetings newest first. Filter by series, speaker, since/until ISO dates.",
        "schema": {
            "type": "object",
            "properties": {
                "series": {"type": "string"},
                "speaker": {"type": "string"},
                "since": {"type": "string"},
                "until": {"type": "string"},
                "limit": {"type": "integer"},
                "offset": {"type": "integer"},
            },
        },
        "fn": tool_list_meetings,
    },
    "get_transcript": {
        "description": "Fetch stored transcript for one meeting id from search/list.",
        "schema": {
            "type": "object",
            "properties": {
                "id": {"type": "string"},
                "speaker": {"type": "string"},
                "max_chars": {"type": "integer"},
            },
            "required": ["id"],
        },
        "fn": tool_get_transcript,
    },
    "get_intel": {
        "description": "Fetch stored meeting intelligence (summary, actions, questions, topics) for one meeting id.",
        "schema": {
            "type": "object",
            "properties": {
                "id": {"type": "string"},
                "max_chars": {"type": "integer"},
            },
            "required": ["id"],
        },
        "fn": tool_get_intel,
    },
    "get_actions": {
        "description": "List stored action items across meetings. open_only defaults true.",
        "schema": {
            "type": "object",
            "properties": {
                "assignee": {"type": "string"},
                "series": {"type": "string"},
                "open_only": {"type": "boolean"},
            },
        },
        "fn": tool_get_actions,
    },
}


def tools_list() -> list[dict[str, Any]]:
    return [
        {
            "name": name,
            "description": spec["description"],
            "inputSchema": spec["schema"],
        }
        for name, spec in TOOLS.items()
    ]


def handle(msg: dict[str, Any]) -> None:
    method = msg.get("method")
    msg_id = msg.get("id")
    if method == "initialize":
        send(
            {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "protocolVersion": PROTOCOL,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "grey-conseil", "version": "1.0.0"},
                },
            }
        )
        return
    if method == "notifications/initialized" or method == "initialized":
        return
    if method == "tools/list":
        send({"jsonrpc": "2.0", "id": msg_id, "result": {"tools": tools_list()}})
        return
    if method == "tools/call":
        params = msg.get("params") or {}
        name = params.get("name")
        args = params.get("arguments") or {}
        spec = TOOLS.get(name)
        if not spec:
            send(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {"code": -32601, "message": f"unknown tool {name}"},
                }
            )
            return
        result = spec["fn"](args)
        send(
            {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}]
                },
            }
        )
        return
    if method == "ping":
        send({"jsonrpc": "2.0", "id": msg_id, "result": {}})
        return
    if msg_id is not None:
        send(
            {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": -32601, "message": f"unknown method {method}"},
            }
        )


def main() -> None:
    while True:
        msg = read_message()
        if msg is None:
            break
        handle(msg)


if __name__ == "__main__":
    main()
