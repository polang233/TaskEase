"""Render the public PostHog dashboard numbers as an SVG card for the README.

Usage: python3 Scripts/usage-stats-svg.py OUTPUT.svg
Reads only the public shared dashboard (no API key) and keeps three tiles:
active installations, daily trend and region share.
"""
import datetime
import html
import json
import re
import sys
import urllib.request

PAGE = 'https://us.posthog.com/shared/Do9W3574hr41SnipsKsuPGuWM_LYrw'
DASHBOARD_ID = 2196112
COUNT, TREND, REGIONS = 'MfmaDUaP', '8r3p40Y9', 'l1yAQ9JN'


def load():
    request = urllib.request.Request(PAGE, headers={'User-Agent': 'TaskEase-usage-card'})
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status != 200:
            raise RuntimeError(f'HTTP {response.status}')
        page = response.read(2_000_000).decode('utf-8')
    match = re.search(r'<script\b(?=[^>]*\bid=["\']posthog-exported-data["\'])[^>]*>(.*?)</script>', page, re.S | re.I)
    if not match:
        raise RuntimeError('exported data not found')
    data = json.loads(match.group(1))
    if isinstance(data, str):
        data = json.loads(data)
    dashboard = data['dashboard']
    if dashboard.get('id') != DASHBOARD_ID:
        raise RuntimeError('unexpected dashboard')
    insights = {tile['insight'].get('short_id'): tile['insight'] for tile in dashboard['tiles'] if tile.get('insight')}

    def integer(value):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0 or value != int(value):
            raise ValueError(value)
        return int(value)

    total = integer(insights[COUNT]['result'][0][0])
    days = []
    trend = (insights.get(TREND) or {}).get('result') or []
    if trend:
        days = [(day, integer(value)) for day, value in zip(trend[0]['days'], trend[0]['data'])]
    regions = []
    for row in (insights.get(REGIONS) or {}).get('result') or []:
        if len(row) == 2 and isinstance(row[0], str) and row[0]:
            regions.append((row[0][:20], integer(row[1])))
    regions.sort(key=lambda item: -item[1])
    return total, days[-30:], regions[:4]


def render(total, days, regions):
    width, height = 560, 190
    left, right, top, bottom = 24, 536, 78, 150
    peak = max([value for _, value in days] + [1])
    points = []
    for index, (_, value) in enumerate(days):
        x = left + (right - left) * index / max(1, len(days) - 1)
        y = bottom - (bottom - top) * value / peak
        points.append(f'{x:.1f},{y:.1f}')
    line = ' '.join(points)
    area = f'{left},{bottom} {line} {right},{bottom}' if points else ''
    share = '  '.join(f'{html.escape(name)} {round(count * 100 / total) if total else 0}%' for name, count in regions)
    first = days[0][0][5:] if days else ''
    last = days[-1][0][5:] if days else ''
    updated = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="轻程近 30 天 {total} 台设备">
<style>
  .card {{ fill: #ffffff; stroke: #d0d7de; }}
  .title {{ fill: #1f2328; font: 600 15px -apple-system, "PingFang SC", "Segoe UI", sans-serif; }}
  .muted {{ fill: #656d76; font: 12px -apple-system, "PingFang SC", "Segoe UI", sans-serif; }}
  .big {{ fill: #1f2328; font: 600 28px -apple-system, "SF Pro Rounded", "Segoe UI", sans-serif; }}
  .line {{ fill: none; stroke: #30bba9; stroke-width: 2; stroke-linejoin: round; }}
  .area {{ fill: #30bba9; opacity: 0.15; }}
  .axis {{ stroke: #d0d7de; }}
  @media (prefers-color-scheme: dark) {{
    .card {{ fill: #0d1117; stroke: #30363d; }}
    .title, .big {{ fill: #e6edf3; }}
    .muted {{ fill: #8d96a0; }}
    .axis {{ stroke: #30363d; }}
  }}
</style>
<rect class="card" x="0.5" y="0.5" width="{width - 1}" height="{height - 1}" rx="10"/>
<text class="title" x="{left}" y="30">轻程 TaskEase · 使用统计</text>
<text class="big" x="{left}" y="64">{total}</text>
<text class="muted" x="{left + 10 + 17 * len(str(total))}" y="63">台设备 · 近 30 天活跃</text>
<text class="muted" x="{right}" y="63" text-anchor="end">{share}</text>
<line class="axis" x1="{left}" y1="{bottom}" x2="{right}" y2="{bottom}"/>
<polygon class="area" points="{area}"/>
<polyline class="line" points="{line}"/>
<text class="muted" x="{left}" y="170">{first}</text>
<text class="muted" x="{right}" y="170" text-anchor="end">{last} · 更新于 {updated} UTC</text>
</svg>
'''


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: usage-stats-svg.py OUTPUT.svg')
    with open(sys.argv[1], 'w', encoding='utf-8') as output:
        output.write(render(*load()))
