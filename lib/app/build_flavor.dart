/// 投影/电视精简版构建开关：`--dart-define=TV_LITE=true`。
///
/// 编译期常量：未启用一侧的界面代码会被 AOT tree-shake 掉，精简版 APK 不含
/// 手机端页面，手机版也不含精简版页面。
const bool kTvLite = bool.fromEnvironment('TV_LITE');
