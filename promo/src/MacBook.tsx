import React from 'react';
import {Img, OffthreadVideo, Sequence, staticFile} from 'remotion';
import {Clip, sec, Tour} from './timeline';
import {font, Lang} from './theme';

/** A MacBook Air in midnight, drawn at `width` pixels across the screen. */
export const MacBook: React.FC<{width: number; children: React.ReactNode}> = ({width, children}) => {
	const aspect = 956 / 1470;
	const side = width * 0.02;
	const topBezel = width * 0.026;
	const bottomBezel = width * 0.03;
	const lidW = width + side * 2;
	const lidH = width * aspect + topBezel + bottomBezel;
	const baseW = lidW * 1.13;
	const baseH = width * 0.032;
	return (
		<div style={{position: 'relative', width: baseW, height: lidH + baseH}}>
			<div
				style={{
					position: 'absolute',
					left: (baseW - lidW) / 2,
					top: 0,
					width: lidW,
					height: lidH,
					borderRadius: width * 0.032,
					background: 'linear-gradient(180deg, #2b2e35, #1a1c21)',
					boxShadow:
						'0 0 0 1.5px #3b3f48 inset, 0 40px 90px rgba(0,0,0,0.55), 0 0 140px rgba(255,170,70,0.10)',
				}}
			>
				<div
					style={{
						position: 'absolute',
						left: side,
						top: topBezel,
						width,
						height: width * aspect,
						borderRadius: width * 0.012,
						overflow: 'hidden',
						background: '#000',
					}}
				>
					{children}
					{/* The notch. */}
					<div
						style={{
							position: 'absolute',
							left: '50%',
							top: -1,
							width: width * 0.13,
							height: width * 0.0215,
							transform: 'translateX(-50%)',
							background: '#0a0b0d',
							borderBottomLeftRadius: width * 0.009,
							borderBottomRightRadius: width * 0.009,
						}}
					/>
					{/* Glass. */}
					<div
						style={{
							position: 'absolute',
							inset: 0,
							background: 'linear-gradient(115deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0) 38%)',
							pointerEvents: 'none',
						}}
					/>
				</div>
			</div>
			<div
				style={{
					position: 'absolute',
					left: 0,
					top: lidH - 2,
					width: baseW,
					height: baseH,
					borderRadius: `${baseH * 0.25}px ${baseH * 0.25}px ${baseH * 0.9}px ${baseH * 0.9}px`,
					background: 'linear-gradient(180deg, #4a4e57 0%, #2a2d33 35%, #17181c 100%)',
					boxShadow: '0 30px 60px rgba(0,0,0,0.6)',
				}}
			>
				<div
					style={{
						position: 'absolute',
						left: '50%',
						top: 0,
						width: baseW * 0.15,
						height: baseH * 0.32,
						transform: 'translateX(-50%)',
						background: '#1b1d22',
						borderBottomLeftRadius: baseH * 0.3,
						borderBottomRightRadius: baseH * 0.3,
					}}
				/>
			</div>
		</div>
	);
};

const MENUS: Record<Lang, string[]> = {
	zh: ['访达', '文件', '编辑', '显示', '前往', '窗口', '帮助'],
	en: ['Finder', 'File', 'Edit', 'View', 'Go', 'Window', 'Help'],
};

const CLOCK: Record<Lang, string> = {zh: '10月11日 周六 09:41', en: 'Sat Oct 11  9:41 AM'};

/** A clean menu bar, so the film shows nothing of the recording Mac's own. */
const MenuBar: React.FC<{lang: Lang; height: number}> = ({lang, height}) => {
	const fs = height * 0.44;
	return (
		<div
			style={{
				position: 'absolute',
				left: 0,
				top: 0,
				right: 0,
				height,
				display: 'flex',
				alignItems: 'center',
				padding: `0 ${height * 0.55}px`,
				gap: height * 0.62,
				background: 'rgba(250, 244, 240, 0.42)',
				backdropFilter: 'blur(18px)',
				color: 'rgba(0,0,0,0.86)',
				fontFamily: font.system,
				fontSize: fs,
			}}
		>
			<svg width={fs * 0.95} height={fs * 1.1} viewBox="0 0 17 20">
				<path
					fill="rgba(0,0,0,0.86)"
					d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9-.1 0-2.7-1-2.7-4.1zM11.6 3c.7-.9 1.2-2 1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.2.1 2.3-.6 3.1-1.5z"
				/>
			</svg>
			{MENUS[lang].map((m, i) => (
				<span key={m} style={{fontWeight: i === 0 ? 700 : 500}}>
					{m}
				</span>
			))}
			<div style={{flex: 1}} />
			{/* SunMemo's own icon in the menu bar: a line with two cards. */}
			<svg width={fs * 1.3} height={fs * 1.05} viewBox="0 0 22 18">
				<path d="M.5 3.5C7 2.8 15 2.8 21.5 3.5" stroke="#000" strokeWidth="1.3" fill="none" />
				<rect x="2.5" y="5" width="8" height="10" rx="1.2" stroke="#000" strokeWidth="1.2" fill="none" />
				<rect x="12" y="5" width="8" height="8" rx="1.2" stroke="#000" strokeWidth="1.2" fill="none" />
			</svg>
			<svg width={fs * 1.2} height={fs} viewBox="0 0 20 15">
				<path d="M10 14l3-3.5a4.6 4.6 0 00-6 0zM4.3 7.6a8.4 8.4 0 0111.4 0l1.6-1.8a10.8 10.8 0 00-14.6 0zM1 4.2a13.3 13.3 0 0118 0L20.4 2.6a15.5 15.5 0 00-20.8 0z" fill="#000" />
			</svg>
			<svg width={fs * 1.7} height={fs * 0.85} viewBox="0 0 27 13">
				<rect x=".5" y=".5" width="23" height="12" rx="3.5" stroke="rgba(0,0,0,0.5)" fill="none" />
				<rect x="2" y="2" width="17" height="9" rx="2" fill="#000" />
				<rect x="24.5" y="4.5" width="1.6" height="4" rx=".8" fill="rgba(0,0,0,0.5)" />
			</svg>
			<span style={{fontWeight: 500}}>{CLOCK[lang]}</span>
		</div>
	);
};

/**
 * The laptop's screen: the backdrop, the recorded tour cut into clips, and a
 * clean menu bar. Laid out in the recording's points, scaled to `width`.
 */
export const Screen: React.FC<{tour: Tour; clips: Clip[]; lang: Lang; width: number}> = ({tour, clips, lang, width}) => {
	const [sw, sh] = tour.screen;
	const [vx, vy, vw, vh] = tour.visible;
	const k = width / sw;
	return (
		<div style={{position: 'absolute', inset: 0}}>
			<div style={{position: 'absolute', left: 0, top: 0, width: sw, height: sh, transform: `scale(${k})`, transformOrigin: '0 0'}}>
				<Img src={staticFile('backdrop.jpg')} style={{position: 'absolute', inset: 0, width: sw, height: sh, objectFit: 'cover'}} />
				{clips.map((c, i) => (
					<Sequence key={i} from={sec(c.at)} durationInFrames={sec(c.length)} layout="none">
						<OffthreadVideo
							src={staticFile(`clips/screen-${lang === 'zh' ? 'zh-Hans' : 'en'}.mp4`)}
							trimBefore={sec(c.from)}
							playbackRate={c.rate}
							muted
							style={{position: 'absolute', left: vx, top: vy, width: vw, height: vh}}
						/>
					</Sequence>
				))}
				<MenuBar lang={lang} height={vy} />
			</div>
		</div>
	);
};
