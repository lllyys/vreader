#!/usr/bin/env python3
import argparse
import json
import os
import shlex
import sys
from pathlib import Path


def warn(msg):
    print(f"warn: {msg}", file=sys.stderr)


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except Exception as exc:
        warn(f"failed to read {path}: {exc}")
        return None


def infer_kind(cfg):
    kind = cfg.get("type")
    if kind:
        kind = str(kind).lower()
    if kind in ("http", "https", "streamable-http", "sse"):
        return "http"
    if kind == "stdio":
        return "stdio"
    if cfg.get("url"):
        return "http"
    if cfg.get("command"):
        return "stdio"
    return "unknown"


def normalize_entry(name, cfg, source):
    if not isinstance(cfg, dict):
        return None
    entry = {
        "name": str(name),
        "source": source,
        "kind": infer_kind(cfg),
        "url": cfg.get("url"),
        "command": cfg.get("command"),
        "args": cfg.get("args") or [],
        "env": cfg.get("env") or {},
        "bearer_token_env_var": cfg.get("bearerTokenEnvVar") or cfg.get("bearer_token_env_var"),
    }
    if not isinstance(entry["args"], list):
        entry["args"] = [str(entry["args"])]
    if not isinstance(entry["env"], dict):
        entry["env"] = {}
    return entry


def collect_from_mcp_servers(servers, source, out):
    if not isinstance(servers, dict):
        return
    for name, cfg in servers.items():
        entry = normalize_entry(name, cfg, source)
        if entry:
            out.append(entry)


def collect_from_claude_json(path, out):
    data = load_json(path)
    if not data:
        return
    collect_from_mcp_servers(data.get("mcpServers"), f"claude:{path}", out)

    projects = data.get("projects")
    if isinstance(projects, dict):
        for proj_path, proj_cfg in projects.items():
            if isinstance(proj_cfg, dict) and "mcpServers" in proj_cfg:
                collect_from_mcp_servers(proj_cfg.get("mcpServers"), f"claude:project:{proj_path}", out)
    elif isinstance(projects, list):
        for proj_cfg in projects:
            if not isinstance(proj_cfg, dict):
                continue
            proj_path = proj_cfg.get("path") or proj_cfg.get("projectPath") or "<unknown>"
            if "mcpServers" in proj_cfg:
                collect_from_mcp_servers(proj_cfg.get("mcpServers"), f"claude:project:{proj_path}", out)


def find_mcp_json_files(root, max_depth):
    root = Path(root)
    if not root.exists():
        warn(f"project path not found: {root}")
        return []
    results = []
    skip = {".git", "node_modules", ".venv", ".idea", ".vscode", ".next", ".cache"}
    for dirpath, dirnames, filenames in os.walk(root):
        rel = Path(dirpath).relative_to(root)
        if rel.parts and rel.parts[0].startswith("."):
            continue
        depth = len(rel.parts)
        if depth > max_depth:
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d not in skip and not d.startswith(".")]
        if ".mcp.json" in filenames:
            results.append(Path(dirpath) / ".mcp.json")
    return results


def collect_from_mcp_json_files(project_path, max_depth, out):
    for path in find_mcp_json_files(project_path, max_depth):
        data = load_json(path)
        if not data:
            continue
        collect_from_mcp_servers(data.get("mcpServers"), f"mcp.json:{path}", out)


def build_command(entry):
    name = shlex.quote(entry["name"])
    if entry["kind"] == "http" and entry.get("url"):
        cmd = f"codex mcp add {name} --url {shlex.quote(str(entry['url']))}"
        bearer_env = entry.get("bearer_token_env_var")
        if bearer_env:
            cmd += f" --bearer-token-env-var {shlex.quote(str(bearer_env))}"
        return cmd
    if entry["kind"] == "stdio" and entry.get("command"):
        cmd = f"codex mcp add {name}"
        for k, v in entry.get("env", {}).items():
            cmd += f" --env {shlex.quote(str(k))}={shlex.quote(str(v))}"
        parts = [entry["command"]] + entry.get("args", [])
        cmd += " -- " + " ".join(shlex.quote(str(p)) for p in parts)
        return cmd
    return None


def main():
    parser = argparse.ArgumentParser(description="Scan local config for MCP servers and print codex mcp add commands.")
    parser.add_argument("--claude", default=os.path.expanduser("~/.claude.json"))
    parser.add_argument("--project", default=os.getcwd())
    parser.add_argument("--max-depth", type=int, default=4)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    entries = []
    collect_from_claude_json(args.claude, entries)
    collect_from_mcp_json_files(args.project, args.max_depth, entries)

    if args.json:
        print(json.dumps(entries, indent=2))
        return

    if not entries:
        print("Found 0 MCP servers.")
        return

    name_counts = {}
    for e in entries:
        name_counts[e["name"]] = name_counts.get(e["name"], 0) + 1

    print(f"Found {len(entries)} MCP server(s):")
    for e in entries:
        print(f"- {e['name']} ({e['kind']}) from {e['source']}")
        if e.get("url"):
            print(f"  url: {e['url']}")
        if e.get("command"):
            args_str = " ".join(str(a) for a in e.get("args", []))
            print(f"  command: {e['command']} {args_str}".rstrip())
        if e.get("env"):
            env_items = [f"{k}={v}" for k, v in e["env"].items()]
            print(f"  env: {', '.join(env_items)}")
        if name_counts[e["name"]] > 1:
            print("  note: duplicate name detected; consider renaming")
        cmd = build_command(e)
        if cmd:
            print(f"  codex mcp add: {cmd}")
        else:
            print("  codex mcp add: (insufficient config)")


if __name__ == "__main__":
    main()
