import 'package:flutter/widgets.dart';

import '../../app/state/settings_layout_state.dart';
import '../../app/tv/tv_layout.dart';

class TvPlayerScale extends StatelessWidget {
  final Widget child;

  const TvPlayerScale({super.key, required this.child});

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScaledPlayer>() != null;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: AppLayoutSettings.tvUiScaleOverride,
      builder: (context, _, _) {
        final scale = TvLayout.uiScale(context);
        final media = MediaQuery.of(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest / scale;
            return FittedBox(
              fit: BoxFit.fill,
              child: SizedBox.fromSize(
                size: size,
                child: MediaQuery(
                  data: media.copyWith(
                    size: media.size / scale,
                    padding: media.padding / scale,
                    viewPadding: media.viewPadding / scale,
                    viewInsets: media.viewInsets / scale,
                  ),
                  child: _ScaledPlayer(child: child),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ScaledPlayer extends InheritedWidget {
  const _ScaledPlayer({required super.child});

  @override
  bool updateShouldNotify(_ScaledPlayer oldWidget) => false;
}
