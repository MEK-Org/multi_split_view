/// Represents the policy for handling overflow of non-flexible areas within
/// a container.
enum SizeOverflowPolicy { shrinkFirst, shrinkLast }

/// Represents the policy for handling cases where the total size of
/// non-flexible areas within a container is smaller than the available space.
enum SizeUnderflowPolicy { stretchFirst, stretchLast, stretchAll }

/// Represents the order in which the minimum size of the areas is recovered.
enum MinSizeRecoveryPolicy { firstToLast, lastToFirst }

/// Represents how flex areas absorb the change when a divider between a
/// size area and a flex area is dragged.
///
/// A divider next to an area with [Area.minPixels] or [Area.collapseSize]
/// always resizes only its two neighbours.
enum FlexResizePolicy {
  /// All flex areas share the change in proportion to their flex.
  proportional,

  /// Only the flex area next to the divider changes; the other areas keep
  /// their pixel sizes.
  neighbourOnly
}
