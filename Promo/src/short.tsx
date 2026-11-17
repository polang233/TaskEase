import React from 'react';
import {AbsoluteFill, Easing, interpolate, interpolateColors, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {AppGlyph, C, clamp, ease, Leaves, useSceneOpacity} from './theme';

/* ================= 通用：短视频式的弹入、高亮、抖动 ================= */

const Punch: React.FC<{start?: number; from?: number; children: React.ReactNode; style?: React.CSSProperties}> = ({
  start = 0,
  from = 1.3,
  children,
  style,
}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: f - start, fps, config: {damping: 13, stiffness: 200, mass: 0.6}});
  const o = Math.max(0, Math.min(1, (f - start) / 4));
  return <div style={{opacity: o, transform: `scale(${from - (from - 1) * p})`, ...style}}>{children}</div>;
};

const Hl: React.FC<{c?: string; children: React.ReactNode}> = ({c = C.green, children}) => (
  <span style={{color: '#06201B', background: c, padding: '0 16px', borderRadius: 12, margin: '0 6px'}}>{children}</span>
);

const Title: React.FC<{children: React.ReactNode; start?: number; size?: number; top?: number}> = ({children, start = 0, size = 64, top = 80}) => (
  <div style={{position: 'absolute', top, width: '100%', display: 'flex', justifyContent: 'center'}}>
    <Punch start={start} from={1.15} style={{fontSize: size, fontWeight: 800, color: C.text, letterSpacing: 1, textAlign: 'center'}}>
      {children}
    </Punch>
  </div>
);

const shake = (f: number, amt: number) => `translate(${Math.sin(f * 2.7) * amt}px, ${Math.cos(f * 3.1) * amt}px)`;

const Cursor: React.FC<{x: number; y: number; down: boolean; opacity?: number}> = ({x, y, down, opacity = 1}) => (
  <div style={{position: 'absolute', left: x, top: y, opacity, transform: `scale(${down ? 0.85 : 1})`, transformOrigin: '0 0', zIndex: 20}}>
    {down && <div style={{position: 'absolute', left: -22, top: -22, width: 44, height: 44, borderRadius: 22, border: `3px solid ${C.green}`}} />}
    <svg width={40} height={48} viewBox="0 0 20 24">
      <path d="M2 1 L2 19 L6.5 15 L9.5 22 L12.5 20.7 L9.6 14 L16 14 Z" fill="#fff" stroke="#000" strokeWidth={1.3} strokeLinejoin="round" />
    </svg>
  </div>
);

/* ================= A. 0–2s 痛点开场 ================= */
export const SHook: React.FC<{duration: number}> = ({duration}) => {
  const f = useCurrentFrame();
  const op = useSceneOpacity(duration, 1, 6);
  const temp = interpolate(f, [0, 38], [45, 83], {...clamp, easing: Easing.in(Easing.quad)});
  const col = interpolateColors(temp, [45, 65, 83], [C.teal, C.warm, C.heat]);
  const amt = interpolate(f, [28, 40], [0, 7], clamp) * (f < 52 ? 1 : 0.3);
  return (
    <AbsoluteFill style={{opacity: op}}>
      <AbsoluteFill style={{background: `radial-gradient(ellipse at 50% 60%, rgba(255,106,77,${interpolate(temp, [45, 83], [0, 0.6])}) 0%, transparent 62%)`}} />
      <Title start={0}>后台只挂了个远程桌面……</Title>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', transform: shake(f, amt)}}>
        <div style={{fontSize: 300, fontWeight: 800, color: col, fontVariantNumeric: 'tabular-nums', lineHeight: 1}}>{temp.toFixed(0)}°C</div>
      </AbsoluteFill>
      <div style={{position: 'absolute', bottom: 150, width: '100%', display: 'flex', justifyContent: 'center'}}>
        <Punch start={32} style={{fontSize: 72, fontWeight: 800, color: C.text}}>
          MacBook Air 直接<Hl c={C.heat}>烫手</Hl>
        </Punch>
      </div>
    </AbsoluteFill>
  );
};

/* ================= B. 2–5s 活动监视器找不到元凶 ================= */
const rows = [
  {name: '远程桌面', cpu: '0.6', gpu: '0.3', c: '#3E7BFA', l: '远'},
  {name: '浏览器', cpu: '2.4', gpu: '1.1', c: '#E8833A', l: '浏'},
  {name: '聊天软件', cpu: '1.2', gpu: '0.0', c: '#2FB36B', l: '聊'},
  {name: 'WindowServer', cpu: '8.1', gpu: '71.3', c: '#7A8A88', l: 'W', suspect: true},
];
export const SMonitor: React.FC<{duration: number}> = ({duration}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const op = useSceneOpacity(duration, 3, 6);
  const HIT = 40;
  const hl = interpolate(f, [HIT, HIT + 6], [0, 1], clamp);
  const zoom = spring({frame: f - HIT, fps, config: {damping: 12, stiffness: 160}});
  return (
    <AbsoluteFill style={{opacity: op}}>
      {f < HIT ? (
        <Title start={0}>打开活动监视器：每个应用都很“清白”</Title>
      ) : (
        <Title start={HIT}>
          GPU <Hl c={C.heat}>71%</Hl>，全记在系统进程名下
        </Title>
      )}
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', top: 90}}>
        <div
          style={{
            width: 1100,
            borderRadius: 24,
            overflow: 'hidden',
            background: 'rgba(255,255,255,0.05)',
            border: `1px solid ${C.border}`,
            boxShadow: '0 30px 80px rgba(0,0,0,0.45)',
            transform: `scale(${1 + zoom * 0.06})`,
          }}
        >
          <div style={{display: 'flex', alignItems: 'center', gap: 10, padding: '18px 26px', borderBottom: `1px solid ${C.border}`}}>
            {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
              <div key={c} style={{width: 14, height: 14, borderRadius: 7, background: c}} />
            ))}
            <div style={{marginLeft: 18, fontSize: 24, color: C.dim}}>活动监视器</div>
            <div style={{marginLeft: 'auto', display: 'flex', gap: 0, fontSize: 24, color: C.faint}}>
              <div style={{width: 180, textAlign: 'right'}}>% CPU</div>
              <div style={{width: 180, textAlign: 'right'}}>% GPU</div>
            </div>
          </div>
          {rows.map((r, i) => {
            const a = r.suspect ? hl : 0;
            const o = Math.max(0, Math.min(1, (f - i * 3) / 5));
            return (
              <div
                key={r.name}
                style={{
                  opacity: o,
                  display: 'flex',
                  alignItems: 'center',
                  padding: '18px 26px',
                  fontSize: 34,
                  background: `rgba(255,106,77,${a * 0.2})`,
                  boxShadow: a ? `inset 6px 0 0 ${C.heat}` : undefined,
                }}
              >
                <div style={{flex: 1, display: 'flex', alignItems: 'center', gap: 20}}>
                  <AppGlyph label={r.l} color={r.c} size={50} />
                  {r.name}
                </div>
                <div style={{width: 180, textAlign: 'right', fontVariantNumeric: 'tabular-nums'}}>{r.cpu}</div>
                <div
                  style={{
                    width: 180,
                    textAlign: 'right',
                    fontVariantNumeric: 'tabular-nums',
                    fontWeight: r.suspect ? 800 : 400,
                    color: r.suspect ? interpolateColors(a, [0, 1], [C.text, C.heat]) : C.text,
                    transform: `scale(${1 + a * 0.3})`,
                    transformOrigin: 'right center',
                  }}
                >
                  {r.gpu}
                </div>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/* ================= C. 5–7.5s 灵感：游戏切后台会降帧 ================= */
export const SIdea: React.FC<{duration: number}> = ({duration}) => {
  const f = useCurrentFrame();
  const op = useSceneOpacity(duration, 3, 4);
  const fps = Math.round(interpolate(f, [14, 30], [144, 10], {...clamp, easing: ease}));
  const away = f >= 14;
  return (
    <AbsoluteFill style={{opacity: op, alignItems: 'center', justifyContent: 'center', gap: 44}}>
      <Punch start={0} from={1.15} style={{fontSize: 68, fontWeight: 800}}>
        打游戏时，切到后台会<Hl c={C.teal}>自动降帧</Hl>
      </Punch>
      <Punch start={6} from={1.1}>
        <div style={{display: 'flex', alignItems: 'center', gap: 26, padding: '22px 40px', borderRadius: 22, background: 'rgba(0,0,0,0.35)', border: `1px solid ${C.border}`}}>
          <div style={{fontSize: 30, color: away ? C.teal : C.dim, fontWeight: 600, width: 120}}>{away ? '后台' : '前台'}</div>
          <div style={{fontSize: 96, fontWeight: 800, fontVariantNumeric: 'tabular-nums', color: away ? C.teal : C.warm, width: 220, textAlign: 'right'}}>{fps}</div>
          <div style={{fontSize: 40, color: C.dim, fontWeight: 700}}>FPS</div>
        </div>
      </Punch>
      <Punch start={40} from={1.2} style={{fontSize: 76, fontWeight: 800}}>
        那别的应用，<Hl>为什么不行？</Hl>
      </Punch>
    </AbsoluteFill>
  );
};

/* ================= D. 7.5–9s Logo 落地 ================= */
export const SLogo: React.FC<{duration: number}> = ({duration}) => {
  const f = useCurrentFrame();
  const op = useSceneOpacity(duration, 1, 5);
  const flash = interpolate(f, [0, 9], [0.85, 0], clamp);
  const p = interpolate(f, [0, 14], [0, 1], {...clamp, easing: ease});
  return (
    <AbsoluteFill style={{opacity: op, alignItems: 'center', justifyContent: 'center'}}>
      <AbsoluteFill style={{background: `radial-gradient(circle at 50% 45%, rgba(67,205,210,0.22) 0%, transparent 55%)`}} />
      <div style={{display: 'flex', alignItems: 'center', gap: 40}}>
        <Leaves size={220} progress={p} />
        <Punch start={4} from={1.4}>
          <div style={{fontSize: 150, fontWeight: 900, lineHeight: 1}}>轻程</div>
          <div style={{fontSize: 56, fontWeight: 700, color: C.teal, marginTop: 10}}>TaskEase</div>
        </Punch>
      </div>
      <Punch start={14} from={1.1} style={{fontSize: 46, color: C.dim, marginTop: 40, letterSpacing: 6}}>
        你没在看的应用，就让它歇着
      </Punch>
      <AbsoluteFill style={{background: '#fff', opacity: flash}} />
    </AbsoluteFill>
  );
};

/* ================= E. 9–18s 三步用法 ================= */
const apps = [
  {name: '远程桌面', note: 'GPU 38%', c: '#3E7BFA', l: '远'},
  {name: '浏览器', note: 'CPU 31%', c: '#E8833A', l: '浏'},
  {name: '聊天软件', note: 'CPU 9%', c: '#2FB36B', l: '聊'},
  {name: '网盘同步', note: '磁盘 12 MB/s', c: '#6C63FF', l: '网'},
];
const ptAt = (f: number, keys: [number, number, number][]) => {
  const fs = keys.map((k) => k[0]);
  return [interpolate(f, fs, keys.map((k) => k[1]), {...clamp, easing: ease}), interpolate(f, fs, keys.map((k) => k[2]), {...clamp, easing: ease})];
};

const Win: React.FC<{title: string; front: number; children?: React.ReactNode}> = ({title, front, children}) => (
  <div
    style={{
      width: 600,
      height: 390,
      borderRadius: 20,
      overflow: 'hidden',
      background: interpolateColors(front, [0, 1], ['#12302C', '#1E4440']),
      border: `1px solid ${front > 0.5 ? 'rgba(177,242,147,0.5)' : C.border}`,
      boxShadow: `0 ${20 + front * 30}px ${50 + front * 50}px rgba(0,0,0,${0.3 + front * 0.3})`,
      opacity: 0.5 + front * 0.5,
    }}
  >
    <div style={{display: 'flex', alignItems: 'center', gap: 9, padding: '14px 20px', borderBottom: `1px solid ${C.border}`}}>
      {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
        <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: front > 0.5 ? c : 'rgba(255,255,255,0.2)'}} />
      ))}
      <div style={{marginLeft: 14, fontSize: 22, color: C.dim}}>{title}</div>
    </div>
    {children}
  </div>
);

export const SUsage: React.FC<{duration: number}> = ({duration}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const op = useSceneOpacity(duration, 4, 8);
  const step = f < 60 ? 0 : f < 120 ? 1 : 2;

  // 第 1、2 步
  const selected = f >= 36;
  const ruleIn = spring({frame: f - 52, fps, config: {damping: 200}, durationInFrames: 14});
  const toggled = f >= 80;
  const paused = f >= 100;
  const [cx, cy] = ptAt(f, [
    [0, 1500, 950],
    [30, 430, 395],
    [50, 430, 395],
    [74, 1676, 412],
    [86, 1676, 412],
    [96, 1350, 556],
  ]);
  const down = (f >= 33 && f < 39) || (f >= 76 && f < 82) || (f >= 97 && f < 103);
  const setupOp = interpolate(f, [114, 124], [1, 0], clamp);

  // 第 3 步（本地时间 t）
  const t = f - 120;
  const AWAY = 10;
  const PAUSE = AWAY + 36;
  const BACK = 112;
  const sw1 = interpolate(t, [AWAY, AWAY + 8], [0, 1], {...clamp, easing: ease});
  const sw2 = interpolate(t, [BACK, BACK + 8], [0, 1], {...clamp, easing: ease});
  const rdFront = 1 - sw1 + sw2;
  const counting = t >= AWAY && t < PAUSE;
  const isPaused = t >= PAUSE && t < BACK;
  const n = 3 - Math.floor((t - AWAY) / 12);
  const temp = t < PAUSE ? 83 : t < BACK ? interpolate(t, [PAUSE, PAUSE + 50], [83, 55], {...clamp, easing: ease}) : 55;
  const gpu = t < PAUSE ? 38 + Math.sin(t * 0.9) * 3 : t < BACK ? Math.max(0, 38 - (t - PAUSE) * 8) : Math.min(36, (t - BACK) * 6);
  const demoOp = interpolate(f, [120, 130], [0, 1], clamp);
  const status = t < AWAY ? '前台运行' : counting ? `${Math.max(1, n)} 秒后暂停` : isPaused ? '已暂停' : '已恢复 · 连接没断';
  const statusColor = isPaused ? C.teal : counting ? C.warm : C.green;

  const titles = [
    <>
      <Hl>①</Hl>选中想管的应用
    </>,
    <>
      <Hl>②</Hl>打开限制，选“暂停”
    </>,
    t < AWAY ? (
      <>
        <Hl>③</Hl>切到别的窗口
      </>
    ) : t < PAUSE ? (
      <>3 秒后，自动暂停</>
    ) : t < BACK ? (
      <>
        GPU <Hl c={C.teal}>归零</Hl>，温度往下掉
      </>
    ) : (
      <>
        切回来，<Hl>秒恢复</Hl>
      </>
    ),
  ];
  const titleKey = step < 2 ? step * 60 : t < AWAY ? 120 : t < PAUSE ? 120 + AWAY : t < BACK ? 120 + PAUSE : 120 + BACK;

  return (
    <AbsoluteFill style={{opacity: op}}>
      <Title key={titleKey} start={titleKey} size={62}>
        {titles[step]}
      </Title>

      {/* 第 1、2 步：应用列表 + 规则卡片 */}
      <AbsoluteFill style={{opacity: setupOp}}>
        <div style={{position: 'absolute', left: 180, top: 250, width: 680, borderRadius: 26, background: 'rgba(255,255,255,0.06)', border: `1px solid ${C.border}`, overflow: 'hidden'}}>
          <div style={{padding: '24px 30px', fontSize: 24, color: C.dim, borderBottom: `1px solid ${C.border}`}}>运行中的应用</div>
          {apps.map((a, i) => {
            const on = selected && i === 0;
            return (
              <div key={a.name} style={{display: 'flex', alignItems: 'center', gap: 20, height: 96, padding: '0 30px', background: on ? 'rgba(67,205,210,0.16)' : 'transparent', boxShadow: on ? `inset 6px 0 0 ${C.teal}` : undefined}}>
                <AppGlyph label={a.l} color={a.c} size={54} />
                <div style={{fontSize: 32, fontWeight: 600, flex: 1}}>{a.name}</div>
                <div style={{fontSize: 28, color: C.warm, fontWeight: 700}}>{a.note}</div>
              </div>
            );
          })}
        </div>

        <div style={{position: 'absolute', left: 960, top: 250, width: 780, height: 500, opacity: ruleIn, transform: `translateX(${(1 - ruleIn) * 40}px)`}}>
          <div style={{position: 'absolute', inset: 0, borderRadius: 26, background: 'rgba(255,255,255,0.07)', border: `1px solid ${C.border}`}} />
          <div style={{position: 'absolute', left: 36, top: 34, display: 'flex', alignItems: 'center', gap: 20}}>
            <AppGlyph label="远" color="#3E7BFA" size={64} />
            <div style={{fontSize: 38, fontWeight: 800}}>远程桌面</div>
          </div>
          <div style={{position: 'absolute', left: 36, top: 145, fontSize: 32, fontWeight: 700}}>限制后台资源</div>
          <div style={{position: 'absolute', left: 684, top: 144, width: 64, height: 36, borderRadius: 18, background: toggled ? C.teal : 'rgba(255,255,255,0.18)'}}>
            <div style={{position: 'absolute', left: toggled ? 32 : 4, top: 4, width: 28, height: 28, borderRadius: 14, background: '#fff'}} />
          </div>
          <div style={{position: 'absolute', left: 36, top: 230, fontSize: 24, color: C.dim}}>限制方式</div>
          <div style={{position: 'absolute', left: 36, top: 276, width: 708, height: 60, borderRadius: 14, background: 'rgba(0,0,0,0.25)', display: 'flex', opacity: toggled ? 1 : 0.4}}>
            {['限 CPU', '暂停', '降优先级'].map((m, i) => {
              const on = i === 1 && paused;
              return (
                <div key={m} style={{flex: 1, margin: 5, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 26, fontWeight: 700, background: on ? C.green : 'transparent', color: on ? C.bg : C.dim}}>
                  {m}
                </div>
              );
            })}
          </div>
          <div style={{position: 'absolute', left: 36, right: 36, top: 380, display: 'flex', justifyContent: 'space-between', fontSize: 26, opacity: toggled ? 1 : 0.4}}>
            <span style={{color: C.dim}}>生效时机</span>
            <span style={{fontWeight: 700}}>离开前台 3 秒后</span>
          </div>
          <div style={{position: 'absolute', left: 36, top: 440, width: 708, height: 8, borderRadius: 4, background: 'rgba(255,255,255,0.12)', opacity: toggled ? 1 : 0.4}}>
            <div style={{width: '18%', height: '100%', borderRadius: 4, background: C.teal}} />
          </div>
        </div>
        <Cursor x={cx} y={cy} down={down} opacity={interpolate(f, [104, 114], [1, 0], clamp)} />
      </AbsoluteFill>

      {/* 第 3 步：切走 → 暂停 → 切回 */}
      {f >= 118 && (
        <AbsoluteFill style={{opacity: demoOp}}>
          <div style={{position: 'absolute', left: 150, top: 270, width: 780, height: 560}}>
            <div style={{position: 'absolute', left: 0, top: 0, zIndex: rdFront > 0.5 ? 2 : 1, transform: `translate(${(1 - rdFront) * -24}px, ${(1 - rdFront) * -24}px) scale(${0.94 + rdFront * 0.06})`}}>
              <Win title="远程桌面 · 已连接" front={rdFront}>
                <div style={{margin: 22, height: 300, borderRadius: 12, background: 'linear-gradient(135deg,#1C4E9A,#2A79D8)', opacity: isPaused ? 0.3 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 30, color: '#fff'}}>
                  {isPaused ? '⏸ 已暂停' : '远程画面'}
                </div>
              </Win>
            </div>
            <div style={{position: 'absolute', left: 170, top: 150, zIndex: rdFront > 0.5 ? 1 : 2, transform: `scale(${0.94 + (1 - rdFront) * 0.06})`}}>
              <Win title="写周报" front={1 - rdFront}>
                <div style={{padding: 30}}>
                  {[0.9, 0.7, 0.85, 0.6, 0.78].map((w, i) => (
                    <div key={i} style={{height: 12, width: `${w * 100}%`, background: 'rgba(255,255,255,0.16)', borderRadius: 6, marginTop: 18}} />
                  ))}
                </div>
              </Win>
            </div>
            {counting && (
              <div key={n} style={{position: 'absolute', left: 0, top: 0, width: 780, height: 560, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 5}}>
                <Punch start={120 + AWAY + (3 - n) * 12} from={1.8} style={{fontSize: 260, fontWeight: 900, color: C.warm, textShadow: '0 10px 50px rgba(0,0,0,0.6)'}}>
                  {n}
                </Punch>
              </div>
            )}
          </div>

          <div style={{position: 'absolute', right: 150, top: 280, width: 700, borderRadius: 26, padding: 36, background: 'rgba(255,255,255,0.07)', border: `1px solid ${C.border}`}}>
            <div style={{display: 'flex', alignItems: 'center', gap: 20}}>
              <AppGlyph label="远" color="#3E7BFA" size={70} />
              <div>
                <div style={{fontSize: 36, fontWeight: 800}}>远程桌面</div>
                <div style={{display: 'inline-block', marginTop: 6, padding: '4px 14px', borderRadius: 10, fontSize: 24, fontWeight: 700, color: statusColor, background: `${statusColor}22`}}>{status}</div>
              </div>
            </div>
            <div style={{display: 'flex', gap: 20, marginTop: 30}}>
              {[
                ['GPU', `${gpu.toFixed(0)}%`, gpu < 2 ? C.teal : C.warm],
                ['芯片温度', `${temp.toFixed(0)}°C`, interpolateColors(temp, [55, 83], [C.green, C.heat])],
              ].map(([k, v, c]) => (
                <div key={k} style={{flex: 1, padding: '22px 26px', borderRadius: 18, background: 'rgba(0,0,0,0.2)'}}>
                  <div style={{fontSize: 24, color: C.dim}}>{k}</div>
                  <div style={{fontSize: 80, fontWeight: 800, color: c, fontVariantNumeric: 'tabular-nums', lineHeight: 1.1}}>{v}</div>
                </div>
              ))}
            </div>
          </div>
        </AbsoluteFill>
      )}

      {/* 步骤进度 */}
      <div style={{position: 'absolute', bottom: 70, width: '100%', display: 'flex', justifyContent: 'center', gap: 18}}>
        {['选应用', '设规则', '切走即生效'].map((s, i) => (
          <div key={s} style={{padding: '10px 26px', borderRadius: 999, fontSize: 26, fontWeight: 700, background: i === step ? C.green : 'rgba(255,255,255,0.06)', color: i === step ? C.bg : C.faint}}>
            {i + 1} {s}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

/* ================= F. 18–24s 能力连击 ================= */
const tiles = [
  ['📊', '实时看清占用', 'CPU · GPU · 内存 · 温度 · 网速'],
  ['🔍', '揪出藏起来的 GPU', '画面合成开销算回真正的应用'],
  ['🎛', '三种限制方式', '限 CPU · 暂停 · 降优先级，可组合'],
  ['🔇', '后台自动调低音量', '切走静音，切回原声'],
  ['🛟', '不会把应用卡死', '睡眠、退出、崩溃都会恢复'],
  ['🌐', '网络限速', '开发中', true],
] as const;

export const SFeatures: React.FC<{duration: number}> = ({duration}) => {
  const op = useSceneOpacity(duration, 4, 8);
  return (
    <AbsoluteFill style={{opacity: op}}>
      <Title start={0}>
        不止能<Hl>暂停</Hl>
      </Title>
      <div style={{position: 'absolute', top: 230, left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
        <div style={{display: 'grid', gridTemplateColumns: 'repeat(3, 520px)', gap: 30}}>
          {tiles.map(([icon, title, sub, soon], i) => (
            <Punch key={title} start={8 + i * 20} from={1.25}>
              <div
                style={{
                  height: 300,
                  borderRadius: 28,
                  padding: 36,
                  background: soon ? 'transparent' : C.card,
                  border: soon ? `2px dashed rgba(177,242,147,0.45)` : `1px solid ${C.border}`,
                  boxSizing: 'border-box',
                }}
              >
                <div style={{fontSize: 70}}>{icon}</div>
                <div style={{fontSize: 40, fontWeight: 800, marginTop: 20}}>{title}</div>
                <div style={{fontSize: 28, color: soon ? C.green : C.dim, marginTop: 12}}>{sub}</div>
              </div>
            </Punch>
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};

/* ================= G. 24–28s 结尾 ================= */
export const SEnd: React.FC<{duration: number}> = ({duration}) => {
  const f = useCurrentFrame();
  const op = useSceneOpacity(duration, 4, 16);
  const p = interpolate(f, [16, 36], [0, 1], {...clamp, easing: ease});
  return (
    <AbsoluteFill style={{opacity: op, alignItems: 'center', justifyContent: 'center'}}>
      <AbsoluteFill style={{background: `radial-gradient(circle at 50% 55%, rgba(177,242,147,0.13) 0%, transparent 55%)`}} />
      <Punch start={0} from={1.3} style={{fontSize: 120, fontWeight: 900, letterSpacing: 6}}>
        切走即静，切回如初。
      </Punch>
      <div style={{display: 'flex', alignItems: 'center', gap: 22, marginTop: 70, opacity: p}}>
        <Leaves size={90} progress={p} />
        <div style={{fontSize: 56, fontWeight: 800}}>轻程</div>
        <div style={{fontSize: 42, fontWeight: 700, color: C.teal}}>TaskEase</div>
      </div>
      <Punch start={30} from={1.1} style={{display: 'flex', gap: 16, marginTop: 40}}>
        {['免费开源', 'Apple Silicon', 'macOS 14+'].map((t) => (
          <div key={t} style={{padding: '10px 26px', borderRadius: 999, background: 'rgba(67,205,210,0.15)', color: C.teal, fontSize: 28, fontWeight: 700}}>
            {t}
          </div>
        ))}
      </Punch>
      <Punch start={40} from={1.05} style={{fontSize: 30, color: C.dim, marginTop: 34}}>
        github.com/polang233/TaskEase
      </Punch>
    </AbsoluteFill>
  );
};
