@tool
class_name TabOrganizer
extends RefCounted

# ------------- [Constants] -------------
const SETTING_PATH: String = "editors/plugins/scene_tab_manager/keyword_weights"

# ------------- [Private Variable] -------------
var _log: RefCounted


# ------------- [Public Method] -------------
func _init(logger: RefCounted) -> void:
	_log = logger


func organize_tabs() -> void:
	_log.info("Starting tab organization.")
	var base_control := EditorInterface.get_base_control()
	var tab_bar := _find_scene_tab_bar(base_control)

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
		await EditorInterface.get_base_control().get_tree().process_frame

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


# ------------- [Private Method] -------------
func _get_keyword_weights() -> Dictionary[String, int]:
	var settings := EditorInterface.get_editor_settings()
	var val: Variant = settings.get_setting(SETTING_PATH)

	var cleaned_weights: Dictionary[String, int] = {}
	if val is Dictionary:
		var dict_val: Dictionary = val
		for key in dict_val.keys():
			if not key is String:
				continue

			var key_str: String = key
			if key_str.strip_edges() == "":
				continue

			var val_int := int(dict_val[key])
			cleaned_weights[key_str] = val_int

	return cleaned_weights


func _find_scene_tab_bar(node: Node) -> TabBar:
	if node is TabBar:
		var tb := node as TabBar
		var open_scenes := EditorInterface.get_open_scenes()

		if tb.tab_count == open_scenes.size() and tb.tab_count > 0:
			var first_tab_title := tb.get_tab_title(0).replace("*", "")
			var first_scene_name := open_scenes[0].get_file()

			if first_tab_title == first_scene_name:
				return tb
			else:
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


func _calc_priority(path: String, weights: Dictionary[String, int]) -> int:
	var score := 0
	var file_name := path.get_file()

	for key in weights.keys():
		if file_name.findn(key) != -1:
			var weight := weights[key]
			score += weight

	return score


func _move_tab_to(from_idx: int, to_idx: int, tab_bar: TabBar) -> void:
	if from_idx == to_idx:
		return

	var scene_paths := EditorInterface.get_open_scenes()
	EditorInterface.open_scene_from_path(scene_paths[from_idx])
	tab_bar.move_tab(from_idx, to_idx)
	tab_bar.active_tab_rearranged.emit(to_idx)


# ------------- [Private Class] -------------
class SortEnt:
	var path: String
	var priority: int

	func _init(p: String, pr: int) -> void:
		path = p
		priority = pr
