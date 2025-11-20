# Illustrations Plugin for KOReader

A plugin for [KOReader](https://github.com/koreader/koreader) that allows you to browse, preview, and navigate through all illustrations contained in an EPUB book.

## Features

*   **Gallery View:** Browse all extracted images in a fullscreen slideshow/gallery mode.
*   **Spoiler-Free Mode:** View illustrations **only up to the current chapter**, preventing accidental spoilers from future chapters.
*   **Navigation:**
    *   **Touch:** Tap left/right to navigate, tap center to open menu.
    *   **Keys:** Supports physical page turn buttons and directional keys.
*   **Go to Page:** Jump directly from an image in the gallery to its location in the book.
*   **Gesture Support:** Register actions in KOReader's Gesture Manager to trigger the gallery (e.g., via corner taps or swipes).
*   **Efficient Caching:** Images are extracted once and stored in the cache, with options to manage/clear storage.

## Installation

1.  Download the `illustrations.koplugin` folder.
2.  Connect your device to your computer via USB.
3.  Copy the folder into the `koreader/plugins/` directory on your device.
4.  Safely eject the device and restart KOReader.

## Usage

### Menu
Open a book, tap the top menu, and go to the **Tools** (wrench icon) tab. You will see a new **Illustrations** menu with the following options:

*   **Clear current book cache:** Removes extracted images for the currently open book.
*   **Clear ALL books cache:** Removes all extracted images for all books to free up space.
*   **Show All illustrations (SPOILERS!):** Opens the gallery with **all** images found in the book.
*   **Show illustrations to chapter end (Spoiler-free):** Opens the gallery containing only images from the beginning of the book up to the end of the current chapter.

### Gallery Controls
*   **Next Image:** Tap right side of screen / Right Key / Page Forward.
*   **Previous Image:** Tap left side of screen / Left Key / Page Back.
*   **Menu / Controls:** Tap center of screen / Menu Key.
    *   **Go to Page:** Closes gallery and jumps to the book page containing the image.
    *   **Resume Gallery:** Returns to viewing.
    *   **Close Gallery:** Exits the plugin.

### Gestures
You can assign the plugin actions to gestures (e.g., "Tap top-right corner") via **Settings -> Taps & Gestures -> Gesture Manager**.
Look for the actions in the **General** or **Tools** tab:
*   `Show All illustrations (SPOILERS!)`
*   `Show illustrations to chapter end (Spoiler-free)`

## Storage
Extracted images are stored in `koreader/cache/illustrations/`. You can manage this space using the built-in menu options.
