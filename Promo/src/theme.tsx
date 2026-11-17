import React from 'react';
import {Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';

export const C = {
  bg: '#061C1A',
  bg2: '#0B2D29',
  teal: '#43CDD2',
  green: '#B1F293',
  text: '#EAF6F3',
  dim: 'rgba(234,246,243,0.58)',
  faint: 'rgba(234,246,243,0.32)',
  heat: '#FF6A4D',
  warm: '#FFB547',
  card: 'rgba(255,255,255,0.055)',
  border: 'rgba(255,255,255,0.10)',
};

export const FONT = '-apple-system, "SF Pro Display", "PingFang SC", "Helvetica Neue", sans-serif';

export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
export const ease = Easing.bezier(0.22, 1, 0.36, 1);

/** 场景整体淡入淡出 */
export const useSceneOpacity = (duration: number, fadeIn = 12, fadeOut = 12) => {
  const f = useCurrentFrame();
  return Math.min(
    interpolate(f, [0, fadeIn], [0, 1], clamp),
    interpolate(f, [duration - fadeOut, duration], [1, 0], clamp),
  );
};

/** 从 start 帧开始，向上浮入 */
export const Rise: React.FC<{
  start?: number;
  dist?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({start = 0, dist = 28, children, style}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: f - start, fps, config: {damping: 200}, durationInFrames: 24});
  return (
    <div style={{opacity: p, transform: `translateY(${(1 - p) * dist}px)`, ...style}}>{children}</div>
  );
};

export const Leaves: React.FC<{size: number; progress?: number; rear?: string; front?: string}> = ({
  size,
  progress = 1,
  rear = C.teal,
  front = C.green,
}) => {
  const rp = Math.min(1, progress * 1.6);
  const fp = Math.max(0, Math.min(1, progress * 1.6 - 0.45));
  return (
    <svg width={size} height={size} viewBox="0 0 640 640">
      <path
        fill={rear}
        opacity={rp}
        transform={`translate(${(1 - rp) * -90} ${(1 - rp) * 40})`}
        d="M 105 449 C 90 449 80 435 80 416 L 80 273 C 80 222 106 184 139 162 C 175 140 217 129 260 123 L 393 105 C 411 102 424 114 424 134 L 424 183 L 337 199 C 242 216 188 254 188 392 L 191 434 L 105 449 Z"
      />
      <path
        fill={front}
        opacity={fp}
        transform={`translate(${(1 - fp) * 90} ${(1 - fp) * -40})`}
        d="M 237 535 C 222 535 209 524 209 502 L 209 392 C 209 321 238 280 286 247 C 313 229 353 218 401 210 L 525 183 C 547 180 561 190 561 211 L 561 313 C 561 420 516 479 434 501 C 376 515 311 523 237 535 Z"
      />
    </svg>
  );
};

export const AppGlyph: React.FC<{label: string; color: string; size?: number}> = ({label, color, size = 64}) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.24,
      background: `linear-gradient(145deg, ${color}, ${color}AA)`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: '#fff',
      fontWeight: 700,
      fontSize: size * 0.42,
      boxShadow: '0 6px 18px rgba(0,0,0,0.35)',
      flexShrink: 0,
    }}
  >
    {label}
  </div>
);

export const Caption: React.FC<{children: React.ReactNode; start?: number; size?: number; color?: string; style?: React.CSSProperties}> = ({
  children,
  start = 0,
  size = 52,
  color = C.text,
  style,
}) => (
  <Rise start={start} style={{fontSize: size, fontWeight: 600, color, letterSpacing: 1, ...style}}>
    {children}
  </Rise>
);
