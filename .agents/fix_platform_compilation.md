# Platform Compilation Fix
- Wrapped `ProductDetectionService`, `ARCameraView`, and `ScannerViewModel` in `#if os(iOS)` conditions.
- Wrapped `ScannerView` in `#if os(iOS)` with a fallback `View` implementation for macOS and other targets.
- This resolved compilation issues where Xcode tried to compile ARKit and iOS-only SwiftUI representables for other platforms (e.g. macOS/visionOS) supported by the project configuration.
