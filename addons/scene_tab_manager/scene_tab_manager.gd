@tool
extends EditorPlugin

# ------------- [Constants] -------------
# Path for the configuration setting
const SETTING_PATH: String = "editors/plugins/scene_tab_manager/keyword_weights"
const _OPERATE_DELAY: float = 0.25
const _TOOLTIP_UPDATE_INTERVAL: float = 0.1
const SHIFT_DOUBLE_TAP_THRESHOLD: int = 300
const MAX_RECENT_FILES: int = 15
const RECENT_FILES_SETTING: String = "editors/plugins/scene_tab_manager/recent_files"

# ------------- [Static Variable] -------------
static var _log := DLoggerClass.new("SceneTabManager")

# ------------- [Private Variable] -------------
var _toolbar_button: Button
var _popup_menu: PopupMenu
var _settings_proxy: RefCounted
var _reset_confirm_dialog: ConfirmationDialog
var _last_operated: float = 0.0
var _scene_tree_control: Tree
var _last_hovered_item: TreeItem
var _last_ctrl_state: bool = false
var _tooltip_timer: float = 0.0
var _last_shift_pressed: int = 0
var _recent_files: Array[String] = []


# ------------- [Callbacks] -------------
func _enter_tree() -> void:
	_log.info("Plugin initialized.")
	_find_and_setup_scene_tree()
	var settings := EditorInterface.get_editor_settings()

	# Define default priority weights based on keywords
	var default_weights := _get_default_weights()

	if not settings.has_setting(SETTING_PATH):
		settings.set_setting(SETTING_PATH, default_weights)
		settings.set_initial_value(SETTING_PATH, default_weights, false)

		# Add hint information for the Editor Settings UI
		var property_info: Dictionary = {
			"name": SETTING_PATH,
			"type": TYPE_DICTIONARY,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "Keyword:Priority-Score"
		}
		settings.add_property_info(property_info)

	# Add a button to the toolbar
	_toolbar_button = Button.new()
	var editor_base := EditorInterface.get_base_control()
	var scene_icon := editor_base.get_theme_icon("Folder", "EditorIcons")

	_toolbar_button.icon = scene_icon
	_toolbar_button.text = "Organize"
	_toolbar_button.tooltip_text = "Sort scene tabs (Right-click for settings)"
	_toolbar_button.flat = true
	_toolbar_button.pressed.connect(_on_button_pressed)
	_toolbar_button.gui_input.connect(_on_button_gui_input)

	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)

	# Setup PopupMenu
	_popup_menu = PopupMenu.new()
	_popup_menu.add_item("Organize Tabs", 0)
	_popup_menu.add_separator()
	_popup_menu.add_item("Edit Keyword Weights...", 1)
	_popup_menu.add_item("Reset to Default", 2)
	_popup_menu.id_pressed.connect(_on_menu_id_pressed)
	_toolbar_button.add_child(_popup_menu)

	# Setup confirmation dialog for reset
	_reset_confirm_dialog = ConfirmationDialog.new()
	_reset_confirm_dialog.dialog_text = "Reset keyword weights to default?"
	_reset_confirm_dialog.confirmed.connect(_on_reset_confirmed)
	_toolbar_button.add_child(_reset_confirm_dialog)

	# Connect to inspector signals for Alt-click feature
	var insp := EditorInterface.get_inspector()
	insp.edited_object_changed.connect(_on_inspector_obj_changed)
	insp.property_selected.connect(_on_inspector_property_selected)

	# Connect to filesystem signals
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)

	# Connect for Recent Files feature
	scene_changed.connect(_on_scene_changed)
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_script_changed)

	# Load recent files
	if settings.has_setting(RECENT_FILES_SETTING):
		var saved: Variant = settings.get_setting(RECENT_FILES_SETTING)
		if saved is Array:
			for item in saved:
				if item is String:
					_recent_files.append(item)


func _exit_tree() -> void:
	if _toolbar_button:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)
		_toolbar_button.queue_free()

	_scene_tree_control = null
	_last_hovered_item = null

	# Disconnect inspector signals
	var insp := EditorInterface.get_inspector()
	if insp:
		if insp.edited_object_changed.is_connected(_on_inspector_obj_changed):
			insp.edited_object_changed.disconnect(_on_inspector_obj_changed)
		if insp.property_selected.is_connected(_on_inspector_property_selected):
			insp.property_selected.disconnect(_on_inspector_property_selected)

	# Disconnect filesystem signals
	var efs := EditorInterface.get_resource_filesystem()
	if efs and efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.disconnect(_on_filesystem_changed)


func _process(delta: float) -> void:
	_tooltip_timer += delta
	if _tooltip_timer >= _TOOLTIP_UPDATE_INTERVAL:
		_tooltip_timer = 0.0
		_update_scene_tree_tooltip()


# Use _input instead of _shortcut_input
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_last_shift_pressed = 0
		return

	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey

	# Double-tap Shift detection
	if key_event.keycode == KEY_SHIFT:
		if key_event.pressed and not key_event.echo:
			var now := Time.get_ticks_msec()
			if now - _last_shift_pressed < SHIFT_DOUBLE_TAP_THRESHOLD:
				_on_double_shift_pressed()
				_last_shift_pressed = 0
				get_viewport().set_input_as_handled()
			else:
				_last_shift_pressed = now
		return

	# Reset double-tap if any other key is pressed
	if key_event.pressed:
		_last_shift_pressed = 0

	# Ctrl+E for Recent Files
	if key_event.pressed and not key_event.echo:
		if (
			key_event.ctrl_pressed
			and key_event.keycode == KEY_E
			and not key_event.shift_pressed
			and not key_event.alt_pressed
		):
			_show_recent_files()
			get_viewport().set_input_as_handled()
			return

	# Only detect key press (not release)
	if key_event.pressed and not key_event.echo:
		# Check if Alt is pressed
		if key_event.alt_pressed and not key_event.shift_pressed and not key_event.ctrl_pressed:
			# Number keys 1 (KEY_1) to 9 (KEY_9)
			if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_9:
				# Switch to 2D-View
				EditorInterface.set_main_screen_editor("2D")
				var index: int = int(key_event.keycode) - int(KEY_1)
				_activate_tab_by_index(index)

				# Consume input to prevent other editor actions
				get_viewport().set_input_as_handled()


func _on_button_pressed() -> void:
	_organize_tabs()


func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_popup_menu.set_position(
				_toolbar_button.get_screen_position() + Vector2(0, _toolbar_button.get_size().y)
			)
			_popup_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	match id:
		0:  # Organize Tabs
			_organize_tabs()
		1:  # Edit Keyword Weights
			_settings_proxy = SettingsProxy.new()
			_settings_proxy.keyword_weights = _get_keyword_weights()
			EditorInterface.inspect_object(_settings_proxy)
		2:  # Reset to Default
			_reset_confirm_dialog.popup_centered()


func _on_reset_confirmed() -> void:
	var settings := EditorInterface.get_editor_settings()
	var default_weights := _get_default_weights()
	settings.set_setting(SETTING_PATH, default_weights)
	_log.info("Keyword weights reset to default.")


func _on_inspector_obj_changed() -> void:
	if _is_alt_only_pressed():
		var obj := EditorInterface.get_inspector().get_edited_object()
		var node := obj as Node
		if node:
			var path := node.scene_file_path
			if not path.is_empty():
				_open_in_file_system(path)


func _on_inspector_property_selected(property: String) -> void:
	if _is_alt_only_pressed():
		var obj := EditorInterface.get_inspector().get_edited_object()
		if not obj:
			return
		var val: Variant = obj.get(property)
		var res := val as Resource
		if res and not res.resource_path.is_empty():
			_open_in_file_system(res.resource_path)


func _on_filesystem_changed() -> void:
	_log.debug("filesystem_changed detected.")

	# Wait a bit longer to ensure the editor has processed the file deletion
	await get_tree().create_timer(0.2).timeout

	var open_scenes := EditorInterface.get_open_scenes()
	if open_scenes.is_empty():
		_log.debug("No scenes open.")
		return

	var to_close: Array[int] = []
	for i in range(open_scenes.size()):
		var path := open_scenes[i]
		# Check both FileAccess and ResourceLoader for existence
		var exists := FileAccess.file_exists(path)
		if not exists:
			_log.info("File missing: {0}", [path])
			to_close.append(i)

	if to_close.is_empty():
		return

	var tab_bar := _find_scene_tab_bar(EditorInterface.get_base_control())
	if not tab_bar:
		_log.warn("Could not find the scene TabBar.")
		# For debugging, we can still use a helper to log structure but via _log
		_log_all_tab_bars(EditorInterface.get_base_control())
		return

	# Close from highest index to lowest to avoid index shifting
	to_close.sort()
	to_close.reverse()
	for index in to_close:
		_log.info("Closing tab index: {0} ({1})", [index, open_scenes[index]])
		tab_bar.tab_close_pressed.emit(index)


# ------------- [Private Method] -------------
func _find_and_setup_scene_tree() -> void:
	if _scene_tree_control and is_instance_valid(_scene_tree_control):
		return

	var base := EditorInterface.get_base_control()
	# Try to find by name directly first (more efficient)
	_scene_tree_control = base.find_child("SceneTree", true, false) as Tree

	if not _scene_tree_control:
		_scene_tree_control = _find_scene_tree_recursive(base)

	if _scene_tree_control:
		_log.info("Found SceneTree control.")
	else:
		_log.warn("SceneTree control NOT found.")


func _find_scene_tree_recursive(node: Node) -> Tree:
	if node is Tree:
		if node.name == "SceneTree":
			return node

		# In some Godot versions, it might be named differently but under a specific dock
		var parent := node.get_parent()
		if (
			parent
			and (parent.name.contains("SceneTree") or parent.get_class().contains("SceneTree"))
		):
			return node

	for child in node.get_children():
		var found := _find_scene_tree_recursive(child)
		if found:
			return found
	return null


func _update_scene_tree_tooltip() -> void:
	if not _scene_tree_control or not is_instance_valid(_scene_tree_control):
		_find_and_setup_scene_tree()
		if not _scene_tree_control:
			return

	if not _scene_tree_control.is_visible_in_tree():
		return

	var mouse_pos := _scene_tree_control.get_local_mouse_position()
	if (
		mouse_pos.x < 0
		or mouse_pos.y < 0
		or mouse_pos.x > _scene_tree_control.size.x
		or mouse_pos.y > _scene_tree_control.size.y
	):
		return

	var item := _scene_tree_control.get_item_at_position(mouse_pos)
	var is_ctrl_pressed := Input.is_key_pressed(KEY_CTRL)

	# We use a combined state to check if update is needed
	if item == _last_hovered_item and _last_ctrl_state == is_ctrl_pressed:
		return

	_last_hovered_item = item
	_last_ctrl_state = is_ctrl_pressed

	if not item:
		return

	_apply_tooltip(item, is_ctrl_pressed)


func _apply_tooltip(item: TreeItem, detailed: bool) -> void:
	var target_node: Variant = item.get_metadata(0)

	if target_node == null:
		for i in range(1, 3):
			var m: Variant = item.get_metadata(i)
			if m != null:
				target_node = m
				break

	var node: Node = null

	if target_node is Node:
		node = target_node
	elif target_node is NodePath:
		var path := target_node as NodePath
		var root := EditorInterface.get_edited_scene_root()
		if root:
			node = root.get_node_or_null(path)
			if not node:
				node = root.get_tree().root.get_node_or_null(path)

	if not node or not is_instance_valid(node):
		return

	var tooltip := _get_connections_tooltip(node, detailed)

	# We always apply if tooltip changed or if we need to ensure it's set
	for i in range(_scene_tree_control.columns):
		item.set_tooltip_text(i, tooltip)

	_scene_tree_control.tooltip_text = tooltip


func _get_connections_tooltip(node: Node, detailed: bool) -> String:
	var lines: Array[String] = []
	lines.append("Node: {0} ({1})".format([node.name, node.get_class()]))
	if not detailed:
		lines[0] += " [Ctrl for detail]"

	# Outgoing connections (Signals from this node)
	var outgoing: Array[String] = []
	for sig in node.get_signal_list():
		var sig_name: String = sig.name
		for conn in node.get_signal_connection_list(sig_name):
			# Filter: Default (not detailed) shows only connections registered in tscn (persistent)
			if not detailed:
				if not (conn.flags & CONNECT_PERSIST):
					continue
			var target: Object = conn.callable.get_object()
			var method: StringName = conn.callable.get_method()
			var target_name: String = target.name if target is Node else str(target)
			outgoing.append("  • {0} -> {1}::{2}".format([sig_name, target_name, method]))

	if not outgoing.is_empty():
		lines.append("\nSignals:")
		lines.append_array(outgoing)

	# Incoming connections (Connections to this node)
	var incoming: Array[String] = []
	for conn in node.get_incoming_connections():
		if not detailed:
			if not (conn.flags & CONNECT_PERSIST):
				continue

		var sig: Signal = conn.signal
		var source: Object = sig.get_object()

		# Optimization: Filter out self-connections from Incoming section
		# because they are already shown in the Signals section above.
		if source == node:
			continue

		var source_name: String = source.name if source is Node else str(source)
		var target_method: StringName = conn.callable.get_method()
		incoming.append("  • {0}::{1} -> {2}".format([source_name, sig.get_name(), target_method]))

	if not incoming.is_empty():
		lines.append("\nIncoming:")
		lines.append_array(incoming)

	if outgoing.is_empty() and incoming.is_empty():
		return "Node: {0}\n(No signal connections)".format([node.name])

	return "\n".join(lines)


func _log_all_tab_bars(node: Node) -> void:
	if node is TabBar:
		var tb := node as TabBar
		_log.debug(
			"  - TabBar: {0} (tabs: {1}) Parent: {2}", [tb.name, tb.tab_count, tb.get_parent().name]
		)
		if tb.tab_count > 0:
			_log.debug("    First tab: {0}", [tb.get_tab_title(0)])
	for child in node.get_children():
		_log_all_tab_bars(child)


func _on_scene_changed(root: Node) -> void:
	if not root:
		return
	_add_to_recent_files(root.scene_file_path)


func _on_script_changed(script: Script) -> void:
	if not script:
		return
	_add_to_recent_files(script.resource_path)


func _add_to_recent_files(path: String) -> void:
	if path.is_empty() or path.begins_with("local://"):
		return

	# Remove if already exists to move to top
	var idx := _recent_files.find(path)
	if idx != -1:
		_recent_files.remove_at(idx)

	_recent_files.push_front(path)

	# Limit size
	if _recent_files.size() > MAX_RECENT_FILES:
		_recent_files.resize(MAX_RECENT_FILES)

	# Save to settings
	EditorInterface.get_editor_settings().set_setting(RECENT_FILES_SETTING, _recent_files)


func _show_recent_files() -> void:
	if _recent_files.is_empty():
		_log.info("No recent files.")
		return

	var popup := PopupMenu.new()
	var base := EditorInterface.get_base_control()
	base.add_child(popup)

	for i in range(_recent_files.size()):
		var path := _recent_files[i]
		var file_name := path.get_file()
		var dir := path.get_base_dir().replace("res://", "")
		var icon: Texture2D

		if path.ends_with(".tscn") or path.ends_with(".scn"):
			icon = base.get_theme_icon("PackedScene", "EditorIcons")
		elif path.ends_with(".gd"):
			icon = base.get_theme_icon("GDScript", "EditorIcons")
		else:
			icon = base.get_theme_icon("Resource", "EditorIcons")

		popup.add_icon_item(icon, "{0} ({1})".format([file_name, dir]), i)

	popup.id_pressed.connect(
		func(id: int):
			var path := _recent_files[id]
			if path.ends_with(".tscn") or path.ends_with(".scn"):
				EditorInterface.open_scene_from_path(path)
			else:
				var res := ResourceLoader.load(path)
				if res:
					EditorInterface.edit_resource(res)
			popup.queue_free()
	)

	popup.popup_hide.connect(func(): popup.queue_free())

	var screen_rect := base.get_viewport_rect()
	var popup_size := popup.get_contents_minimum_size()
	popup.set_position(Vector2i(screen_rect.size / 2.0) - Vector2i(popup_size / 2.0))
	popup.popup()


func _on_double_shift_pressed() -> void:
	_log.debug("Double-tap Shift detected. Opening Quick Open Resource.")
	var callback := func(path: String):
		if path.is_empty():
			return

		# If Alt is held, select in FileSystem dock instead of opening
		if Input.is_key_pressed(KEY_ALT):
			_log.debug("Alt held. Selecting in FileSystem: {0}", [path])
			EditorInterface.select_file(path)
			return

		var res := ResourceLoader.load(path)
		if res is PackedScene:
			EditorInterface.open_scene_from_path(path)
		else:
			EditorInterface.edit_resource(res)

	EditorInterface.popup_quick_open(callback)


func _activate_tab_by_index(index: int) -> void:
	var scene_paths := EditorInterface.get_open_scenes()
	if index >= 0 and index < scene_paths.size():
		_log.debug("Activating tab {0}: {1}", [index, scene_paths[index]])
		EditorInterface.open_scene_from_path(scene_paths[index])


# Retrieves keyword and score pairs from editor settings in a type-safe manner
func _get_keyword_weights() -> Dictionary[String, int]:
	var settings := EditorInterface.get_editor_settings()
	var val: Variant = settings.get_setting(SETTING_PATH)

	var cleaned_weights: Dictionary[String, int] = {}
	if val is Dictionary:
		var dict_val: Dictionary = val
		for key in dict_val.keys():
			# check key-type for safety
			if not key is String:
				_log.error("Keyword weights dictionary contains a non-string key: {0}", [key])
				continue

			var key_str: String = key
			if key_str.strip_edges() == "":
				_log.warn("Keyword weights contain an empty or whitespace-only key. Skipping.")
				continue

			var val_int := int(dict_val[key])
			cleaned_weights[key_str] = val_int

	return cleaned_weights


# Locates the TabBar node from the Editor's UI tree
func _find_scene_tab_bar(node: Node) -> TabBar:
	if node is TabBar:
		var tb := node as TabBar
		var open_scenes := EditorInterface.get_open_scenes()

		if tb.tab_count == open_scenes.size() and tb.tab_count > 0:
			# Scene tabs often have "*" prefix if unsaved, but the base name should match
			var first_tab_title := tb.get_tab_title(0).replace("*", "")
			var first_scene_name := open_scenes[0].get_file()

			if first_tab_title == first_scene_name:
				return tb
			else:
				# Sometimes the title is truncated or has other decorations
				if (
					first_scene_name.begins_with(first_tab_title)
					or first_tab_title.begins_with(first_scene_name.get_basename())
				):
					return tb

	for child in node.get_children():
		var found := _find_scene_tab_bar(child)
		if found:
			return found
	return null


# Calculates priority based on the scene path
func _calc_priority(path: String, weights: Dictionary[String, int]) -> int:
	var score := 0
	var file_name := path.get_file()

	# Add points based on keyword matching
	for key in weights.keys():
		if file_name.findn(key) != -1:
			var weight := weights[key]
			score += weight

	return score


func _get_default_weights() -> Dictionary:
	return {
		"title": 50,
		"level_base": 30,
		"player": 10,
	}


func _organize_tabs() -> void:
	_log.info("Starting tab organization.")
	var tab_bar := _find_scene_tab_bar(EditorInterface.get_base_control())

	if not tab_bar:
		_log.warn("Could not find scene tab bar.")
		return

	var scene_paths := EditorInterface.get_open_scenes()
	if scene_paths.size() <= 1:
		_log.debug("Not enough scenes open to organize.")
		return

	# load weights
	var weights := _get_keyword_weights()
	var entries: Array[SortEnt] = []
	for path in scene_paths:
		entries.append(SortEnt.new(path, _calc_priority(path, weights)))

	# Sort in descending order of priority (higher score first)
	entries.sort_custom(func(a: SortEnt, b: SortEnt) -> bool: return a.priority > b.priority)

	var current_root := EditorInterface.get_edited_scene_root()
	var prev_opened_scene := ""
	if current_root:
		prev_opened_scene = current_root.scene_file_path

	# Execute tab rearrangement
	for i in range(entries.size()):
		# Wait slightly to stabilize processing
		await get_tree().process_frame

		var current_paths := EditorInterface.get_open_scenes()
		var target_path := entries[i].path

		var from_idx: int = -1
		for k in range(current_paths.size()):
			if current_paths[k] == target_path:
				from_idx = k
				break

		if from_idx != -1 and from_idx != i:
			_move_tab_to(from_idx, i, tab_bar)

	if prev_opened_scene != "":
		EditorInterface.open_scene_from_path(prev_opened_scene)

	_log.info("Tab organization completed.")


func _move_tab_to(from_idx: int, to_idx: int, tab_bar: TabBar) -> void:
	if from_idx == to_idx:
		return

	var scene_paths := EditorInterface.get_open_scenes()

	EditorInterface.open_scene_from_path(scene_paths[from_idx])
	tab_bar.move_tab(from_idx, to_idx)
	tab_bar.active_tab_rearranged.emit(to_idx)


func _is_alt_only_pressed() -> bool:
	# Check if only alt key is pressed (no Shift, Ctrl, or Meta/Command)
	var is_alt_only := (
		Input.is_key_pressed(KEY_ALT)
		and not Input.is_key_pressed(KEY_SHIFT)
		and not Input.is_key_pressed(KEY_CTRL)
		and not Input.is_key_pressed(KEY_META)
	)

	if not is_alt_only:
		return false

	# Check if number keys 0~9 are NOT pressed (to avoid conflict with tab switching)
	for i in range(10):
		if Input.is_key_pressed(KEY_0 + i):
			return false

	return true


func _open_in_file_system(path: String) -> void:
	# Prevent double-triggering
	var now := Time.get_unix_time_from_system()
	if now - _last_operated < _OPERATE_DELAY:
		return
	_last_operated = now

	_log.debug("Opening in FileSystem: {0}", [path])
	EditorInterface.select_file(path)


# ------------- [Private Class] -------------
class SettingsProxy:
	extends RefCounted
	@export var keyword_weights: Dictionary[String, int]:
		set(val):
			keyword_weights = val
			EditorInterface.get_editor_settings().set_setting(SETTING_PATH, val)


class SortEnt:
	var path: String
	var priority: int

	func _init(p: String, pr: int) -> void:
		path = p
		priority = pr
