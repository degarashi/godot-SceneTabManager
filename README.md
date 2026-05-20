# Scene Tab Manager for Godot 4.x

[日本語版 (Japanese)](README.ja.md)

**Scene Tab Manager** is an editor plugin that automatically organizes the numerous open scene tabs in the Godot Editor based on predefined keyword priorities (weights).

It solves the common issue in large projects where important scenes—such as the main menu, player, or common base levels—get buried under a sea of other open tabs.

## Key Features

* **Keyword-Based Sorting**: Calculates a priority score based on keywords in the scene's filename (defaults: `title`, `level_base`, `player`) and sorts them in descending order.
* **Easy Customization**: Change keyword weights or shortcut preferences directly from the **Editor Settings** or via the button's context menu.
* **One-Click Operation**: Instantly organize your tabs by clicking the "Organize" button added to the 2D/3D viewport toolbar.
* **Recent Files (Ctrl+E)**: Quickly jump back to recently opened scenes or scripts using a searchable popup.
* **Quick Open (Double-Tap Shift)**: Trigger the "Quick Open Resource" dialog by double-tapping the **Shift** key.
* **Alt+Click to Locate**: Hold the **Alt** key while clicking on a node or resource to immediately reveal that file in the **FileSystem** dock.
* **Tab Switching (Alt + 1-9)**: Instantly switch between the first nine scene tabs using numeric keys.
* **Signal Connection Tooltip**: Hover over any node in the **Scene Tree** to see its signal connections in a tooltip.
* **Auto-Cleanup**: Automatically closes tabs when their underlying files are deleted from the filesystem.

## Installation

1.  Copy the `addons/scene_tab_manager` directory into your own project's `addons/` directory.
2.  In the Godot Editor, navigate to **Project -> Project Settings**.
3.  Go to the **Plugins** tab and change the status of **Scene Tab Manager** to **Enabled**.

## Usage

### Organizing Tabs
Click the **Organize** button (with the folder icon) located in the top toolbar of the editor.

![Organize Button Location](doc_images/info_icon0.jpg)

### Quick Settings Access (Right-Click)
Right-click the **Organize** button for quick actions:
* **Organize Tabs**: Same as left-click.
* **Edit Keyword Weights...**: Opens the plugin configurations (Keyword weights and Shortcuts) in the **Inspector**.
* **Reset to Default**: Reverts all keyword weights to their initial values.

### Recent Files (Ctrl+E)
Press **Ctrl+E** to open a popup listing your most recent files.
* Use the **Arrow Keys** to navigate.
* Use numeric keys **1-9** (and **0** for the 10th item) to focus the corresponding item (press **Enter** to open).

### Quick Open (Double-Tap Shift)
Double-tap the **Shift** key to open the resource search dialog.
* **Alt + Confirm**: Highlight the selected file in the FileSystem dock instead of opening it.

### Tab Switching (Alt + 1-9)
Hold **Alt** and press a number key (**1-9**) to jump to that specific tab index. This action also automatically switches the editor to the **2D View**.

### Quick File Locate (Alt+Click)
Hold the **Alt** key and click on any of the following to reveal it in the **FileSystem** dock:
* **Nodes in Scene Tree**: Highlights the scene file of an instanced node.
* **Resources in Inspector**: Click on a resource property (like a texture or script).

### Signal Connection Tooltip
Hover over a node in the **Scene Tree** to see its connections:
* **Signals (Outgoing)**: Connections from this node.
* **Incoming**: Connections to this node.
* **Detailed View (Hold Ctrl)**: Shows all connections, including internal engine ones.

### Configuration Settings
All preferences can also be configured under **Editor -> Editor Settings -> Editors -> Plugins -> Scene Tab Manager**:
* `keyword_weights`: A dictionary of keyword-weight pairs (Default: `{"title": 50, "level_base": 30, "player": 10}`).
* `shortcuts/recent_files`: Shortcut key to open the Recent Files popup (Default: `Ctrl+E`).
* `shortcuts/enable_double_shift`: Toggle double-tap Shift to trigger the Quick Open dialog (Default: `true`).
* `shortcuts/enable_alt_tab_switching`: Toggle Alt + 1-9 tab switching (Default: `true`).
* `shortcuts/enable_alt_click_locate`: Toggle Alt + Click to locate files in the FileSystem dock (Default: `true`).

---

## Technical Details & Limitations

* **Frame-by-Frame Sorting**: Tab rearrangement is processed over multiple frames to ensure editor stability.
* **Focus Restoration**: Automatically returns focus to your active scene after sorting.
* **Optimized Updates**: Signal tooltips update at 0.1s intervals, and file locate actions have a 0.25s cooldown to prevent double-triggers.
* **Auto-Cleanup**: The plugin monitors filesystem changes and closes any open tabs whose files have been moved or deleted.

---

### License
This project is released under the MIT License.
