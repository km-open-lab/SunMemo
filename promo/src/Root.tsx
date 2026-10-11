import React from 'react';
import {Composition} from 'remotion';
import {Promo} from './Promo';
import {FPS, HEIGHT, WIDTH} from './theme';
import {sec, T} from './timeline';

export const RemotionRoot: React.FC = () => (
	<>
		<Composition id="Promo-zh" component={Promo} defaultProps={{lang: 'zh' as const}} durationInFrames={sec(T.total)} fps={FPS} width={WIDTH} height={HEIGHT} />
		<Composition id="Promo-en" component={Promo} defaultProps={{lang: 'en' as const}} durationInFrames={sec(T.total)} fps={FPS} width={WIDTH} height={HEIGHT} />
	</>
);
