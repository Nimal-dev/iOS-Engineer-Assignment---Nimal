# Multi-Mode Detection & Precision Fixes

## Changes Made:

1. **Multi-Mode Scanner in ProductDetectionService**:
   - Added `VNDetectBarcodesRequest` for recognizing barcodes and decoding payloads.
   - Added `VNRecognizeTextRequest` in accurate mode to detect printed labels/brands.
   - Grouped rectangle, barcode, and text requests into a single unified `VNImageRequestHandler` execution.

2. **DisplayTransform Coordinate Correction**:
   - Replaced custom, hardcoded screen calculations with the official ARKit `displayTransform(for:viewportSize:)` CGAffineTransform.
   - Inverted the Y-axis of normalized Vision outputs to map correctly to camera frame orientation before applying the displayTransform.
   - This guarantees that coordinates are mapped precisely, ensuring bounding boxes and tick marks are aligned exactly on the physical items.

3. **Stable Dual-Step Raycasting**:
   - Programmed the viewport raycast to check `.existingPlaneGeometry` first for maximum stability.
   - If no plane geometry is tracked yet, it falls back to `.estimatedPlane`.

4. **Type-Specific Non-Duplication Logic**:
   - Barcodes: Deduplicated globally using payload strings.
   - Text: Deduplicated within a 1-meter radius matching the exact recognized string.
   - Rectangles: Deduplicated spatially within a 15-centimeter radius.

5. **Custom 3D/AR Visuals in SceneKit**:
   - Barcodes: Rendered with Cyan borders and QR symbols, accompanied by a 3D float-scaled text tag above the item showing the decoded payload.
   - Text: Rendered with Orange borders and text alignment symbols, accompanied by a 3D float-scaled text tag showing the recognized content.
   - Rectangles: Kept green outlines with a checkmark symbol.
