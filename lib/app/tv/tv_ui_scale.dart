import 'package:flutter/widgets.dart';

import '../state/settings_layout_state.dart';
import 'tv_layout.dart';

/// Scales the navigator and its overlays using the same logical viewport.
class TvUiScale extends StatelessWidget {
  final Widget child;

  const TvUiScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (TvUiScaleScope.maybeOf(context) != null) return child;
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppLayoutSettings.tvMode,
        AppLayoutSettings.tvUiScaleOverride,
      ]),
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final scale = AppLayoutSettings.tvMode.value
            ? TvLayout.configuredUiScale(context)
            : 1.0;
        return LayoutBuilder(
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.fill,
              child: SizedBox.fromSize(
                size: constraints.biggest / scale,
                child: MediaQuery(
                  data: media.copyWith(
                    size: media.size / scale,
                    devicePixelRatio: media.devicePixelRatio * scale,
                    padding: media.padding / scale,
                    viewPadding: media.viewPadding / scale,
                    viewInsets: media.viewInsets / scale,
                    systemGestureInsets: media.systemGestureInsets / scale,
                  ),
                  child: TvUiScaleScope(
                    unscaledSize: media.size,
                    scale: scale,
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
