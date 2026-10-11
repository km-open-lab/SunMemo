import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {color} from './theme';

/** Warm black with a faint grid of rounded dots, a sunny glow and a vignette. */
export const Background: React.FC<{glowX?: number; glowY?: number}> = ({glowX = 64, glowY = 46}) => {
	const frame = useCurrentFrame();
	const breathe = interpolate(Math.sin(frame / 70), [-1, 1], [0.85, 1.1]);
	const grid = encodeURIComponent(
		`<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26"><rect x="10" y="10" width="7" height="7" rx="1.8" fill="rgba(255,240,220,0.055)"/></svg>`,
	);
	return (
		<AbsoluteFill style={{background: color.night}}>
			<AbsoluteFill style={{backgroundImage: `url("data:image/svg+xml,${grid}")`}} />
			<AbsoluteFill
				style={{
					background: `radial-gradient(ellipse 52% 60% at ${glowX}% ${glowY}%, rgba(255, 176, 64, ${0.17 * breathe}), rgba(255, 140, 60, 0.05) 45%, transparent 70%)`,
				}}
			/>
			<AbsoluteFill
				style={{background: 'radial-gradient(ellipse 85% 80% at 50% 48%, transparent 55%, rgba(0,0,0,0.65) 100%)'}}
			/>
		</AbsoluteFill>
	);
};
