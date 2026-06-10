#!/usr/bin/env python3
"""
导出 her-gateway 所有用户每日用量数据，生成可视化 HTML 页面。

用法:
  python3 export-daily-usage.py                    # 最近 30 天
  python3 export-daily-usage.py --days 7           # 最近 7 天
  python3 export-daily-usage.py --start 2026-04-01 --end 2026-04-30
  python3 export-daily-usage.py -o /tmp/report.html
"""

import argparse
import json
import os
import subprocess
import sys
import webbrowser
from collections import defaultdict
from datetime import datetime, timedelta, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GW_SCRIPT = os.path.join(SCRIPT_DIR, "gw-admin.sh")
CN_TZ = timezone(timedelta(hours=8))


def gw_api(method, path):
    result = subprocess.run(
        [GW_SCRIPT, method, path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"API 调用失败: {path}\n{result.stderr}", file=sys.stderr)
        return None
    return json.loads(result.stdout)


def fetch_all_users():
    page = 0
    all_users = []
    while True:
        data = gw_api("GET", f"/api/user/?p={page}&page_size=100")
        if not data or not data.get("data", {}).get("items"):
            break
        all_users.extend(data["data"]["items"])
        if len(all_users) >= data["data"]["total"]:
            break
        page += 1
    return all_users


def fetch_user_usage(user_id, start_ts, end_ts):
    data = gw_api("GET", f"/api/user/{user_id}/usage?start_timestamp={start_ts}&end_timestamp={end_ts}")
    if not data or not data.get("success"):
        return []
    return data.get("data", [])


def clean_username(username):
    return username.replace("-Her", "").split("@")[0] if "@" in username else username.replace("-Her", "")


def main():
    parser = argparse.ArgumentParser(description="导出 her-gateway 每日用量 HTML 报告")
    parser.add_argument("--days", type=int, default=30, help="最近 N 天（默认 30）")
    parser.add_argument("--start", type=str, help="起始日期 YYYY-MM-DD")
    parser.add_argument("--end", type=str, help="结束日期 YYYY-MM-DD")
    parser.add_argument("-o", "--output", type=str, help="输出 HTML 路径")
    parser.add_argument("--no-open", action="store_true", help="不自动打开浏览器")
    args = parser.parse_args()

    now = datetime.now(CN_TZ)
    if args.start and args.end:
        start_dt = datetime.strptime(args.start, "%Y-%m-%d").replace(tzinfo=CN_TZ)
        end_dt = datetime.strptime(args.end, "%Y-%m-%d").replace(hour=23, minute=59, second=59, tzinfo=CN_TZ)
    else:
        end_dt = now
        start_dt = now - timedelta(days=args.days)
        start_dt = start_dt.replace(hour=0, minute=0, second=0)

    start_ts = int(start_dt.timestamp())
    end_ts = int(end_dt.timestamp())

    print(f"时间范围: {start_dt.strftime('%Y-%m-%d')} ~ {end_dt.strftime('%Y-%m-%d')}")
    print("正在获取用户列表...")
    users = fetch_all_users()
    active_users = [u for u in users if u["used_quota"] > 0]
    print(f"总用户 {len(users)}，活跃用户 {len(active_users)}")

    # user_id -> { date_str -> { model -> {quota, tokens, count} } }
    all_usage = {}
    user_map = {}  # id -> display info

    for i, u in enumerate(active_users):
        uid = u["id"]
        uname = u["username"]
        display = clean_username(uname)
        user_map[uid] = {"username": uname, "display": display, "used_quota": u["used_quota"], "request_count": u["request_count"]}
        print(f"  [{i+1}/{len(active_users)}] {display}...", end="", flush=True)
        records = fetch_user_usage(uid, start_ts, end_ts)
        if not records:
            print(" 无数据")
            continue
        daily = defaultdict(lambda: defaultdict(lambda: {"quota": 0, "tokens": 0, "count": 0}))
        for r in records:
            ts = r["created_at"]
            dt = datetime.fromtimestamp(ts, tz=CN_TZ)
            day = dt.strftime("%Y-%m-%d")
            model = r["model_name"]
            daily[day][model]["quota"] += r["quota"]
            daily[day][model]["tokens"] += r["token_used"]
            daily[day][model]["count"] += r["count"]
        all_usage[uid] = dict(daily)
        total_calls = sum(r["count"] for r in records)
        print(f" {len(daily)} 天, {total_calls} 次调用")

    # 生成日期列表
    date_list = []
    d = start_dt
    while d <= end_dt:
        date_list.append(d.strftime("%Y-%m-%d"))
        d += timedelta(days=1)

    # 聚合: 每日总消耗 / 每日模型消耗 / 每用户每日消耗
    daily_total = defaultdict(lambda: {"quota": 0, "tokens": 0, "count": 0})
    daily_model = defaultdict(lambda: defaultdict(lambda: {"quota": 0, "tokens": 0, "count": 0}))
    user_daily_total = defaultdict(lambda: defaultdict(lambda: {"quota": 0, "tokens": 0, "count": 0}))
    all_models = set()

    for uid, days in all_usage.items():
        for day, models in days.items():
            for model, stats in models.items():
                all_models.add(model)
                daily_total[day]["quota"] += stats["quota"]
                daily_total[day]["tokens"] += stats["tokens"]
                daily_total[day]["count"] += stats["count"]
                daily_model[day][model]["quota"] += stats["quota"]
                daily_model[day][model]["tokens"] += stats["tokens"]
                daily_model[day][model]["count"] += stats["count"]
                user_daily_total[uid][day]["quota"] += stats["quota"]
                user_daily_total[uid][day]["tokens"] += stats["tokens"]
                user_daily_total[uid][day]["count"] += stats["count"]

    all_models = sorted(all_models)

    # 用户按总消耗排序
    user_rank = sorted(
        [(uid, sum(d["quota"] for d in days.values())) for uid, days in user_daily_total.items()],
        key=lambda x: -x[1]
    )

    # 配色
    palette = [
        "#6366f1", "#f59e0b", "#10b981", "#ef4444", "#8b5cf6",
        "#ec4899", "#14b8a6", "#f97316", "#06b6d4", "#84cc16",
        "#e11d48", "#7c3aed", "#059669", "#d946ef", "#0ea5e9",
    ]

    def quota_to_yuan(q):
        return q / 500000

    # 构建 JSON 数据
    chart_data = {
        "dates": date_list,
        "models": all_models,
        "dailyTotal": [{"date": d, "yuan": round(quota_to_yuan(daily_total[d]["quota"]), 2), "tokens": daily_total[d]["tokens"], "count": daily_total[d]["count"]} for d in date_list],
        "dailyModel": {m: [round(quota_to_yuan(daily_model[d][m]["quota"]), 2) for d in date_list] for m in all_models},
        "dailyModelTokens": {m: [daily_model[d][m]["tokens"] for d in date_list] for m in all_models},
        "userRank": [{"uid": uid, "display": user_map[uid]["display"], "totalYuan": round(quota_to_yuan(total_q), 2), "totalRequests": user_map.get(uid, {}).get("request_count", 0), "daily": [round(quota_to_yuan(user_daily_total[uid][d]["quota"]), 2) for d in date_list]} for uid, total_q in user_rank],
        "palette": palette,
        "generatedAt": now.strftime("%Y-%m-%d %H:%M"),
        "range": f"{start_dt.strftime('%Y-%m-%d')} ~ {end_dt.strftime('%Y-%m-%d')}",
    }

    html = generate_html(chart_data)

    output_path = args.output or f"/tmp/her-gateway-usage-{now.strftime('%Y%m%d-%H%M')}.html"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\n报告已生成: {output_path}")

    if not args.no_open:
        webbrowser.open(f"file://{output_path}")


def generate_html(data):
    data_json = json.dumps(data, ensure_ascii=False)
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Her Gateway 用量报告</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    background: #0f0f11; color: #e4e4e7;
    min-height: 100vh; padding: 32px 24px;
  }}
  .header {{
    max-width: 1200px; margin: 0 auto 40px;
  }}
  .header h1 {{
    font-size: 28px; font-weight: 600; color: #fafafa;
    letter-spacing: -0.02em;
  }}
  .header .meta {{
    margin-top: 8px; font-size: 14px; color: #71717a;
  }}
  .kpi-row {{
    max-width: 1200px; margin: 0 auto 40px;
    display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px;
  }}
  .kpi {{
    background: #18181b; border: 1px solid #27272a; border-radius: 12px;
    padding: 20px 24px;
  }}
  .kpi .label {{ font-size: 13px; color: #71717a; margin-bottom: 6px; }}
  .kpi .value {{ font-size: 28px; font-weight: 700; color: #fafafa; }}
  .kpi .unit {{ font-size: 14px; color: #52525b; margin-left: 4px; }}
  .section {{
    max-width: 1200px; margin: 0 auto 48px;
  }}
  .section h2 {{
    font-size: 18px; font-weight: 600; color: #d4d4d8;
    margin-bottom: 20px; padding-bottom: 12px;
    border-bottom: 1px solid #27272a;
  }}
  .chart-wrap {{
    background: #18181b; border: 1px solid #27272a; border-radius: 12px;
    padding: 24px; margin-bottom: 24px;
  }}
  .chart-wrap canvas {{
    width: 100% !important;
    max-height: 380px;
  }}
  .user-grid {{
    display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 16px;
  }}
  .user-card {{
    background: #18181b; border: 1px solid #27272a; border-radius: 12px;
    padding: 20px;
  }}
  .user-card .name {{
    font-size: 15px; font-weight: 600; color: #e4e4e7;
    margin-bottom: 4px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }}
  .user-card .stats {{
    font-size: 13px; color: #71717a; margin-bottom: 14px;
  }}
  .user-card .stats span {{ color: #a1a1aa; font-weight: 500; }}
  .user-card canvas {{ max-height: 120px; }}
  .rank-badge {{
    display: inline-block; width: 22px; height: 22px; border-radius: 6px;
    text-align: center; line-height: 22px; font-size: 12px; font-weight: 700;
    margin-right: 8px; vertical-align: middle;
  }}
  .rank-1 {{ background: #f59e0b; color: #18181b; }}
  .rank-2 {{ background: #94a3b8; color: #18181b; }}
  .rank-3 {{ background: #b45309; color: #fafafa; }}
  .rank-n {{ background: #27272a; color: #71717a; }}
</style>
</head>
<body>

<div class="header">
  <h1>Her Gateway 用量报告</h1>
  <div class="meta">{data["range"]} &middot; 生成于 {data["generatedAt"]}</div>
</div>

<div class="kpi-row" id="kpiRow"></div>

<div class="section">
  <h2>每日费用趋势</h2>
  <div class="chart-wrap"><canvas id="dailyCostChart"></canvas></div>
</div>

<div class="section">
  <h2>模型费用分布</h2>
  <div class="chart-wrap"><canvas id="modelStackChart"></canvas></div>
</div>

<div class="section">
  <h2>每日调用次数</h2>
  <div class="chart-wrap"><canvas id="dailyCountChart"></canvas></div>
</div>

<div class="section">
  <h2>用户用量排行</h2>
  <div class="user-grid" id="userGrid"></div>
</div>

<script>
const D = {data_json};
const palette = D.palette;

// --- KPI ---
const totalYuan = D.dailyTotal.reduce((s, d) => s + d.yuan, 0);
const totalTokens = D.dailyTotal.reduce((s, d) => s + d.tokens, 0);
const totalCalls = D.dailyTotal.reduce((s, d) => s + d.count, 0);
const activeDays = D.dailyTotal.filter(d => d.count > 0).length;
const avgDaily = activeDays > 0 ? totalYuan / activeDays : 0;

function fmt(n) {{ return n >= 10000 ? (n/10000).toFixed(1) + "万" : n >= 1000 ? (n/1000).toFixed(1) + "k" : n.toString(); }}
function fmtYuan(n) {{ return n >= 1000 ? (n/1000).toFixed(1) + "k" : n.toFixed(1); }}

document.getElementById("kpiRow").innerHTML = [
  ["总费用", "¥" + fmtYuan(totalYuan), ""],
  ["日均费用", "¥" + avgDaily.toFixed(1), "/" + activeDays + "天"],
  ["总调用", fmt(totalCalls), "次"],
  ["总 Token", fmt(totalTokens), ""],
  ["活跃用户", D.userRank.filter(u => u.totalYuan > 0).length, "人"],
].map(([label, value, unit]) =>
  `<div class="kpi"><div class="label">${{label}}</div><div class="value">${{value}}<span class="unit">${{unit}}</span></div></div>`
).join("");

// --- Chart defaults ---
Chart.defaults.color = "#71717a";
Chart.defaults.borderColor = "#27272a";
Chart.defaults.font.family = "-apple-system, BlinkMacSystemFont, sans-serif";

const shortDates = D.dates.map(d => d.slice(5));

// --- Daily cost ---
new Chart(document.getElementById("dailyCostChart"), {{
  type: "bar",
  data: {{
    labels: shortDates,
    datasets: [{{
      data: D.dailyTotal.map(d => d.yuan),
      backgroundColor: "#6366f180",
      borderColor: "#6366f1",
      borderWidth: 1, borderRadius: 4,
    }}]
  }},
  options: {{
    plugins: {{ legend: {{ display: false }},
      tooltip: {{ callbacks: {{ label: ctx => "¥" + ctx.parsed.y.toFixed(1) }} }}
    }},
    scales: {{
      y: {{ ticks: {{ callback: v => "¥" + v }}, grid: {{ color: "#27272a40" }} }},
      x: {{ ticks: {{ maxRotation: 45 }}, grid: {{ display: false }} }}
    }}
  }}
}});

// --- Model stack ---
new Chart(document.getElementById("modelStackChart"), {{
  type: "bar",
  data: {{
    labels: shortDates,
    datasets: D.models.map((m, i) => ({{
      label: m,
      data: D.dailyModel[m],
      backgroundColor: palette[i % palette.length] + "b0",
      borderRadius: 2,
    }}))
  }},
  options: {{
    plugins: {{
      legend: {{ position: "top", labels: {{ boxWidth: 12, padding: 12 }} }},
      tooltip: {{ callbacks: {{ label: ctx => ctx.dataset.label + ": ¥" + ctx.parsed.y.toFixed(1) }} }}
    }},
    scales: {{
      x: {{ stacked: true, ticks: {{ maxRotation: 45 }}, grid: {{ display: false }} }},
      y: {{ stacked: true, ticks: {{ callback: v => "¥" + v }}, grid: {{ color: "#27272a40" }} }}
    }}
  }}
}});

// --- Daily calls ---
new Chart(document.getElementById("dailyCountChart"), {{
  type: "line",
  data: {{
    labels: shortDates,
    datasets: [{{
      data: D.dailyTotal.map(d => d.count),
      borderColor: "#10b981",
      backgroundColor: "#10b98120",
      fill: true, tension: 0.3, pointRadius: 3,
    }}]
  }},
  options: {{
    plugins: {{ legend: {{ display: false }},
      tooltip: {{ callbacks: {{ label: ctx => ctx.parsed.y + " 次" }} }}
    }},
    scales: {{
      y: {{ grid: {{ color: "#27272a40" }} }},
      x: {{ ticks: {{ maxRotation: 45 }}, grid: {{ display: false }} }}
    }}
  }}
}});

// --- User cards ---
const grid = document.getElementById("userGrid");
D.userRank.forEach((u, idx) => {{
  if (u.totalYuan <= 0) return;
  const card = document.createElement("div");
  card.className = "user-card";
  const rankClass = idx < 3 ? "rank-" + (idx+1) : "rank-n";
  card.innerHTML = `
    <div class="name">
      <span class="rank-badge ${{rankClass}}">${{idx+1}}</span>
      ${{u.display}}
    </div>
    <div class="stats">
      费用 <span>¥${{u.totalYuan.toFixed(1)}}</span>
    </div>
    <canvas id="user-${{u.uid}}"></canvas>
  `;
  grid.appendChild(card);

  new Chart(card.querySelector("canvas"), {{
    type: "bar",
    data: {{
      labels: shortDates,
      datasets: [{{
        data: u.daily,
        backgroundColor: palette[idx % palette.length] + "90",
        borderRadius: 2,
      }}]
    }},
    options: {{
      plugins: {{ legend: {{ display: false }},
        tooltip: {{ callbacks: {{ label: ctx => "¥" + ctx.parsed.y.toFixed(2) }} }}
      }},
      scales: {{
        x: {{ display: false }},
        y: {{ display: false }}
      }},
      maintainAspectRatio: false,
    }}
  }});
}});
</script>
</body>
</html>"""


if __name__ == "__main__":
    main()
