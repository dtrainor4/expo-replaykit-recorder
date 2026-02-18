export type ReplaykitRecorderState = 'idle' | 'recording' | 'stopping';

export type StartRecordingOptions = {
  mic?: boolean;
  appAudio?: boolean;
  fps?: number;
};

export type StopRecordingResult = {
  uri: string;
  durationSeconds: number;
  startedAtMs: number;
  endedAtMs: number;
};

export type ReplaykitRecorderModule = {
  isAvailable(): Promise<boolean>;
  getState(): { state: ReplaykitRecorderState };
  startRecording(options?: StartRecordingOptions): Promise<void>;
  stopRecording(): Promise<StopRecordingResult>;
  cancelRecording(): Promise<boolean>;
};
