# Changelog

All notable changes to this project will be documented in this file.

## [0.5] - 2025-12-14 - Gallery Overhaul & CBZ Support

### Added
- **Comic Book Support**: Added support for `.cbz` archives (extracts and sorts images automatically).

### Changed
- **Gallery**: Completely rewritten gallery engine with pagination support. Now opens instantly even with 200+ images and handles large collections smoothly.
- **Gesture Menus**: Fixed actions ("Show Gallery", "Show Illustrations") to be reliably visible in the General gesture menu.

## [0.4] - 2025-12-09

### Added
- **Favorites System**: You can now add images to your "Favorites".
- **Favorites Gallery**: A new global gallery to view your favorite illustrations from all books. Available from the plugin menu or globally via a gesture.
- **Update Checker**: Automatically checks for new versions on GitHub and notifies you when an update is available.
- **Settings Enhancements**:
    - Toggle for "Check for updates".
    - Option to "Clear Favorites".
    - "Minimum Image Size" setting to filter out small icons/artifacts.

### Changed
- **Context Awareness**: "Show Gallery" and "Show Illustrations" actions are now strictly available only when a document is open. "Show Favorites" is available everywhere (including file browser).
- **Update Notifications**: Improved notification clarity (shows "Remote" vs "Local" version) and identifying plugin name.
- **Performance**: Improved network checks to prevent crashes if offline.

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
