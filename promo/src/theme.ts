import {loadFont as loadJakarta} from '@remotion/google-fonts/PlusJakartaSans';
import {loadFont as loadMono} from '@remotion/google-fonts/JetBrainsMono';

const jakarta = loadJakarta('normal', {weights: ['600', '800'], subsets: ['latin']});
const mono = loadMono('normal', {weights: ['500'], subsets: ['latin']});

export const FPS = 60;
export const WIDTH = 1920;
export const HEIGHT = 1080;

export const color = {
	night: '#0c0b0a',
	ink: '#f5f1ea',
	inkSoft: 'rgba(245, 241, 234, 0.62)',
	sun: '#ffc83d',
	sunset: '#ff9d4d',
	glow: 'rgba(255, 176, 64, 0.16)',
};

export type Lang = 'zh' | 'en';

export const font = {
	mono: `${mono.fontFamily}, ui-monospace, monospace`,
	head: (lang: Lang) =>
		lang === 'zh'
			? `${jakarta.fontFamily}, "PingFang SC", sans-serif`
			: `${jakarta.fontFamily}, "PingFang SC", sans-serif`,
	system: '-apple-system, "SF Pro Text", "PingFang SC", sans-serif',
};

/** Deterministic noise in [0, 1) from an integer seed. */
export const rand = (seed: number) => {
	let t = (seed * 0x6d2b79f5) >>> 0;
	t = Math.imul(t ^ (t >>> 15), t | 1);
	t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
	return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
