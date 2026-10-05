#!/bin/bash
# Website visits, from the site's own private counts. Usage: ./stats.sh [days, default 14]
DAYS="${1:-14}"
cd "$(dirname "$0")"
q() { npx wrangler d1 execute blackhole-analytics --remote --json --command "$1" 2>/dev/null; }
python3 - "$DAYS" <<PY
import json, subprocess, sys
days = int(sys.argv[1])
def q(sql):
    out = subprocess.run(["npx", "wrangler", "d1", "execute", "blackhole-analytics", "--remote", "--json", "--command", sql], capture_output=True, text=True).stdout
    return json.loads(out)[0]["results"]
since = f"date('now', '-{days - 1} days')"
daily = q(f"""SELECT day,
  COUNT(DISTINCT CASE WHEN kind='view' THEN visitor END) AS visitors,
  SUM(kind='view') AS views,
  COUNT(DISTINCT CASE WHEN kind='download' THEN visitor END) AS downloads,
  SUM(kind='agent') AS agents
  FROM hits WHERE day >= {since} GROUP BY day ORDER BY day""")
total = {k: sum(r[k] or 0 for r in daily) for k in ("visitors", "views", "downloads", "agents")}
print(f"getblackhole.app — last {days} days\n")
print(f"  {'day':<12}{'visitors':>9}{'views':>8}{'downloads':>11}{'agents':>8}")
for r in daily:
    print(f"  {r['day']:<12}{r['visitors']:>9}{r['views']:>8}{r['downloads']:>11}{r['agents']:>8}")
print(f"  {'total':<12}{total['visitors']:>9}{total['views']:>8}{total['downloads']:>11}{total['agents']:>8}")
print("  (visitors are counted per day: one person on two days counts twice)\n")
for title, col in (("Where they came from", "referrer"), ("Countries", "country")):
    rows = q(f"SELECT {col} AS k, COUNT(DISTINCT visitor || day) AS n FROM hits WHERE kind='view' AND day >= {since} GROUP BY {col} ORDER BY n DESC LIMIT 8")
    print(f"{title}:")
    for r in rows:
        print(f"  {(r['k'] or ('direct / unknown' if col == 'referrer' else 'unknown')):<28}{r['n']:>5}")
    print()
PY
