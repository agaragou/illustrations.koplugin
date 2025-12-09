# Illustrations Plugin for KOReader

A plugin for [KOReader](https://github.com/koreader/koreader) that allows you to browse, preview, and navigate through all illustrations contained in an EPUB book.

![Gallery View](screenshots/gallery.jpeg)

<details>
<summary><b>More Screenshots (Menu, Settings, Actions)</b></summary>

| **Plugin Menu** | **Settings** |
| :---: | :---: |
| ![Plugin Menu](screenshots/illustrations-menu.png) | ![Settings](screenshots/settings.png) |

| **Main Menu Entry** | **Gesture Actions** |
| :---: | :---: |
| ![Main Menu](screenshots/illustrations-main-menu.png) | ![Actions](screenshots/actions.png) |

</details>

## Features

*   **Gallery Mode:** Browse all extracted images in a 3x3 grid view.
*   **Illustrations Mode:** View images one by one in full screen.
*   **Favorites System:** Mark images as favorites and view them in a dedicated **Favorites Gallery** (available globally, even outside books).
*   **Update Checker:** Automatically checks for updates and notifies you of new versions.
*   **Spoiler Protection:** By default, shows images **only up to the current page**. You can toggle "Allow Spoilers" in settings to see everything.
*   **Navigation:**
    *   **Touch:** Tap left/right to navigate, tap **top-center** to open controls.
    *   **Keys:** Supports physical page turn buttons and directional keys.
*   **Go to Page:** Jump directly from an image to its location in the book.
*   **Gesture Support:** Assign "Show Gallery", "Show Illustrations", or "Show Favorites" to any gesture.
*   **Efficient Caching:** Images are extracted once and stored in the cache.

## Installation

1.  Download the latest release ZIP file from the [Releases page](../../releases).
2.  Connect your device to your computer via USB.
3.  Unzip the archive and copy the `illustrations.koplugin` folder into the `koreader/plugins/` directory on your device.
4.  Safely eject the device and restart KOReader.

## Usage

### Menu
Open a book, tap the top menu, and go to the **Tools** (wrench icon) tab. You will see a new **Illustrations** menu:

*   **Show Favorites:** Opens the gallery of your favorite images from all books.
*   **Settings:**
    *   **Check for updates:** Toggle automatic update checks (shows current version).
    *   **Min Image Size:** Set threshold to ignore small images (e.g. dividers).
    *   **Clear current book cache:** Removes extracted images for the current book.
    *   **Clear ALL books cache:** Removes all extracted images to free up space.
    *   **Clear Favorites:** Removes all images from favorites.
    *   **Allow Spoilers:** Toggle to show ALL images in the book (default is OFF).
*   **Show Illustrations:** Opens the single-image viewer.
*   **Show Gallery:** Opens the grid view of thumbnails.

### Controls (Single View)
*   **Next/Prev:** Tap right/left side or use keys.
*   **Menu:** Tap **top-center**.
    *   **Add/Remove Favorite:** Toggle favorite status.
    *   **Go to Page:** Jump to the book page.
    *   **Gallery:** Switch to grid view.
    *   **Resume:** Continue viewing.
    *   **Exit:** Close plugin.

### Gestures
You can assign actions in **Settings -> Taps & Gestures -> Gesture Manager**:
*   `Illustrations: Show Gallery` (Book only)
*   `Illustrations: Show Illustrations` (Book only)
*   `Illustrations: Show Favorites` (Global)

## Storage
Extracted images are stored in `koreader/cache/illustrations/`.
