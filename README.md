# @dtrainor4/expo-replaykit-recorder

Standalone Expo module for iOS ReplayKit screen recording with microphone and app audio capture.

## Status

- Platform: iOS only
- Architecture: Expo Modules API
- Current scope: module scaffold + native recording implementation

## Features

- `isAvailableAsync()` check
- `startRecordingAsync({ mic, appAudio })`
- `stopRecordingAsync()` returns `{ uri, durationSeconds, startedAtMs, endedAtMs }`
- `cancelRecordingAsync()`
- `getState()` reports `idle | recording | stopping`

## Install (future app integration)

1. Add dependency (example via git):
```bash
npm install git+ssh://git@github.com/dtrainor4/expo-replaykit-recorder.git
```

2. Add plugin to `app.json`:
```json
{
  "expo": {
    "plugins": [
      [
        "@dtrainor4/expo-replaykit-recorder",
        {
          "microphonePermission": "Allow $(PRODUCT_NAME) to access your microphone while recording."
        }
      ]
    ]
  }
}
```

3. Rebuild native app:
```bash
eas build --platform ios
```

## JS API

```ts
import ReplaykitRecorder from '@dtrainor4/expo-replaykit-recorder';

const available = await ReplaykitRecorder.isAvailableAsync();
if (!available) return;

await ReplaykitRecorder.startRecordingAsync({ mic: true, appAudio: true });
const result = await ReplaykitRecorder.stopRecordingAsync();
console.log(result.uri);
```

## Development

```bash
npm install
npm run build
```

## Notes

- ReplayKit does not work on iOS Simulator.
- Native module changes require a new iOS build (not OTA-only).
