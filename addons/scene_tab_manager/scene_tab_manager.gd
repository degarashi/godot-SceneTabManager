@tool
extends EditorPlugin

# Path for the configuration setting
const SETTING_PATH: String = "editors/plugins/scene_tab_manager/keyword_weights"

var _toolbar_button: Button


func _enter_tree() -> void:
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


func _exit_tree() -> void:
	if _toolbar_button:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)
		_toolbar_button.queue_free()


# Use _input instead of _shortcut_input
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey

	# Only detect key press (not release)
	if key_event.pressed and not key_event.echo:
		# Check if Alt is pressed
		if key_event.alt_pressed:
			# Number keys 1 (KEY_1) to 9 (KEY_9)
			if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_9:
				# Switch to 2D-View
				EditorInterface.set_main_screen_editor("2D")
				var index: int = int(key_event.keycode) - int(KEY_1)
				_activate_tab_by_index(index)

				# Consume input to prevent other editor actions
				get_viewport().set_input_as_handled()


func _activate_tab_by_index(index: int) -> void:
	var scene_paths := EditorInterface.get_open_scenes()
	if index >= 0 and index < scene_paths.size():
		EditorInterface.open_scene_from_path(scene_paths[index])


func _on_button_pressed() -> void:
	_organize_tabs()


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
				push_error(
					"SceneTabManager: Keyword weights dictionary contains a non-string key: ", key
				)
				continue

			var key_str: String = key
			if key_str.strip_edges() == "":
				push_warning(
					"SceneTabManager: Keyword weights contain an empty or whitespace-only key. Skipping."
				)
				continue

			var val_int := int(dict_val[key])
			cleaned_weights[key_str] = val_int

	return cleaned_weights


# Locates the TabBar node from the Editor's UI tree
func _find_scene_tab_bar(node: Node) -> TabBar:
	if node is TabBar:
		return node as TabBar
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


class SortEnt:
	var path: String
	var priority: int

	func _init(p: String, pr: int) -> void:
		path = p
		priority = pr


func _organize_tabs() -> void:
	var tab_bar := _find_scene_tab_bar(EditorInterface.get_base_control())

	if not tab_bar:
		return

	var scene_paths := EditorInterface.get_open_scenes()
	if scene_paths.size() <= 1:
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


func _move_tab_to(from_idx: int, to_idx: int, tab_bar: TabBar) -> void:
	if from_idx == to_idx:
		return

	var scene_paths := EditorInterface.get_open_scenes()

	EditorInterface.open_scene_from_path(scene_paths[from_idx])
	tab_bar.move_tab(from_idx, to_idx)
	tab_bar.active_tab_rearranged.emit(to_idx)
