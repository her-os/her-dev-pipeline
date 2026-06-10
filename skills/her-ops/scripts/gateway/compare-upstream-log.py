#!/usr/bin/env python3
"""
按 gateway request_id 对比 new-api 兼容上游的 token 日志。

只读操作：
  - 通过 gateway Admin API 读取本地 logs
  - 通过 SSH + psql 读取本地 channel key，调用上游 /api/log/token
  - 不发模型请求，不改 gateway / 上游配置

用法：
  compare-upstream-log.py 202605150539369706863368268d9d60yGmSzWi
  compare-upstream-log.py <gateway_request_id> --upstream-base https://api.imarouter.com
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GW_ADMIN = os.path.join(SCRIPT_DIR, "gw-admin.sh")
SSH = os.environ.get("HER_OPS_SSH", "/usr/bin/ssh ubuntu@192.144.187.174").split()
CN_TZ = timezone(timedelta(hours=8))
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,128}$")


class ToolError(RuntimeError):
    pass


def run(cmd: list[str], *, input_text: str | None = None) -> str:
    result = subprocess.run(
        cmd,
        input=input_text,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise ToolError(detail or f"command failed: {' '.join(cmd)}")
    return result.stdout


def gw_api(method: str, path: str) -> dict[str, Any]:
    out = run([GW_ADMIN, method, path])
    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise ToolError(f"gateway Admin API returned non-json: {out[:300]}") from exc
    if not data.get("success"):
        raise ToolError(f"gateway Admin API failed: {data.get('message') or data}")
    return data


def remote_psql_json(sql: str) -> dict[str, Any]:
    sql_b64 = base64.b64encode(sql.encode()).decode()
    remote = f"""
set -euo pipefail
pg="$(sudo docker ps --format '{{{{.Names}}}}' | awk '/dokploy-postgres|postgres/ {{print; exit}}')"
if [ -z "$pg" ]; then
  echo "ERROR: postgres container not found" >&2
  exit 2
fi
dsn="$(sudo docker exec new-api printenv SQL_DSN)"
if [ -z "$dsn" ]; then
  echo "ERROR: SQL_DSN not found in new-api" >&2
  exit 2
fi
printf '%s' '{sql_b64}' | base64 -d | sudo docker exec -i "$pg" psql "$dsn" -v ON_ERROR_STOP=1 -At
"""
    out = run([*SSH, "bash", "-lc", remote])
    line = out.strip().splitlines()[0] if out.strip() else ""
    if not line:
        raise ToolError("psql returned empty result")
    try:
        return json.loads(line)
    except json.JSONDecodeError as exc:
        raise ToolError(f"psql returned non-json: {line[:300]}") from exc


def fetch_gateway_log(request_id: str) -> dict[str, Any]:
    query = urllib.parse.urlencode({"request_id": request_id, "p": 0, "page_size": 1})
    data = gw_api("GET", f"/api/log/?{query}")
    payload = data.get("data") or {}
    items = payload.get("items") or []
    if not items:
        raise ToolError(f"gateway log not found for request_id={request_id}")
    return items[0]


def fetch_channel_with_key(channel_id: int) -> dict[str, Any]:
    sql = f"""
select json_build_object(
  'id', id,
  'name', coalesce(name, ''),
  'type', type,
  'base_url', coalesce(base_url, ''),
  'key', coalesce(key, ''),
  'models', coalesce(models, ''),
  'tag', coalesce(tag, ''),
  'setting', coalesce(setting, ''),
  'header_override', coalesce(header_override, '')
) from channels where id = {int(channel_id)} limit 1;
"""
    return remote_psql_json(sql)


def parse_jsonish(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if not isinstance(value, str) or not value.strip():
        return {}
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def extract_channel_id(log: dict[str, Any]) -> int:
    for key in ("channel", "channel_id"):
        value = log.get(key)
        if value:
            return int(value)
    other = parse_jsonish(log.get("other"))
    if other.get("channel_id"):
        return int(other["channel_id"])
    raise ToolError("gateway log has no channel id")


def extract_keys(raw_key: str) -> list[str]:
    raw_key = (raw_key or "").strip()
    if not raw_key:
        return []
    if raw_key.startswith("["):
        try:
            arr = json.loads(raw_key)
            keys: list[str] = []
            for item in arr:
                if isinstance(item, str):
                    keys.append(item.strip())
                elif item:
                    keys.append(json.dumps(item, ensure_ascii=False))
            return [k for k in keys if k]
        except json.JSONDecodeError:
            pass
    return [line.strip() for line in raw_key.splitlines() if line.strip()]


def infer_upstream_base(channel: dict[str, Any], override: str | None) -> str:
    if override:
        return override.rstrip("/")
    base_url = str(channel.get("base_url") or "").rstrip("/")
    name = str(channel.get("name") or "").lower()
    if "relay.tokenic.cn" in base_url or "imarouter" in name:
        return "https://api.imarouter.com"
    if base_url:
        return base_url
    raise ToolError("channel has no base_url; pass --upstream-base explicitly")


def http_json(url: str, key: str, timeout: int) -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "User-Agent": "her-ops-upstream-log-compare/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise ToolError(f"upstream HTTP {exc.code}: {body[:300]}") from exc
    except urllib.error.URLError as exc:
        raise ToolError(f"upstream request failed: {exc}") from exc
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ToolError(f"upstream returned non-json: {raw[:300]!r}") from exc


def fetch_upstream_logs(base_url: str, keys: list[str], *, timeout: int, max_keys: int) -> list[dict[str, Any]]:
    if not keys:
        raise ToolError("channel key is empty")
    logs: list[dict[str, Any]] = []
    tried = 0
    url = f"{base_url.rstrip('/')}/api/log/token"
    for index, key in enumerate(keys):
        if tried >= max_keys:
            break
        tried += 1
        try:
            data = http_json(url, key, timeout)
        except ToolError as exc:
            print(f"warn: upstream key#{index} log fetch skipped: {exc}", file=sys.stderr)
            continue
        if not data.get("success"):
            print(f"warn: upstream key#{index} returned success=false: {data.get('message')}", file=sys.stderr)
            continue
        payload = data.get("data")
        if isinstance(payload, dict):
            items = payload.get("items") or []
        else:
            items = payload or []
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict):
                    item["_upstream_key_index"] = index
                    logs.append(item)
    if len(keys) > max_keys:
        print(f"warn: channel has {len(keys)} keys; only tried first {max_keys}", file=sys.stderr)
    return logs


def to_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def fmt_ts(ts: int) -> str:
    if not ts:
        return "-"
    return datetime.fromtimestamp(ts, CN_TZ).strftime("%Y-%m-%d %H:%M:%S CST")


def pick_cache_tokens(log: dict[str, Any]) -> tuple[int, int]:
    other = parse_jsonish(log.get("other"))
    return to_int(other.get("cache_tokens")), to_int(other.get("cache_creation_tokens"))


def candidate_score(gw_log: dict[str, Any], up_log: dict[str, Any]) -> tuple[int, dict[str, int | bool]]:
    gw_end = to_int(gw_log.get("created_at"))
    gw_use = to_int(gw_log.get("use_time"))
    gw_start = gw_end - gw_use if gw_use else gw_end

    up_end = to_int(up_log.get("created_at"))
    up_use = to_int(up_log.get("use_time"))
    up_start = up_end - up_use if up_use else up_end

    start_delta = abs(up_start - gw_start) if up_start and gw_start else 999999
    end_delta = abs(up_end - gw_end) if up_end and gw_end else 999999

    gw_model = str(gw_log.get("model_name") or "")
    up_model = str(up_log.get("model_name") or "")
    model_match = bool(gw_model and gw_model == up_model)

    score = start_delta
    if not model_match:
        score += 100000

    gw_prompt = to_int(gw_log.get("prompt_tokens"))
    gw_completion = to_int(gw_log.get("completion_tokens"))
    up_prompt = to_int(up_log.get("prompt_tokens"))
    up_completion = to_int(up_log.get("completion_tokens"))
    if gw_prompt and up_prompt:
        score += min(abs(gw_prompt - up_prompt), 10000)
    if gw_completion and up_completion:
        score += min(abs(gw_completion - up_completion), 10000)

    return score, {
        "start_delta": start_delta,
        "end_delta": end_delta,
        "model_match": model_match,
    }


def match_candidates(
    gw_log: dict[str, Any],
    upstream_logs: list[dict[str, Any]],
    *,
    window_seconds: int,
) -> list[tuple[int, dict[str, int | bool], dict[str, Any]]]:
    gw_end = to_int(gw_log.get("created_at"))
    gw_use = to_int(gw_log.get("use_time"))
    gw_start = gw_end - gw_use if gw_use else gw_end
    candidates = []
    for item in upstream_logs:
        up_end = to_int(item.get("created_at"))
        up_use = to_int(item.get("use_time"))
        up_start = up_end - up_use if up_use else up_end
        if not up_start and not up_end:
            continue
        near_start = abs(up_start - gw_start) <= window_seconds if gw_start and up_start else False
        near_end = abs(up_end - gw_end) <= window_seconds if gw_end and up_end else False
        if not near_start and not near_end:
            continue
        score, detail = candidate_score(gw_log, item)
        candidates.append((score, detail, item))
    candidates.sort(key=lambda row: row[0])
    return candidates


def print_log_summary(prefix: str, log: dict[str, Any]) -> None:
    end = to_int(log.get("created_at"))
    use_time = to_int(log.get("use_time"))
    start = end - use_time if end and use_time else 0
    cache_tokens, cache_creation_tokens = pick_cache_tokens(log)
    request_id = log.get("request_id") or log.get("id") or "-"
    print(f"{prefix} request_id: {request_id}")
    print(f"{prefix} model: {log.get('model_name') or '-'}")
    print(f"{prefix} start: {fmt_ts(start)}")
    print(f"{prefix} end: {fmt_ts(end)}")
    print(f"{prefix} use_time: {use_time}s")
    print(f"{prefix} status/type: {log.get('type', '-')}")
    print(f"{prefix} content: {str(log.get('content') or '-')[:180]}")
    print(
        f"{prefix} tokens: prompt={to_int(log.get('prompt_tokens'))} "
        f"completion={to_int(log.get('completion_tokens'))} "
        f"cache={cache_tokens} cache_create={cache_creation_tokens}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="对比 gateway request_id 与 new-api 兼容上游 token 日志")
    parser.add_argument("gateway_request_id")
    parser.add_argument("--upstream-base", help="上游 new-api 面板 base URL；默认从 channel 推断")
    parser.add_argument("--window-seconds", type=int, default=900, help="候选时间窗口，默认 900 秒")
    parser.add_argument("--top", type=int, default=8, help="输出前 N 个候选，默认 8")
    parser.add_argument("--timeout", type=int, default=20, help="上游日志 API 超时秒数，默认 20")
    parser.add_argument("--max-keys", type=int, default=5, help="多 key 渠道最多尝试几个 key，默认 5")
    args = parser.parse_args()

    if not REQUEST_ID_RE.match(args.gateway_request_id):
        raise ToolError("gateway_request_id format looks invalid")

    gw_log = fetch_gateway_log(args.gateway_request_id)
    channel_id = extract_channel_id(gw_log)
    channel = fetch_channel_with_key(channel_id)
    upstream_base = infer_upstream_base(channel, args.upstream_base)
    keys = extract_keys(str(channel.get("key") or ""))
    upstream_logs = fetch_upstream_logs(upstream_base, keys, timeout=args.timeout, max_keys=args.max_keys)
    candidates = match_candidates(gw_log, upstream_logs, window_seconds=args.window_seconds)

    print("== gateway ==")
    print_log_summary("gateway", gw_log)
    print(f"gateway channel: #{channel_id} {channel.get('name') or '-'}")
    print(f"upstream log base: {upstream_base}")
    print()

    print("== upstream candidates ==")
    if not candidates:
        print(f"no candidates in +/- {args.window_seconds}s; upstream logs fetched={len(upstream_logs)}")
        return 1

    for rank, (score, detail, item) in enumerate(candidates[: args.top], start=1):
        cache_tokens, cache_creation_tokens = pick_cache_tokens(item)
        end = to_int(item.get("created_at"))
        use_time = to_int(item.get("use_time"))
        start = end - use_time if end and use_time else 0
        rid = item.get("request_id") or item.get("id") or "-"
        print(f"[{rank}] upstream_request_id={rid} score={score}")
        print(f"    model={item.get('model_name') or '-'} type={item.get('type', '-')}")
        print(f"    start={fmt_ts(start)} end={fmt_ts(end)} use_time={use_time}s")
        print(f"    delta_start={detail['start_delta']}s delta_end={detail['end_delta']}s model_match={detail['model_match']}")
        print(
            f"    tokens prompt={to_int(item.get('prompt_tokens'))} "
            f"completion={to_int(item.get('completion_tokens'))} "
            f"cache={cache_tokens} cache_create={cache_creation_tokens} quota={to_int(item.get('quota'))}"
        )
        print(f"    content={str(item.get('content') or '-')[:180]}")

    best = candidates[0][2]
    gw_end = to_int(gw_log.get("created_at"))
    up_end = to_int(best.get("created_at"))
    if gw_end and up_end and up_end > gw_end + 30:
        print()
        print("note: best upstream log ended after gateway log.")
        print("      如果 gateway 已经 504，而上游之后成功，说明上游后端可能继续跑完并计费；自动重试要先评估重复计费。")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
