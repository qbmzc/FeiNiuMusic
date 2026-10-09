import 'package:flutter/rendering.dart';

/// Caps the requested columns so TV cards remain readable in the scaled viewport.
class TvGridDelegate extends SliverGridDelegateWithFixedCrossAxisCount {
  final double minimumCardWidth;

  const TvGridDelegate({
    required super.crossAxisCount,
    required this.minimumCardWidth,
    super.crossAxisSpacing,
    super.mainAxisSpacing,
    super.childAspectRatio,
  });

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final columns =
        ((constraints.crossAxisExtent + crossAxisSpacing) /
                (minimumCardWidth + crossAxisSpacing))
            .floor()
            .clamp(1, crossAxisCount);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      childAspectRatio: childAspectRatio,
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(covariant TvGridDelegate oldDelegate) =>
      minimumCardWidth != oldDelegate.minimumCardWidth ||
      super.shouldRelayout(oldDelegate);
}
