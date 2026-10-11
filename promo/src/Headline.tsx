import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig, Easing} from 'remotion';
import {color, font, Lang} from './theme';

const PUNCT = /^[.,?!。，？！]$/;

/** Words for English; characters for Chinese, keeping key names whole. */
const tokens = (line: string, lang: Lang): string[] => {
	if (lang === 'en') return line.split(/(?<= )/);
	return line.match(/⌃⌥[A-Z]|[A-Za-z0-9.]+|\s|./gu) ?? [];
};

/**
 * Two short lines that type in word by word, with the closing mark in the
 * sun's color. Leaves by lifting and fading at `out` (frames from its start).
 */
export const Headline: React.FC<{lines: string[]; lang: Lang; out: number; size?: number}> = ({
	lines,
	lang,
	out,
	size = lang === 'zh' ? 84 : 92,
}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const step = lang === 'zh' ? 2.6 : 4.5;
	const leave = interpolate(frame, [out - 12, out], [0, 1], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
		easing: Easing.in(Easing.cubic),
	});
	let index = 0;
	return (
		<div
			style={{
				fontFamily: font.head(lang),
				fontWeight: lang === 'zh' ? 600 : 800,
				fontSize: size,
				lineHeight: 1.14,
				letterSpacing: lang === 'zh' ? '0.02em' : '-0.025em',
				color: color.ink,
				opacity: 1 - leave,
				transform: `translateY(${-24 * leave}px)`,
				filter: leave > 0 ? `blur(${leave * 6}px)` : undefined,
			}}
		>
			{lines.map((line, li) => (
				<div key={li} style={{whiteSpace: 'pre'}}>
					{tokens(line, lang).map((tok, ti) => {
						const delay = index++ * step + li * 10;
						const p = spring({frame: frame - delay, fps, config: {damping: 18, stiffness: 140, mass: 0.7}});
						const accent = PUNCT.test(tok.trim()) && ti === tokens(line, lang).length - 1;
						const pop = accent ? spring({frame: frame - delay - 2, fps, config: {damping: 7, stiffness: 220}}) : p;
						return (
							<span
								key={ti}
								style={{
									display: 'inline-block',
									opacity: Math.min(1, p * 1.3),
									transform: accent
										? `scale(${0.2 + 0.8 * pop})`
										: `translateY(${(1 - p) * 0.45 * size}px)`,
									filter: p < 0.98 ? `blur(${(1 - p) * 10}px)` : undefined,
									color: accent ? color.sun : undefined,
									textShadow: accent ? `0 0 24px ${color.sun}99` : undefined,
									transformOrigin: '50% 80%',
								}}
							>
								{tok}
							</span>
						);
					})}
				</div>
			))}
		</div>
	);
};

/** The small monospaced label, typed out with a block cursor. */
export const Label: React.FC<{text: string; start?: number}> = ({text, start = 0}) => {
	const frame = useCurrentFrame() - start;
	const shown = Math.max(0, Math.min(text.length, Math.floor(frame / 2.2)));
	const typing = shown < text.length;
	const blink = typing || Math.floor(frame / 18) % 2 === 0;
	return (
		<div
			style={{
				fontFamily: font.mono,
				fontWeight: 500,
				fontSize: 22,
				letterSpacing: '0.32em',
				color: color.inkSoft,
				whiteSpace: 'pre',
				display: 'flex',
				alignItems: 'center',
			}}
		>
			{text.slice(0, shown)}
			{frame >= 0 && frame < text.length * 2.2 + 70 ? (
				<span style={{display: 'inline-block', width: 12, height: 22, marginLeft: 4, background: color.sun, opacity: blink ? 0.9 : 0}} />
			) : null}
		</div>
	);
};
