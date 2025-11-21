# Changelog

All notable changes to this project will be documented in this file.

## [0.3] - 2025-11-21

### Added
- **Gallery Mode**: New 3x3 grid view to browse all thumbnails at once (Gallery).
- **Settings Menu**: New submenu for plugin configuration.
- **Allow Spoilers**: Persistent setting to toggle between showing all images or only up to the current page.
- **Navigation**: "Gallery" button in the single-image view to return to the grid.

### Changed
- **Menu Structure**: Reorganized into "Settings", "Show Illustrations", and "Show Gallery".
- **Gesture Actions**: Updated to `Show Gallery` and `Show Illustrations` (both respect the "Allow Spoilers" setting).
- **Performance**: Disabled image caching in widgets to prevent Out-Of-Memory (OOM) crashes on Kindle devices.
- **UX**: Improved scrolling and touch interaction in Gallery mode. Refined touch zones in single view (menu now triggers only on top-center tap).

### Fixed
- Fixed an issue where the plugin menu would appear outside of an open book.
- Fixed scrolling repaint issues in the grid view.
- Fixed The plugin is only available in reader mode (when a book is open).

## [0.2] - 2025-11-20
- Initial beta release with basic viewing capabilities.
