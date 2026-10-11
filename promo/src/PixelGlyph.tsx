import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {rand} from './theme';

// The app icon as a dot-matrix picture: a clothesline with a memo and a
// photo pegged to it.
const MAP = [
	'........................',
	'rrrr................rrrr',
	'....rrrprrrrrrrrrprrrr..',
	'.......p.........p......',
	'..yyyyyyyyy..wwwwwwww...',
	'..yllllllly..wssssssw...',
	'..yyyyyyyyy..wsssuusw...',
	'..yllllllyy..wsssuusw...',
	'..yyyyyyyyy..wssmsssw...',
	'..ylllllyyy..wsmmmsmw...',
	'..yyyyyyyyy..wmmmmmmw...',
	'..yyyyyyyyy..wwwwwwww...',
	'.............wwwwwwww...',
];

const COLORS: Record<string, string> = {
	r: '#d9cfc0',
	p: '#c08a4e',
	y: '#ffd25a',
	l: '#b5791c',
	w: '#f4efe6',
	s: '#8ec5ff',
	u: '#ffb547',
	m: '#4a5878',
};

type Cell = {x: number; y: number; c: string; part: 'rope' | 'memo' | 'photo'};

const CELLS: Cell[] = MAP.flatMap((row, y) =>
	[...row].flatMap((c, x) => {
		if (c === '.') return [];
		const part = c === 'r' || c === 'p' ? 'rope' : x < 12 ? 'memo' : 'photo';
		return [{x, y, c, part} as Cell];
	}),
);

export const GLYPH_COLS = MAP[0].length;
export const GLYPH_ROWS = MAP.length;

/**
 * Lights up cell by cell from `start`: the rope from left to right, then
 * the two cards drop onto it. `pitch` is the cell spacing in pixels.
 */
export const PixelGlyph: React.FC<{start?: number; pitch: number; instant?: boolean; glow?: number}> = ({
	start = 0,
	pitch,
	instant = false,
	glow = 1,
}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const size = pitch * 0.84;
	const t = frame - start;

	return (
		<div style={{position: 'relative', width: GLYPH_COLS * pitch, height: GLYPH_ROWS * pitch}}>
			{CELLS.map((cell, i) => {
				const seed = cell.x * 31 + cell.y * 17;
				const delay =
					cell.part === 'rope'
						? cell.x * 1.1 + rand(seed) * 3
						: 26 + (cell.part === 'photo' ? 8 : 0) + cell.y * 1.6 + rand(seed) * 10;
				const p = instant ? 1 : spring({frame: t - delay, fps, config: {damping: 14, stiffness: 160, mass: 0.6}});
				const drop = cell.part === 'rope' ? 0 : (1 - p) * -pitch * 3;
				// A few cells flicker once as they come on, like a dot-matrix sign.
				const flicker =
					!instant && rand(seed + 5) > 0.8
						? interpolate(t - delay, [6, 9, 12], [1, 0.25, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})
						: 1;
				const opacity = Math.min(1, p * 1.4) * flicker;
				if (opacity <= 0.001) return null;
				const c = COLORS[cell.c];
				return (
					<div
						key={i}
						style={{
							position: 'absolute',
							left: cell.x * pitch,
							top: cell.y * pitch + drop,
							width: size,
							height: size,
							borderRadius: size * 0.24,
							background: c,
							opacity,
							transform: `scale(${0.5 + 0.5 * Math.min(1, p)})`,
							boxShadow: glow > 0 ? `0 0 ${pitch * 0.7 * glow}px ${c}66` : undefined,
						}}
					/>
				);
			})}
		</div>
	);
};
