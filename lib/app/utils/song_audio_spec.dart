import '../state/song_state.dart';

/// 原始音源规格，不代表转码后或音频设备实际输出的规格。
String formatSongAudioSpec(SongEntity? song) {
  if (song == null) return '';
  final legacy = song.audioSpec ?? '';

  // 部分旧队列只有音质描述文本，从中兜底读取码率。
  num? readBitrate() {
    final match = RegExp(
      r'(?:^|\s|·)(\d+(?:\.\d+)?)\s*kbps\b',
      caseSensitive: false,
    ).firstMatch(legacy);
    final value = num.tryParse(match?.group(1) ?? '');
    return value != null && value > 0 ? value : null;
  }

  String? nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  final format =
      nonEmpty(song.codec) ??
      nonEmpty(song.format) ??
      RegExp(
        r'^\s*([a-zA-Z][a-zA-Z0-9_-]*)(?=\s|·|$)',
      ).firstMatch(legacy)?.group(1);
  final bitrate = song.bitrate != null && song.bitrate! > 0
      ? song.bitrate! / 1000
      : readBitrate();

  final parts = <String>[
    if (format != null) format.toUpperCase(),
    if (bitrate != null)
      '${bitrate.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (match) => '${match[1]},')} kbps',
  ];
  return parts.join(' · ');
}

/// 播放器实际音频链路：未转码时显示原始规格，转码时同时显示原始音源
/// 和当前播放格式，避免把歌曲元数据误认为当前输出格式。
String formatPlayerAudioSpec(SongEntity? song, {String? playbackCodec}) {
  final source = formatSongAudioSpec(song);
  final output = playbackCodec?.trim().toUpperCase();
  if (output == null || output.isEmpty) {
    return source.isEmpty ? '' : '$source · 直连';
  }
  if (source.isEmpty) return '当前播放：$output · 转码';
  return '$source → $output · 转码';
}
