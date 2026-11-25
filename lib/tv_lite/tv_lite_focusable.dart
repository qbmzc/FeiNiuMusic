import 'package:flutter/material.dart';

/// 遥控器可聚焦块：聚焦时描边 + 底色，确认键或点击触发 [onSelect]。
///
/// 刻意不用 InkWell 水波纹、阴影和缩放动画：低端投影 GPU 上每次焦点移动
/// 只重绘这一块。
class TvLiteFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final bool autofocus;
  final bool selected;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;
  final double radius;

  const TvLiteFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.autofocus = false,
    this.selected = false,
    this.focusNode,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.radius = 12,
  });

  @override
  State<TvLiteFocusable> createState() => _TvLiteFocusableState();
}

class _TvLiteFocusableState extends State<TvLiteFocusable> {
  bool _focused = false;

  Object? _activate(Intent _) {
    widget.onSelect?.call();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    if (_focused) {
      background = scheme.primaryContainer;
    } else if (widget.selected) {
      background = scheme.surfaceContainerHighest;
    } else {
      background = Colors.transparent;
    }
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: _activate),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: _activate,
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Padding(
            padding: widget.padding,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: _focused ? scheme.onPrimaryContainer : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
