import { requireOptionalNativeModule } from 'expo-modules-core';

import type { ReplaykitRecorderModule } from './ExpoReplaykitRecorder.types';

export default requireOptionalNativeModule<ReplaykitRecorderModule>('ExpoReplaykitRecorder');
