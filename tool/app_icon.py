# 앱 아이콘 생성기 (교회 로고 + 집회 배지). 실행: python3 tool/app_icon.py
# 필요: rsvg-convert (brew install librsvg)
# tool/icon/*.svg 를 만들고 web / macos / windows 아이콘을 전부 덮어쓴다.
import math, struct, subprocess, os, tempfile

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # repo root
OUT = f'{R}/tool/icon'
C = 512  # logo center

def arc(r, a0, a1):
    # clockwise from a0 to a1 (deg, SVG coords: 0=right, 90=down)
    sweep = (a1 - a0) % 360
    p = lambda a: (C + r * math.cos(math.radians(a)), C + r * math.sin(math.radians(a)))
    x0, y0 = p(a0); x1, y1 = p(a1)
    return f'M{x0:.1f} {y0:.1f} A{r} {r} 0 {1 if sweep > 180 else 0} 1 {x1:.1f} {y1:.1f}'

def logo():
    return f'''
  <g fill="none" stroke="url(#g)" stroke-linecap="round">
    <path d="{arc(360, 150, 40)}" stroke-width="58"/>
    <path d="{arc(270, 140, 30)}" stroke-width="50"/>
    <path d="{arc(180, 80, 20)}" stroke-width="42"/>
  </g>
  <g fill="url(#g)">
    <rect x="{C-24}" y="{C-150}" width="48" height="290" rx="6"/>
    <rect x="{C-105}" y="{C-80}" width="210" height="46" rx="6"/>
  </g>
  <!-- 집회(사람들) 배지 -->
  <circle cx="770" cy="770" r="150" fill="#fff" stroke="url(#g)" stroke-width="22"/>
  <g fill="#B3132F">
    <circle cx="712" cy="738" r="30"/><circle cx="828" cy="738" r="30"/>
    <path d="M652 842 a60 52 0 0 1 120 0 z"/><path d="M768 842 a60 52 0 0 1 120 0 z"/>
    <circle cx="770" cy="716" r="38" stroke="#fff" stroke-width="10"/>
    <path d="M692 858 a78 66 0 0 1 156 0 z" stroke="#fff" stroke-width="10"/>
  </g>'''

def svg(bg_rect, scale):
    # scale logo around canvas center to keep it inside safe zones
    t = f'translate({C} {C}) scale({scale}) translate({-C} {-C})'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs><linearGradient id="g" x1="1" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#E5485F"/><stop offset="1" stop-color="#A30F2B"/>
  </linearGradient></defs>
  {bg_rect}
  <g transform="{t}">{logo()}</g>
</svg>'''

variants = {
    # 둥근 사각 (favicon / web / windows)
    'rounded': svg('<rect width="1024" height="1024" rx="220" fill="#fff"/>', 0.92),
    # macOS: 824px 본체 + 여백
    'macos': svg('<rect x="100" y="100" width="824" height="824" rx="185" fill="#fff"/>', 0.74),
    # maskable: 꽉 찬 배경, 로고는 80% 안전영역 안
    'maskable': svg('<rect width="1024" height="1024" fill="#fff"/>', 0.72),
}
os.makedirs(OUT, exist_ok=True)
for k, s in variants.items():
    open(f'{OUT}/{k}.svg', 'w').write(s)

def png(variant, size, dst):
    subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), f'{OUT}/{variant}.svg', '-o', dst], check=True)

png('rounded', 64, f'{R}/web/favicon.png')
png('rounded', 192, f'{R}/web/icons/Icon-192.png')
png('rounded', 512, f'{R}/web/icons/Icon-512.png')
png('maskable', 192, f'{R}/web/icons/Icon-maskable-192.png')
png('maskable', 512, f'{R}/web/icons/Icon-maskable-512.png')
for s in (16, 32, 64, 128, 256, 512, 1024):
    png('macos', s, f'{R}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{s}.png')

# Windows .ico: PNG-embedded entries (Vista+)
sizes = (16, 24, 32, 48, 64, 128, 256)
blobs = []
tmp = tempfile.mkdtemp()
for s in sizes:
    png('rounded', s, f'{tmp}/{s}.png')
    blobs.append(open(f'{tmp}/{s}.png', 'rb').read())
off = 6 + 16 * len(sizes)
ico = struct.pack('<HHH', 0, 1, len(sizes))
for s, b in zip(sizes, blobs):
    ico += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(b), off)
    off += len(b)
open(f'{R}/windows/runner/resources/app_icon.ico', 'wb').write(ico + b''.join(blobs))
