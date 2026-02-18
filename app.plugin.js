const { IOSConfig, createRunOncePlugin } = require('expo/config-plugins');
const pkg = require('./package.json');

const DEFAULT_MICROPHONE_PERMISSION =
  'Allow $(PRODUCT_NAME) to access your microphone while recording screen review sessions.';

const withReplaykitRecorder = (config, props = {}) => {
  const microphonePermission = props.microphonePermission || DEFAULT_MICROPHONE_PERMISSION;

  return IOSConfig.Permissions.createPermissionsPlugin({
    NSMicrophoneUsageDescription: DEFAULT_MICROPHONE_PERMISSION,
  })(config, {
    NSMicrophoneUsageDescription: microphonePermission,
  });
};

module.exports = createRunOncePlugin(withReplaykitRecorder, pkg.name, pkg.version);
