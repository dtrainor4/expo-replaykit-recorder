import { Platform, UnavailabilityError } from 'expo-modules-core';

import ExpoReplaykitRecorderModule from './ExpoReplaykitRecorderModule';
import type {
  ReplaykitRecorderState,
  StartRecordingOptions,
  StopRecordingResult,
} from './ExpoReplaykitRecorder.types';

export type { ReplaykitRecorderState, StartRecordingOptions, StopRecordingResult };

function getModuleOrThrow() {
  if (Platform.OS !== 'ios') {
    throw new UnavailabilityError('@swingspace/expo-replaykit-recorder', 'iOS ReplayKit recording');
  }
  if (!ExpoReplaykitRecorderModule) {
    throw new UnavailabilityError('@swingspace/expo-replaykit-recorder', 'native module');
  }
  return ExpoReplaykitRecorderModule;
}

export async function isAvailableAsync(): Promise<boolean> {
  if (Platform.OS !== 'ios' || !ExpoReplaykitRecorderModule) {
    return false;
  }
  return ExpoReplaykitRecorderModule.isAvailable();
}

export function getState(): { state: ReplaykitRecorderState } {
  if (Platform.OS !== 'ios' || !ExpoReplaykitRecorderModule) {
    return { state: 'idle' };
  }
  return ExpoReplaykitRecorderModule.getState();
}

export async function startRecordingAsync(options?: StartRecordingOptions): Promise<void> {
  const module = getModuleOrThrow();
  return module.startRecording(options);
}

export async function stopRecordingAsync(): Promise<StopRecordingResult> {
  const module = getModuleOrThrow();
  return module.stopRecording();
}

export async function cancelRecordingAsync(): Promise<boolean> {
  if (Platform.OS !== 'ios' || !ExpoReplaykitRecorderModule) {
    return false;
  }
  return ExpoReplaykitRecorderModule.cancelRecording();
}

const ReplaykitRecorder = {
  isAvailableAsync,
  getState,
  startRecordingAsync,
  stopRecordingAsync,
  cancelRecordingAsync,
};

export default ReplaykitRecorder;
