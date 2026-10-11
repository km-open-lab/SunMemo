import {Lang} from './theme';

export const copy: Record<
	Lang,
	{label: string; beats: string[][]; name: string; latin?: string; tagline: string; footer: string}
> = {
	zh: {
		label: '晾想法 · SUNMEMO',
		beats: [
			['屏幕顶上，', '一根晾衣绳。'],
			['截个图，', '自己就挂上去。'],
			['想到就记，', '⌃⌥N 一下。'],
			['挂满几十张，', '也不乱。'],
		],
		name: '晾想法',
		latin: 'SUNMEMO',
		tagline: '把没做完的想法，晾在阳光下。',
		footer: '免费开源 · MACOS 13+ · GITHUB.COM/KM-OPEN-LAB/SUNMEMO',
	},
	en: {
		label: 'SUNMEMO FOR MAC',
		beats: [
			['A clothesline', 'for your screen.'],
			['Take a screenshot.', 'It hangs itself.'],
			['Jot it down.', '⌃⌥N. Done.'],
			['Hang dozens.', 'Never a mess.'],
		],
		name: 'SunMemo',
		tagline: 'Hang your unfinished thoughts in the sun.',
		footer: 'FREE & OPEN SOURCE · MACOS 13+ · GITHUB.COM/KM-OPEN-LAB/SUNMEMO',
	},
};
