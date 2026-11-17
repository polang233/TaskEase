import React from 'react';
import {AbsoluteFill, Composition, Sequence, staticFile, Audio} from 'remotion';
import {C, FONT} from './theme';
import {SEnd, SFeatures, SHook, SIdea, SLogo, SMonitor, SUsage} from './short';

// 120 BPM：每拍 15 帧，场景切换都落在拍点上
const scenes: [React.FC<{duration: number}>, number][] = [
  [SHook, 60],
  [SMonitor, 90],
  [SIdea, 75],
  [SLogo, 45],
  [SUsage, 270],
  [SFeatures, 180],
  [SEnd, 120],
];
export const TOTAL = scenes.reduce((s, [, d]) => s + d, 0);

const Promo: React.FC = () => {
  let at = 0;
  return (
    <AbsoluteFill style={{background: `radial-gradient(ellipse at 50% 0%, ${C.bg2} 0%, ${C.bg} 70%)`, fontFamily: FONT, color: C.text}}>
      <Audio src={staticFile('music.wav')} volume={(f) => Math.min(1, f / 20, (TOTAL - f) / 20)} />
      {scenes.map(([S, d], i) => {
        const from = at;
        at += d;
        return (
          <Sequence key={i} from={from} durationInFrames={d}>
            <S duration={d} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

export const Root: React.FC = () => (
  <Composition id="Promo" component={Promo} durationInFrames={TOTAL} fps={30} width={1920} height={1080} />
);
