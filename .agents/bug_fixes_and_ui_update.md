# Bug Fixes & Dark Theme UI Update

## 1. Codebase & Concurrency Bug Fixes

- **ProductDetectionService Thread Safety**:
  - Fixed race condition where `frameDetections` array was mutated on `self` inside Vision request callbacks.
  - Implemented thread-local array initialization inside `detectionQueue.async` block to eliminate shared state corruption.

- **ScannerViewModel Render Thread Race Condition**:
  - Fixed potential data race between Main Thread Vision delegate updates and SceneKit's render thread calling `renderer(_:nodeFor:)`.
  - Added an `NSRecursiveLock` (`itemLock`) around all `trackedItems` reads, writes, and iterations.

- **Cleaned Deprecation Warnings**:
  - Adjusted `interfaceOrientation` availability check to `#available(iOS 17.0, *)` using `effectiveGeometry.interfaceOrientation`.

## 2. UI & UX Refinements

- **Removed Center Crosshair Reticle**:
  - Removed the `Image(systemName: "viewfinder")` element from the middle of `ScannerView`.

- **Dark Theme Polish**:
  - Added dark vignette gradient overlays (`LinearGradient` top & bottom) over the live AR camera feed for high contrast readability.
  - Redesigned the top navigation header with dark glassmorphic styling (`Color.black.opacity(0.65)`), crisp borders, and a live scanning state indicator dot.
  - Created a dark counter badge displaying the total detected products.
  - Modernized the bottom control button into a dark glass capsule with glowing action state indicators.
  - Forced `.preferredColorScheme(.dark)` across views.
