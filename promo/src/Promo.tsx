import React from 'react';
import {AbsoluteFill, Easing, interpolate, Sequence, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Background} from './Background';
import {copy} from './copy';
import {Headline, Label} from './Headline';
import {MacBook, Screen} from './MacBook';
import {GLYPH_COLS, GLYPH_ROWS, PixelGlyph} from './PixelGlyph';
import {color, font, Lang} from './theme';
import {clips, sec, T, tours} from './timeline';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ease = Easing.bezier(0.65, 0, 0.35, 1);

// Layout, in pixels of the 1920 × 1080 frame.
const COLUMN_X = 150;
const SMALL_PITCH = 9;
const BIG_PITCH = 26;
const GLYPH_TOP = 300;
const LABEL_TOP = GLYPH_TOP + GLYPH_ROWS * SMALL_PITCH + 26;
const HEAD_TOP = LABEL_TOP + 58;
const SCREEN_W = 1120;
const LAPTOP_X = 770;
const LAPTOP_Y = 168;

/** Where the camera looks on the laptop in each beat: a push-in and its focus. */
const CAMERA = [
	{zoom: [1.0, 1.12], origin: '8% 2%'},
	{zoom: [1.42, 1.52], origin: '8% 4%'},
	{zoom: [1.36, 1.46], origin: '6% 34%'},
	{zoom: [1.6, 1.72], origin: '8% 2%'},
];

export const Promo: React.FC<{lang: Lang}> = ({lang}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const tour = tours[lang];
	const text = copy[lang];
	const t = frame / fps;

	// The glyph: big in the middle, then up to the top of the text column.
	const move = interpolate(t, [T.introEnd, T.introEnd + 0.9], [0, 1], {...clamp, easing: ease});
	const bigW = GLYPH_COLS * BIG_PITCH;
	const bigH = GLYPH_ROWS * BIG_PITCH;
	const glyphScale = interpolate(move, [0, 1], [1, SMALL_PITCH / BIG_PITCH]);
	const glyphX = interpolate(move, [0, 1], [(1920 - bigW) / 2, COLUMN_X]);
	const glyphY = interpolate(move, [0, 1], [(1080 - bigH) / 2 - 60, GLYPH_TOP]);

	// The laptop: a sun-colored card slides in, then turns into the MacBook.
	const slide = spring({frame: frame - sec(T.mockIn - 0.4), fps, config: {damping: 20, stiffness: 90, mass: 0.9}});
	const reveal = interpolate(t, [T.mockIn + 0.25, T.mockIn + 0.75], [0, 1], {...clamp, easing: ease});
	const leave = interpolate(t, [T.outro, T.outro + 0.6], [0, 1], {...clamp, easing: Easing.in(Easing.cubic)});
	const beat = T.beats.findIndex((b) => t >= b.start && t < b.end);
	const cam = CAMERA[Math.max(0, beat)];
	const inBeat = beat >= 0 ? (t - T.beats[beat].start) / (T.beats[beat].end - T.beats[beat].start) : 0;
	let zoom = beat >= 0 ? interpolate(inBeat, [0, 1], cam.zoom, {easing: Easing.out(Easing.quad)}) : 1;
	// A quick push at each cut hides the jump in the footage.
	const sinceCut = beat > 0 ? t - T.beats[beat].start : 99;
	const kick = interpolate(sinceCut, [0, 0.07, 0.35], [1, 0, 0], clamp);
	zoom *= 1 + 0.05 * kick;
	const float = Math.sin(frame / 55) * 4;

	const outroT = t - T.outro;
	const textOut = interpolate(t, [T.outro - 0.1, T.outro + 0.3], [1, 0], clamp);

	return (
		<AbsoluteFill style={{overflow: 'hidden'}}>
			<Background glowX={interpolate(move, [0, 1], [50, 64])} glowY={46} />

			{/* The laptop. */}
			<AbsoluteFill style={{perspective: 2600}}>
				<div
					style={{
						position: 'absolute',
						left: LAPTOP_X + (1 - slide) * 1300,
						top: LAPTOP_Y + float + leave * 950,
						transform: `rotateY(-13deg) rotateX(3deg) scale(${zoom})`,
						transformOrigin: cam.origin,
						filter: leave > 0 || kick > 0 ? `blur(${leave * 14 + kick * 5}px)` : undefined,
					}}
				>
					<div style={{opacity: reveal}}>
						<MacBook width={SCREEN_W}>
							<Screen tour={tour} clips={clips(tour)} lang={lang} width={SCREEN_W} />
						</MacBook>
					</div>
					{reveal < 1 ? (
						<div
							style={{
								position: 'absolute',
								left: 74,
								top: 0,
								width: SCREEN_W + 45,
								height: SCREEN_W * 0.706,
								borderRadius: 36,
								background: `linear-gradient(160deg, ${color.sun}, ${color.sunset})`,
								opacity: 1 - reveal,
								boxShadow: `0 0 120px ${color.sun}55`,
							}}
						/>
					) : null}
				</div>
			</AbsoluteFill>

			{/* The glyph, and its label: under it in the opening, then in the column. */}
			{t < T.outro + 0.4 ? (
				<div
					style={{
						position: 'absolute',
						left: glyphX,
						top: glyphY,
						transform: `scale(${glyphScale})`,
						transformOrigin: '0 0',
						opacity: textOut,
					}}
				>
					<PixelGlyph pitch={BIG_PITCH} start={8} glow={1.2} />
				</div>
			) : null}
			<div
				style={{
					position: 'absolute',
					top: (1080 + bigH) / 2 - 20,
					width: '100%',
					display: 'flex',
					justifyContent: 'center',
					opacity: interpolate(t, [T.introEnd - 0.2, T.introEnd + 0.1], [1, 0], clamp),
				}}
			>
				<Label text={text.label} start={sec(1.3)} />
			</div>
			<div style={{position: 'absolute', left: COLUMN_X, top: LABEL_TOP, opacity: textOut}}>
				<Label text={text.label} start={sec(T.introEnd + 0.6)} />
			</div>

			{/* One headline per beat. */}
			{T.beats.map((b, i) => (
				<Sequence key={i} from={sec(b.start + 0.15)} durationInFrames={sec(b.end - b.start)} layout="none">
					<div style={{position: 'absolute', left: COLUMN_X, top: HEAD_TOP, width: 720}}>
						<Headline lines={text.beats[i]} lang={lang} out={sec(b.end - b.start - 0.15)} />
					</div>
				</Sequence>
			))}

			{/* Closing card. */}
			{outroT > 0 ? <Outro lang={lang} t={outroT} /> : null}
		</AbsoluteFill>
	);
};

const Outro: React.FC<{lang: Lang; t: number}> = ({lang, t}) => {
	const {fps} = useVideoConfig();
	const text = copy[lang];
	const f = Math.round(t * fps);
	const pitch = 17;
	const appear = (delay: number) => {
		const p = spring({frame: f - sec(delay), fps, config: {damping: 20, stiffness: 120}});
		return {opacity: Math.min(1, p * 1.2), transform: `translateY(${(1 - p) * 24}px)`, filter: p < 0.98 ? `blur(${(1 - p) * 8}px)` : undefined};
	};
	return (
		<AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', flexDirection: 'column'}}>
			<PixelGlyph pitch={pitch} start={sec(T.outro + 0.25)} glow={1.3} />
			<div style={{height: 46}} />
			<div
				style={{
					fontFamily: font.head(lang),
					fontWeight: lang === 'zh' ? 600 : 800,
					fontSize: lang === 'zh' ? 104 : 116,
					letterSpacing: lang === 'zh' ? '0.08em' : '-0.03em',
					color: color.ink,
					...appear(0.9),
				}}
			>
				{text.name}
				<span style={{color: color.sun, textShadow: `0 0 28px ${color.sun}aa`}}>{lang === 'zh' ? '' : '.'}</span>
			</div>
			{text.latin ? (
				<div style={{fontFamily: font.mono, fontSize: 22, letterSpacing: '0.6em', color: color.sun, marginTop: 6, ...appear(1.05)}}>
					{text.latin}
				</div>
			) : null}
			<div
				style={{
					fontFamily: font.head(lang),
					fontWeight: 600,
					fontSize: 34,
					color: color.inkSoft,
					marginTop: lang === 'zh' ? 26 : 18,
					letterSpacing: lang === 'zh' ? '0.06em' : '-0.01em',
					...appear(1.2),
				}}
			>
				{text.tagline}
			</div>
			<div style={{position: 'absolute', bottom: 92, fontFamily: font.mono, fontSize: 18, letterSpacing: '0.24em', color: 'rgba(245,241,234,0.42)', ...appear(1.6)}}>
				{text.footer}
			</div>
		</AbsoluteFill>
	);
};
