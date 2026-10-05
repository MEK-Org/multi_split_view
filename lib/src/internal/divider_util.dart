import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:multi_split_view/src/area.dart';
import 'package:multi_split_view/src/controller.dart';
import 'package:multi_split_view/src/internal/layout_constraints.dart';
import 'package:multi_split_view/src/internal/num_util.dart';
import 'package:multi_split_view/src/policies.dart';

/// Represents divider util used by the [MultiSplitView].
@internal
class DividerUtil {
  static double move(
      {required MultiSplitViewController controller,
      required LayoutConstraints layoutConstraints,
      required int dividerIndex,
      required double pixels,
      required bool pushDividers}) {
    if (pixels == 0) {
      return 0;
    }

    double rest;
    if (pixels < 0) {
      rest = _resizeAreas(
              pixelsToMove: pixels.abs(),
              direction: -1,
              controller: controller,
              layoutConstraints: layoutConstraints,
              shrinkAreaIndex: dividerIndex,
              growAreaIndex: dividerIndex + 1,
              pushDividers: pushDividers) *
          -1;
    } else {
      rest = _resizeAreas(
          pixelsToMove: pixels,
          direction: 1,
          controller: controller,
          layoutConstraints: layoutConstraints,
          shrinkAreaIndex: dividerIndex + 1,
          growAreaIndex: dividerIndex,
          pushDividers: pushDividers);
    }
    return rest;
  }

  static double _resizeAreas(
      {required double pixelsToMove,
      required int direction,
      required MultiSplitViewController controller,
      required LayoutConstraints layoutConstraints,
      required int shrinkAreaIndex,
      required int growAreaIndex,
      required bool pushDividers}) {
    Area shrinkArea = controller.getArea(shrinkAreaIndex);

    Area growArea = controller.getArea(growAreaIndex);

    final double availableSizeForFlexAreas =
        layoutConstraints.calculateAvailableSpaceForFlexAreas(controller);
    final double pixelsPerFlex =
        availableSizeForFlexAreas / layoutConstraints.flexSum;

    final double flexPerPixels = availableSizeForFlexAreas == 0
        ? 0
        : layoutConstraints.flexSum / availableSizeForFlexAreas;

    double movedPixels = pixelsToMove;

    final bool bothFlex = shrinkArea.flex != null && growArea.flex != null;

    if (bothFlex) {
      // both flex
      movedPixels = math.min(
          flexToAvailablePixelsToShrink(
              area: shrinkArea, pixelsPerFlex: pixelsPerFlex),
          movedPixels);

      final double? availablePixelsToMax = flexToAvailablePixelsToMax(
          area: growArea, pixelsPerFlex: pixelsPerFlex);
      if (availablePixelsToMax != null) {
        movedPixels = math.min(availablePixelsToMax, movedPixels);
      }
    } else {
      if (shrinkArea.size != null) {
        final double availablePixelsToShrink =
            sizeToAvailablePixelsToShrink(area: shrinkArea);
        movedPixels = math.min(availablePixelsToShrink, movedPixels);
      }
      if (growArea.size != null) {
        final double? availablePixelsToMax =
            sizeToAvailablePixelsToMax(area: growArea);

        if (availablePixelsToMax != null) {
          movedPixels = math.min(availablePixelsToMax, movedPixels);
        }

        if (layoutConstraints.flexSum > 0) {
          // avoid grow more then container
          final double shrinkAreaPixels =
              toPixels(area: shrinkArea, pixelsPerFlex: pixelsPerFlex);
          movedPixels = math.min(shrinkAreaPixels, movedPixels);
        }
      }
    }

    movedPixels = NumUtil.fix('movedPixels', movedPixels);

    if (shrinkArea.size != null) {
      AreaHelper.setSize(
          area: shrinkArea, size: shrinkArea.size! - movedPixels);
    }
    if (growArea.size != null) {
      AreaHelper.setSize(area: growArea, size: growArea.size! + movedPixels);
    }
    if (bothFlex && shrinkArea.flex != null) {
      AreaHelper.setFlex(
          area: shrinkArea,
          flex: shrinkArea.flex! - (movedPixels * flexPerPixels));
    }
    if (bothFlex && growArea.flex != null) {
      AreaHelper.setFlex(
          area: growArea, flex: growArea.flex! + (movedPixels * flexPerPixels));
    }

    double rest = pixelsToMove - movedPixels;

    shrinkAreaIndex += direction;
    if (pushDividers &&
        shrinkAreaIndex >= 0 &&
        shrinkAreaIndex < controller.areasCount) {
      return _resizeAreas(
          pixelsToMove: rest,
          direction: direction,
          controller: controller,
          layoutConstraints: layoutConstraints,
          shrinkAreaIndex: shrinkAreaIndex,
          growAreaIndex: growAreaIndex,
          pushDividers: pushDividers);
    }
    return rest;
  }

  static double flexToAvailablePixelsToShrink(
      {required Area area, required double pixelsPerFlex}) {
    final double size = area.flex! * pixelsPerFlex;
    final double? minSize =
        area.min != null ? (area.min! * pixelsPerFlex) : null;
    return math.max(size - (minSize ?? 0), 0);
  }

  static double sizeToAvailablePixelsToShrink({required Area area}) {
    return math.max(area.size! - (area.min != null ? area.min! : 0), 0);
  }

  static double? flexToAvailablePixelsToMax(
      {required Area area, required double pixelsPerFlex}) {
    if (area.max == null) {
      return null;
    }
    final double maxSize = area.max! * pixelsPerFlex;
    final double size = area.flex! * pixelsPerFlex;
    return math.max(maxSize - size, 0);
  }

  static double? sizeToAvailablePixelsToMax({required Area area}) {
    if (area.max == null) {
      return null;
    }
    return math.max(area.max! - area.size!, 0);
  }

  static double toPixels({required Area area, required double pixelsPerFlex}) {
    if (area.size != null) {
      return area.size!;
    }
    return area.flex! * pixelsPerFlex;
  }
}

/// A divider drag measured from where it started, resizing only the two
/// areas next to the divider and applying their pixel limits synchronously.
///
/// Used when either neighbour has [Area.minPixels] or [Area.collapseSize],
/// or for a size|flex divider under [FlexResizePolicy.neighbourOnly].
@internal
class AnchoredDrag {
  AnchoredDrag._(
      {required this.dividerIndex,
      required this.dividerStart,
      required this.prevArea,
      required this.nextArea,
      required this.prevSize,
      required this.nextSize,
      required this.prevMin,
      required this.nextMin})
      : _prevBelowMin = prevSize < prevMin,
        _nextBelowMin = nextSize < nextMin;

  /// Starts an anchored drag if the divider qualifies, otherwise null.
  static AnchoredDrag? start(
      {required MultiSplitViewController controller,
      required LayoutConstraints layoutConstraints,
      required int dividerIndex,
      required double dividerStart,
      required FlexResizePolicy flexResizePolicy}) {
    final Area prev = controller.getArea(dividerIndex);
    final Area next = controller.getArea(dividerIndex + 1);
    final bool pixelLimits = _hasPixelLimits(prev) || _hasPixelLimits(next);
    final bool mixed = (prev.flex == null) != (next.flex == null);
    if (!pixelLimits &&
        !(mixed && flexResizePolicy == FlexResizePolicy.neighbourOnly)) {
      return null;
    }
    final double pixelsPerFlex = _pixelsPerFlex(controller, layoutConstraints);
    return AnchoredDrag._(
        dividerIndex: dividerIndex,
        dividerStart: dividerStart,
        prevArea: prev,
        nextArea: next,
        prevSize:
            DividerUtil.toPixels(area: prev, pixelsPerFlex: pixelsPerFlex),
        nextSize:
            DividerUtil.toPixels(area: next, pixelsPerFlex: pixelsPerFlex),
        prevMin: _minPixelsOf(prev, pixelsPerFlex),
        nextMin: _minPixelsOf(next, pixelsPerFlex));
  }

  final int dividerIndex;
  final double dividerStart;
  final Area prevArea;
  final Area nextArea;
  final double prevSize;
  final double nextSize;
  final double prevMin;
  final double nextMin;

  /// Whether an area began the drag below its minimum; it may stay there
  /// until the drag grows it past the minimum.
  bool _prevBelowMin;
  bool _nextBelowMin;

  /// Whether the controller still holds the areas this drag started with.
  bool matches(MultiSplitViewController controller) =>
      dividerIndex + 1 < controller.areasCount &&
      identical(controller.getArea(dividerIndex), prevArea) &&
      identical(controller.getArea(dividerIndex + 1), nextArea);

  /// Moves the divider to [delta] pixels from where the drag started.
  void update(
      {required MultiSplitViewController controller,
      required LayoutConstraints layoutConstraints,
      required double delta}) {
    final double sum = prevSize + nextSize;
    if (delta == 0 || prevMin + nextMin >= sum) {
      return;
    }
    if (delta < 0 && _prevBelowMin || delta > 0 && _nextBelowMin) {
      return;
    }
    final double prevCollapse = prevArea.collapseSize ?? 0;
    final double nextCollapse = nextArea.collapseSize ?? 0;
    double newPrev;
    double newNext;
    if (delta < 0) {
      final double proposedPrev = prevSize + delta;
      newPrev =
          proposedPrev < prevCollapse ? 0 : math.max(prevMin, proposedPrev);
      newNext = sum - newPrev;
      if (nextSize == 0) {
        // reopening a collapsed next area
        if (newNext < nextCollapse) {
          newNext = 0;
          newPrev = sum;
        } else if (newNext < nextMin) {
          newNext = nextMin;
          newPrev = sum - newNext;
        }
      }
      if (_nextBelowMin) {
        if (newNext > nextMin) {
          _nextBelowMin = false;
        }
      } else if (newNext < nextMin) {
        newPrev -= nextMin - newNext;
        newNext = nextMin;
      }
    } else {
      final double proposedNext = nextSize - delta;
      newNext =
          proposedNext < nextCollapse ? 0 : math.max(nextMin, proposedNext);
      newPrev = sum - newNext;
      if (prevSize == 0) {
        // reopening a collapsed previous area
        if (newPrev < prevCollapse) {
          newPrev = 0;
          newNext = sum;
        } else if (newPrev < prevMin) {
          newPrev = prevMin;
          newNext = sum - newPrev;
        }
      }
      if (_prevBelowMin) {
        if (newPrev > prevMin) {
          _prevBelowMin = false;
        }
      } else if (newPrev < prevMin) {
        newNext -= prevMin - newPrev;
        newPrev = prevMin;
      }
    }

    final double pixelsPerFlex = _pixelsPerFlex(controller, layoutConstraints);
    final double? prevMax = _maxPixelsOf(prevArea, pixelsPerFlex);
    if (prevMax != null && newPrev > prevMax) {
      newPrev = prevMax;
      newNext = sum - newPrev;
    }
    final double? nextMax = _maxPixelsOf(nextArea, pixelsPerFlex);
    if (nextMax != null && newNext > nextMax) {
      newNext = nextMax;
      newPrev = sum - newNext;
    }

    _apply(
        controller: controller,
        pixelsPerFlex: pixelsPerFlex,
        newPrev: newPrev,
        newNext: newNext);
  }

  /// Writes the new neighbour sizes, keeping every other area at its
  /// current pixel size and the flex sum unchanged.
  void _apply(
      {required MultiSplitViewController controller,
      required double pixelsPerFlex,
      required double newPrev,
      required double newNext}) {
    final List<double> pixels = [];
    double flexSum = 0;
    double flexPixels = 0;
    for (int index = 0; index < controller.areasCount; index++) {
      final Area area = controller.getArea(index);
      double size =
          DividerUtil.toPixels(area: area, pixelsPerFlex: pixelsPerFlex);
      if (index == dividerIndex) {
        size = newPrev;
      } else if (index == dividerIndex + 1) {
        size = newNext;
      }
      pixels.add(size);
      if (area.flex != null) {
        flexSum += area.flex!;
        flexPixels += size;
      }
    }
    for (int index = 0; index < controller.areasCount; index++) {
      final Area area = controller.getArea(index);
      if (area.size != null) {
        AreaHelper.setSize(area: area, size: pixels[index]);
      } else if (flexPixels > 0) {
        AreaHelper.setFlex(
            area: area, flex: pixels[index] * flexSum / flexPixels);
      }
    }
  }

  static bool _hasPixelLimits(Area area) =>
      area.minPixels != null || area.collapseSize != null;

  static double _pixelsPerFlex(MultiSplitViewController controller,
      LayoutConstraints layoutConstraints) {
    if (layoutConstraints.flexSum == 0) {
      return 0;
    }
    return layoutConstraints.calculateAvailableSpaceForFlexAreas(controller) /
        layoutConstraints.flexSum;
  }

  static double _minPixelsOf(Area area, double pixelsPerFlex) {
    double min = area.minPixels ?? 0;
    if (area.min != null) {
      min = math.max(
          min, area.size != null ? area.min! : area.min! * pixelsPerFlex);
    }
    return min;
  }

  static double? _maxPixelsOf(Area area, double pixelsPerFlex) {
    if (area.max == null) {
      return null;
    }
    return area.size != null ? area.max! : area.max! * pixelsPerFlex;
  }
}
