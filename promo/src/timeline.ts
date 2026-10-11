import {FPS, Lang} from './theme';
import zhTour from './data/tour-zh-Hans.json';
import enTour from './data/tour-en.json';

export type Tour = {
	screen: [number, number];
	visible: [number, number, number, number];
	footage: [number, number];
	markers: {event: string; t: number; at?: number; rect?: number[]; rects?: number[][]}[];
};

export const tours: Record<Lang, Tour> = {zh: zhTour as unknown as Tour, en: enTour as unknown as Tour};

export const sec = (s: number) => Math.round(s * FPS);

/** The film, in seconds. Each beat is one selling point. */
export const T = {
	introEnd: 2.8,
	mockIn: 3.0,
	beats: [
		{start: 3.8, end: 7.6},
		{start: 7.6, end: 11.4},
		{start: 11.4, end: 16.4},
		{start: 16.4, end: 22.6},
	],
	outro: 22.6,
	total: 27.6,
};

export const first = (tour: Tour, event: string) => {
	const m = tour.markers.find((x) => x.event === event);
	if (!m) throw new Error(`No ${event} in the tour`);
	return m.t;
};

/** A piece of the tour shown on the laptop: from `from` seconds of the
 * tour, at `rate`, starting at film time `at` for `length` seconds. */
export type Clip = {at: number; length: number; from: number; rate: number};

export const clips = (tour: Tour): Clip[] => {
	const [b1, b2, b3, b4] = T.beats;
	const sweep = first(tour, 'sweep_start');
	return [
		// The empty backdrop while the laptop arrives, then the line comes down.
		{at: T.mockIn, length: b1.end - T.mockIn, from: first(tour, 'line_down') - 0.6 - (b1.start - T.mockIn), rate: 1},
		{at: b2.start, length: b2.end - b2.start, from: first(tour, 'shot_fly') - 0.75, rate: 1},
		{at: b3.start, length: b3.end - b3.start, from: first(tour, 'editor_open') - 0.25, rate: 1.6},
		{at: b4.start, length: 3.0, from: first(tour, 'cascade_start') - 0.2, rate: 1.35},
		{at: b4.start + 3.0, length: b4.end - b4.start - 3.0 + 1.0, from: sweep - 0.15, rate: 1},
	];
};
