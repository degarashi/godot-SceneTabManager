@tool
extends EditorPlugin

# Path for the configuration setting
const SETTING_PATH: String = "editors/plugins/scene_tab_manager/keyword_weights"

var _toolbar_button: Button


func _enter_tree() -> void:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()

	# Define default priority weights based on keywords
	var default_weights: Dictionary[String, int] = {
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
	var editor_base := get_editor_interface().get_base_control()
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


func _on_button_pressed() -> void:
	_organize_tabs()


# Retrieves keyword and score pairs from editor settings in a type-safe manner
func _get_keyword_weights() -> Dictionary[String,int]:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	var val: Variant = settings.get_setting(SETTING_PATH)

	var cleaned_weights: Dictionary[String, int] = {}
	if val is Dictionary:
		var dict_val: Dictionary = val
		for k in dict_val.keys():
			# Force type conversion during retrieval for safety
			var key_str := str(k)
			var val_int := int(dict_val[k])
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
func _calc_priority(path: String) -> int:
	var score := 0
	var file_name := path.get_file()
	var weights := _get_keyword_weights()

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
	var interface := get_editor_interface()
	var tab_bar := _find_scene_tab_bar(interface.get_base_control())

	if not tab_bar:
		return

	var scene_paths := interface.get_open_scenes()
	if scene_paths.size() <= 1:
		return

	var entries: Array[SortEnt] = []
	for path in scene_paths:
		entries.append(SortEnt.new(path, _calc_priority(path)))

	# Sort in descending order of priority (higher score first)
	entries.sort_custom(func(a: SortEnt, b: SortEnt) -> bool: return a.priority > b.priority)

	var prev_opened_scene := interface.get_edited_scene_root().scene_file_path

	# Execute tab rearrangement
	for i in range(entries.size()):
		await get_tree().create_timer(0.05).timeout

		var current_paths := interface.get_open_scenes()
		var target_path := entries[i].path

		var from_idx: int = -1
		for k in range(current_paths.size()):
			if current_paths[k] == target_path:
				from_idx = k
				break

		if from_idx != -1 and from_idx != i:
			_move_tab_to(from_idx, i, tab_bar)

	# Restore the previously active scene
	interface.open_scene_from_path(prev_opened_scene)


func _move_tab_to(from_idx: int, to_idx: int, tab_bar: TabBar) -> void:
	if from_idx == to_idx:
		return

	var ifc: EditorInterface = get_editor_interface()
	var scene_paths: PackedStringArray = ifc.get_open_scenes()

	ifc.open_scene_from_path(scene_paths[from_idx])
	tab_bar.move_tab(from_idx, to_idx)
	tab_bar.active_tab_rearranged.emit(to_idx)
