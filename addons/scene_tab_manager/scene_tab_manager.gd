@tool
extends EditorPlugin

# ------------- [Constants] -------------
# Path for the configuration setting
const SETTING_PATH: String = "editors/plugins/scene_tab_manager/keyword_weights"
const _OPERATE_DELAY: float = 0.25

# ------------- [Static Variable] -------------
static var _log := DLoggerClass.new("SceneTabManager")

# ------------- [Private Variable] -------------
var _toolbar_button: Button
var _last_operated: float = 0.0


# ------------- [Callbacks] -------------
func _enter_tree() -> void:
	_log.info("Plugin initialized.")
	var settings := EditorInterface.get_editor_settings()

	# Define default priority weights based on keywords
	var default_weights: Dictionary = {
		"title": 50,
		"level_base": 30,
		"player": 10,
	}

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
	_toolbar_button.tooltip_text = "Sort scene tabs based on keyword weights"
	_toolbar_button.flat = true
	_toolbar_button.pressed.connect(_on_button_pressed)

	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)

	# Connect to inspector signals for Alt-click feature
	var insp := EditorInterface.get_inspector()
	insp.edited_object_changed.connect(_on_inspector_obj_changed)
	insp.property_selected.connect(_on_inspector_property_selected)

	# Connect to filesystem signals
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	if _toolbar_button:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)
		_toolbar_button.queue_free()

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


# Use _input instead of _shortcut_input
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey

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


func _activate_tab_by_index(index: int) -> void:
	var scene_paths := EditorInterface.get_open_scenes()
	if index >= 0 and index < scene_paths.size():
		_log.debug("Activating tab {0}: {1}", [index, scene_paths[index]])
		EditorInterface.open_scene_from_path(scene_paths[index])


# Retrieves keyword and score pairs from editor settings in a type-safe manner
func _get_keyword_weights() -> Dictionary[String,int]:
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
class SortEnt:
	var path: String
	var priority: int

	func _init(p: String, pr: int) -> void:
		path = p
		priority = pr
