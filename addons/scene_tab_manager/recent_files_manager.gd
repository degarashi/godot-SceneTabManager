@tool
class_name RecentFilesManager
extends RefCounted

# ------------- [Constants] -------------
const MAX_RECENT_FILES: int = 15

# ------------- [Private Variable] -------------
var _log: DLoggerClass
var _recent_files: Array[String] = []
var _recent_popup: PopupMenu


# ------------- [Public Method] -------------
func _init(logger: DLoggerClass) -> void:
	_log = logger
	_load_recent_files()


func show_recent_files() -> void:
	if _recent_files.is_empty():
		_log.info("No recent files.")
		return

	if _recent_popup:
		_recent_popup.queue_free()

	_recent_popup = PopupMenu.new()
	var popup := _recent_popup
	popup.exclusive = false
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

		var prefix := ""
		if i < 9:
			prefix = str(i + 1) + ". "
		elif i == 9:
			prefix = "0. "

		popup.add_icon_item(icon, "{0}{1} ({2})".format([prefix, file_name, dir]), i)

	popup.id_pressed.connect(func(id: int): open_recent_file_by_index(id))

	popup.popup_hide.connect(
		func():
			popup.queue_free()
			if _recent_popup == popup:
				_recent_popup = null
	)

	var screen_rect := base.get_viewport_rect()
	var popup_size := popup.get_contents_minimum_size()
	popup.set_position(Vector2i(screen_rect.size / 2.0) - Vector2i(popup_size / 2.0))
	popup.popup()


func open_recent_file_by_index(idx: int) -> void:
	if idx < 0 or idx >= _recent_files.size():
		return

	var path := _recent_files[idx]
	_log.debug("Opening recent file: {0}", [path])

	if path.ends_with(".tscn") or path.ends_with(".scn"):
		EditorInterface.open_scene_from_path(path)
	else:
		var res := ResourceLoader.load(path)
		if res:
			EditorInterface.edit_resource(res)


func add_to_recent_files(path: String) -> void:
	if path.is_empty() or path.begins_with("local://"):
		return

	var idx := _recent_files.find(path)
	if idx != -1:
		_recent_files.remove_at(idx)

	_recent_files.push_front(path)

	if _recent_files.size() > MAX_RECENT_FILES:
		_recent_files.resize(MAX_RECENT_FILES)

	EditorInterface.get_editor_settings().set_project_metadata(
		STMConstants.RECENT_FILES_SECTION, STMConstants.RECENT_FILES_KEY, _recent_files
	)


func is_popup_visible() -> bool:
	return _recent_popup != null and _recent_popup.visible


func set_popup_focused_item(idx: int) -> void:
	if _recent_popup:
		_recent_popup.set_focused_item(idx)


func get_recent_files_count() -> int:
	return _recent_files.size()


# ------------- [Private Method] -------------
func _load_recent_files() -> void:
	var settings := EditorInterface.get_editor_settings()
	var saved: Variant = settings.get_project_metadata(
		STMConstants.RECENT_FILES_SECTION, STMConstants.RECENT_FILES_KEY, []
	)

	if saved is Array:
		for item in saved:
			if item is String:
				_recent_files.append(item)
