# Scene Tab Manager for Godot 4.x

[日本語版 (Japanese)](README.ja.md)

**Scene Tab Manager** is an editor plugin that automatically organizes the numerous open scene tabs in the Godot Editor based on predefined keyword priorities (weights).

It solves the common issue in large projects where important scenes—such as the main menu, player, or common base levels—get buried under a sea of other open tabs.

## Key Features

* **Keyword-Based Sorting**: Calculates a priority score based on keywords in the scene's filename (e.g., `Player`, `Main`, `Level`) and sorts them in descending order.
* **Easy Customization**: Change keyword and score pairs directly from the **Editor Settings** or via the button's context menu.
* **One-Click Operation**: Instantly organize your tabs by clicking the "Organize" button added to the 2D/3D viewport toolbar.
* **Context Menu**: Right-click the Organize button to quickly access settings or reset them to default.
* **Smart Restoration**: Automatically returns focus to the scene you were originally working on after the sorting process is complete.
* **Signal Connection Tooltip**: Hover over any node in the **Scene Tree** to see its signal connections (Signals/Outgoing and Incoming) in a tooltip.
* **Quick File Locate (Alt+Click)**: Hold the **Alt** key while clicking on a scene tab, a node in the Scene tree, or a resource in the Inspector to immediately reveal that file in the **FileSystem** dock.

## Installation

1.  Copy the `addons/scene_tab_manager` directory into your own project's `addons/` directory.
2.  In the Godot Editor, navigate to **Project -> Project Settings**.
3.  Go to the **Plugins** tab and change the status of **Scene Tab Manager** to **Enabled**.

## Usage

### 1. Organizing Tabs
Click the **Organize** button (with the folder icon) located in the top toolbar of the editor (near the "View" or "Tool" menus).

![Organize Button Location](doc_images/info_icon0.jpg)

### 2. Quick Settings Access (Right-Click)
Right-click the **Organize** button to open a context menu with the following options:

![Context Menu](doc_images/context_menu.jpg)

* **Organize Tabs**: Performs the same action as a left-click.
* **Edit Keyword Weights...**: Opens the weight settings directly in the **Inspector** for quick editing without opening the Editor Settings dialog.
* **Reset to Default**: Reverts all keyword weights to their initial values (requires confirmation).

### 3. Configuring Priorities
You can configure priorities in two ways:
1.  **Via Context Menu**: Right-click the Organize button and select **Edit Keyword Weights...**. The settings will appear in the Inspector.
2.  **Via Editor Settings**:
    * Open **Editor -> Editor Settings**.
    * Navigate to the **Editors -> Plugins -> Scene Tab Manager** section.
    * Edit the `Keyword Weights` dictionary.

#### Keyword Weights Configuration:
* **Key (String)**: The keyword to search for (case-insensitive).
* **Value (Integer)**: The priority score. Higher values will place the tab further to the left.

#### Default Setting Example:
| Keyword | Score
| :--- | :---
| `title` | 50
| `level_base` | 30
| `player` | 10

![Settings](doc_images/settings.jpg)

### 4. Quick File Locate
Hold the **Alt** key and click on any of the following to reveal the corresponding file in the **FileSystem** dock:
* **Scene Tabs**: Select the tab while holding Alt.
* **Nodes in Scene Tree**: If the node is a saved scene (instanced), it will be highlighted.
* **Resources in Inspector**: Click on a resource property (like a texture, script, or material).

### 5. Signal Connection Tooltip
Hover your mouse over a node in the **Scene Tree** dock to instantly see its signal connections:

* **Signals (Outgoing)**: Shows where this node's signals are connected to.
* **Incoming**: Shows which nodes are sending signals to this node.
* **Detail Control**:
    * **Default View**: Shows only connections registered in the `.tscn` file (persistent connections).
    * **Detailed View (Hold Ctrl)**: Shows all connections, including internal engine/inherited ones.

---

## Technical Details & Limitations

* This plugin only sorts scene tabs that are currently **open** in the editor.
* During the reorganization process, each scene is briefly set as active; however, the focus is restored to your original scene once finished.
* To ensure stability even with a large number of tabs, a tiny delay (0.05s) is applied between tab movements.
* The signal tooltip updates at an optimized interval (0.1s) to ensure editor performance remains smooth.

---

### License
This project is released under the MIT License.
