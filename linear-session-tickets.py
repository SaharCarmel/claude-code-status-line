#!/usr/bin/python3
"""Find the Linear tickets a Claude Code session is about, with their status.

Run in the background by statusline-haiku-summary.sh. It scores every ticket
identifier in the session transcript (and its subagent transcripts) by how it
appears, adds the tickets Linear links to the session's PRs, fetches status and
parent for the winners in one GraphQL call, and writes one render-ready TSV
line per ticket to OUT:

    identifier  state  state-color  url  child-count  title

The highest-scoring ticket is the session's main ticket and is always shown as
itself. Of the others, two or more that share a parent are rolled up and shown
as that parent, with the number of them. Tickets scoring under a fifth of the
main ticket are dropped.

Signals and weights (a ticket needs THRESHOLD to be shown):
  branch   8  a git branch the session ran on names the ticket
  write    5  the session commented on, updated or attached to the ticket
  created  5  the session created the ticket
  human    6  the user typed the identifier in the first message, 3 later
  pr       4  Linear links the ticket to one of the session's PRs
              (1 when that PR is linked to more than 3 tickets: an umbrella PR)
  read     2  the session fetched the ticket
  child    2  the session created a sub-issue under the ticket
  prose    1  Claude named the ticket in its own text, at most 3 times

Usage: linear-session-tickets.py TRANSCRIPT OUT [--branch B] [--pr URL ...]
Needs LINEAR_API_KEY in the environment or exported in ~/.zshrc.
"""
import json
import os
import re
import sys
import time
import urllib.request
from collections import defaultdict

THRESHOLD = 5
W_BRANCH, W_WRITE, W_CREATED, W_HUMAN_FIRST, W_HUMAN = 8, 5, 5, 6, 3
W_PR, W_PR_UMBRELLA, W_READ, W_CHILD, W_PROSE, PROSE_CAP = 4, 1, 2, 2, 1, 3
MAX_CANDIDATES = 15
RELATIVE_CUTOFF = 5  # also drop tickets scoring under a fifth of the main one
WORKSPACE_CACHE = os.path.expanduser("~/.claude/linear_workspace.json")
WORKSPACE_TTL = 86400

WRITE_TOOLS = {"save_comment", "save_issue", "create_attachment", "create_attachment_from_upload",
               "share_issue", "delete_comment"}
READ_TOOLS = {"get_issue", "list_comments", "get_attachment", "extract_images", "get_issue_status"}
GQL_WRITES = ("commentCreate", "issueUpdate", "attachmentCreate", "attachmentLinkURL", "issueRelationCreate")
ISSUE_FIELDS = "identifier title url state { name color } parent { identifier title url state { name color } }"


def api_key():
    key = os.environ.get("LINEAR_API_KEY")
    if key:
        return key
    try:
        with open(os.path.expanduser("~/.zshrc")) as fh:
            # The last export wins, as it does in the shell
            found = re.findall(r"""^\s*export\s+LINEAR_API_KEY=["']?([^"'\s]+)""", fh.read(), re.M)
            return found[-1] if found else None
    except OSError:
        return None


def gql(key, query):
    req = urllib.request.Request("https://api.linear.app/graphql", data=json.dumps({"query": query}).encode(),
                                 headers={"Authorization": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp).get("data") or {}


def workspace(key):
    """Team keys and the workspace URL key, cached for a day."""
    try:
        if time.time() - os.path.getmtime(WORKSPACE_CACHE) < WORKSPACE_TTL:
            with open(WORKSPACE_CACHE) as fh:
                return json.load(fh)
    except (OSError, ValueError):
        pass
    data = gql(key, "{ organization { urlKey } teams { nodes { key } } }")
    ws = {"urlKey": data["organization"]["urlKey"], "keys": [t["key"] for t in data["teams"]["nodes"]]}
    with open(WORKSPACE_CACHE, "w") as fh:
        json.dump(ws, fh)
    return ws


def score_transcript(transcript, id_re, branches):
    ids = lambda text: {m.upper() for m in id_re.findall(text or "")}
    score = defaultdict(int)
    prose = defaultdict(int)

    def add(found, weight):
        for i in found:
            score[i] += weight

    files = [transcript]
    subdir = os.path.join(transcript[:-len(".jsonl")], "subagents")
    if os.path.isdir(subdir):
        files += [os.path.join(subdir, f) for f in os.listdir(subdir) if f.endswith(".jsonl")]

    for path in files:
        main_file = path == transcript
        pending = {}  # tool_use id -> "create" | "gql", to read results back
        first_human = True
        try:
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if main_file and '"gitBranch"' in line:
                    m = re.search(r'"gitBranch":"([^"]+)"', line)
                    if m and m.group(1) not in branches:
                        branches.append(m.group(1))
                if not (id_re.search(line) or "api.linear.app" in line or "_Linear__" in line
                        or (pending and '"tool_use_id"' in line)):
                    continue
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                kind = e.get("type")
                content = (e.get("message") or {}).get("content")
                if kind == "user" and isinstance(content, str):
                    if main_file and (e.get("origin") or {}).get("kind") == "human":
                        add(ids(content), W_HUMAN_FIRST if first_human else W_HUMAN)
                        first_human = False
                elif kind == "user" and isinstance(content, list):
                    for c in content:
                        how = pending.pop(c.get("tool_use_id"), None) if c.get("type") == "tool_result" else None
                        if not how:
                            continue
                        body = json.dumps(c.get("content"))
                        found = {x.upper() for x in re.findall(r'identifier\\*"\s*:\s*\\*"([A-Za-z0-9]+-[0-9]+)', body)
                                 if id_re.fullmatch(x)}
                        if "issueCreate" in body or how == "create":
                            add(found, W_CREATED)
                        elif any(w in body for w in GQL_WRITES):
                            add(found, W_WRITE)
                elif kind == "assistant" and isinstance(content, list):
                    for c in content:
                        if c.get("type") == "text" and main_file:
                            for i in ids(c.get("text")):
                                prose[i] += 1
                        elif c.get("type") == "tool_use":
                            name, inp = c.get("name", ""), c.get("input") or {}
                            if "Linear" in name:
                                tool = name.rsplit("__", 1)[-1]
                                own = ids(" ".join(str(inp.get(k, "")) for k in ("id", "issueId", "issue")))
                                if tool in WRITE_TOOLS:
                                    add(own, W_WRITE)
                                    add(ids(str(inp.get("parentId", ""))), W_CHILD)
                                    if tool == "save_issue" and not own:
                                        pending[c.get("id")] = "create"
                                elif tool in READ_TOOLS:
                                    add(own, W_READ)
                            elif name == "Bash" and "api.linear.app" in str(inp.get("command", "")):
                                cmd = inp["command"]
                                add(ids(cmd), W_WRITE if "mutation" in cmd else W_READ)
                                pending[c.get("id")] = "gql"

    for i, n in prose.items():
        score[i] += min(n, PROSE_CAP) * W_PROSE
    for b in branches:
        add(ids(b.replace("_", "-")), W_BRANCH)
    return score


def color(hexstr):
    m = re.fullmatch(r"#?([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})", hexstr or "")
    return ";".join(str(int(g, 16)) for g in m.groups()) if m else ""


def main():
    args = sys.argv[1:]
    transcript, out = args[0], args[1]
    branches, prs = [], []
    it = iter(args[2:])
    for a in it:
        if a == "--branch":
            b = next(it, "")
            if b:
                branches.append(b)
        elif a == "--pr":
            prs.append(next(it, ""))
    prs = [p for p in dict.fromkeys(prs) if p]

    key = api_key()
    if not key:
        return
    ws = workspace(key)
    id_re = re.compile(r"\b(?:%s)-[0-9]+\b" % "|".join(map(re.escape, ws["keys"])), re.I)
    score = score_transcript(transcript, id_re, branches)

    # One request: the strongest candidates, plus the tickets linked to each PR
    candidates = [i for i, s in sorted(score.items(), key=lambda kv: -kv[1]) if s >= W_READ][:MAX_CANDIDATES]
    parts = ['i%d: issue(id: "%s") { %s }' % (n, i, ISSUE_FIELDS) for n, i in enumerate(candidates)]
    parts += ['p%d: attachmentsForURL(url: %s) { nodes { issue { %s } } }' % (n, json.dumps(u), ISSUE_FIELDS)
              for n, u in enumerate(prs)]
    issues = {}
    if parts:
        # A deleted or inaccessible ticket fails only its own alias; keep the rest
        req = urllib.request.Request("https://api.linear.app/graphql",
                                     data=json.dumps({"query": "{ %s }" % " ".join(parts)}).encode(),
                                     headers={"Authorization": key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.load(resp).get("data") or {}
        except urllib.error.HTTPError as err:
            data = json.load(err).get("data") or {}
        for alias, val in data.items():
            if not val:
                continue
            if alias.startswith("i"):
                issues[val["identifier"]] = val
            else:
                linked = [n["issue"] for n in val["nodes"] if n.get("issue")]
                for iss in linked:
                    issues.setdefault(iss["identifier"], iss)
                    score[iss["identifier"]] += W_PR if len(linked) <= 3 else W_PR_UMBRELLA

    ranked = sorted(issues, key=lambda i: -score[i])
    cutoff = max(THRESHOLD, score[ranked[0]] // RELATIVE_CUTOFF) if ranked else THRESHOLD
    chosen = [issues[i] for i in ranked if score[i] >= cutoff]

    # The session's main ticket is shown as itself. The others roll up: two or
    # more that share a parent are shown as that parent.
    by_parent = defaultdict(list)
    for iss in chosen[1:]:
        if iss.get("parent"):
            by_parent[iss["parent"]["identifier"]].append(iss)
    rows, seen = [], set()
    for n, iss in enumerate(chosen):
        parent = iss.get("parent")
        if n > 0 and parent and len(by_parent[parent["identifier"]]) >= 2:
            shown, count = parent, len(by_parent[parent["identifier"]])
        else:
            shown, count = iss, 0
        if shown["identifier"] in seen:
            continue
        seen.add(shown["identifier"])
        rows.append([shown["identifier"], shown["state"]["name"], color(shown["state"]["color"]),
                     shown["url"], str(count),
                     re.sub(r"\s+", " ", shown["title"])])

    tmp = out + ".tmp"
    with open(tmp, "w") as fh:
        fh.writelines("\t".join(r) + "\n" for r in rows)
    os.replace(tmp, out)


if __name__ == "__main__":
    main()
