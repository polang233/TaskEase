"""宣传短片配乐（纯标准库）。120 BPM，7.5 秒前紧张铺垫，7.5 秒 Logo 落地进入明亮段。用法：python3 music.py 28"""
import math, random, struct, sys, wave

SR = 44100
DUR = float(sys.argv[1]) if len(sys.argv) > 1 else 28.0
N = int(SR * DUR)
BEAT = 0.5
DROP = 7.5
random.seed(7)

def hz(m): return 440 * 2 ** ((m - 69) / 12)
tense = [[45, 52, 57, 60], [44, 52, 56, 59], [41, 48, 53, 57], [40, 47, 52, 56]]       # 每 2 秒一换
bright = [[48, 55, 60, 64, 67], [43, 50, 55, 59, 62], [45, 52, 57, 60, 64], [41, 48, 53, 57, 60]]  # 每 2 秒一换

def kick(t):
    if t < 0 or t > 0.35: return 0.0
    f = 50 + 110 * math.exp(-t * 30)
    return math.sin(2 * math.pi * f * t) * math.exp(-t * 9)

out = bytearray()
for i in range(N):
    t = i / SR
    pre = t < DROP
    if pre:
        chord = tense[int(t / 2) % 4]; seg = t % 2
    else:
        chord = bright[int((t - DROP) / 2) % 4]; seg = (t - DROP) % 2
    env = min(1, seg / 0.15) * (0.75 + 0.25 * math.exp(-seg * 2))
    pad = sum(math.sin(2 * math.pi * hz(m) * t) + 0.25 * math.sin(2 * math.pi * hz(m) * 2.004 * t) for m in chord) / len(chord)
    s = pad * env * (0.18 if pre else 0.22)
    bt = t % BEAT
    # 底鼓：铺垫段每拍，尾段 26 秒后停
    if t < DUR - 2.0:
        s += kick(bt) * (0.55 if pre else 0.75) * min(1, t / 1.0 + 0.4)
    # 明亮段：贝斯八分 + 军鼓 2/4 拍 + 踩镲
    if not pre and t < DUR - 2.0:
        e = t % 0.25
        s += math.sin(2 * math.pi * hz(chord[0] - 12) * t) * math.exp(-e * 10) * 0.28
        beat_idx = int((t - DROP) / BEAT)
        if beat_idx % 2 == 1 and bt < 0.2:
            s += (random.random() * 2 - 1) * math.exp(-bt * 22) * 0.32
        if (t % 0.25) < 0.04:
            s += (random.random() * 2 - 1) * math.exp(-(t % 0.25) * 120) * 0.12
        # 琶音
        arp = chord[int(t / 0.125) % len(chord)] + 12
        s += math.sin(2 * math.pi * hz(arp) * t) * math.exp(-(t % 0.125) * 18) * 0.07
    # 铺垫段：心跳加速感的上升噪声
    if 5.5 < t < DROP:
        x = (t - 5.5) / 2.0
        s += (random.random() * 2 - 1) * 0.10 * x * x
        s += math.sin(2 * math.pi * (200 + 1200 * x * x) * t) * 0.05 * x
    # Logo 落地冲击
    if DROP <= t < DROP + 1.2:
        d = t - DROP
        s += (random.random() * 2 - 1) * math.exp(-d * 5) * 0.35 + math.sin(2 * math.pi * 45 * d) * math.exp(-d * 3) * 0.5
    # 结尾和弦延音
    if t >= DUR - 2.0:
        s *= max(0, (DUR - t) / 2.0) ** 0.5
    out += struct.pack('<h', int(math.tanh(s * 1.2) * 26000))

with wave.open('public/music.wav', 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(out))
print('ok', DUR)
