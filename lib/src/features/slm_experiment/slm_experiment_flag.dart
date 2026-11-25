/// Set only by the test builds (`--dart-define=SLM_EXPERIMENT=true` in
/// ios-build.yml, and test-apk.yml off main), never by release builds. When
/// off (the default) the experiment's row, screen and model code are
/// constant-folded away, and no build step adds the model file.
const bool slmExperiment = bool.fromEnvironment('SLM_EXPERIMENT');
