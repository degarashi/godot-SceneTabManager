@tool
extends EditorPlugin

# ------------- [Constants] -------------
const SETTING_PATH: String = "editors/plugins/scene_tab_manager/keyword_weights"
const SHORTCUT_RECENT_FILES: String = "editors/plugins/scene_tab_manager/shortcuts/recent_files"
const ENABLE_DOUBLE_SHIFT: String = "editors/plugins/scene_tab_manager/shortcuts/enable_double_shift"
const ENABLE_ALT_TAB_SWITCHING: String = "editors/plugins/scene_tab_manager/shortcuts/enable_alt_tab_switching"
const ENABLE_ALT_CLICK_LOCATE: String = "editors/plugins/scene_tab_manager/shortcuts/enable_alt_click_locate"
const _OPERATE_DELAY: float = 0.25

# ------------- [Static Variable] -------------
static var _log := DLoggerClass.new("SceneTabManager")

# ------------- [Private Variable] -------------
var _toolbar_button: Button
var _popup_menu: PopupMenu
var _settings_proxy: RefCounted
var _reset_confirm_dialog: ConfirmationDialog
var _last_operated: float = 0.0

# Modules
var _tab_organizer: TabOrganizer
var _recent_files_manager: RecentFilesManager
var _signal_tooltip_handler: SignalTooltipHandler
var _shortcut_handler: ShortcutHandler


# ------------- [Callbacks] -------------
func _enter_tree() -> void:
	_log.info("Plugin initialized.")

	# Initialize modules
	_tab_organizer = TabOrganizer.new(_log)
	_recent_files_manager = RecentFilesManager.new(_log)
	_signal_tooltip_handler = SignalTooltipHandler.new(_log)
	_shortcut_handler = ShortcutHandler.new(_log)

	var settings := EditorInterface.get_editor_settings()
	var default_weights := _get_default_weights()

	if not settings.has_setting(SETTING_PATH):
		settings.set_setting(SETTING_PATH, default_weights)
		settings.set_initial_value(SETTING_PATH, default_weights, false)
		var property_info: Dictionary = {
			"name": SETTING_PATH,
			"type": TYPE_DICTIONARY,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "Keyword:Priority-Score"
		}
		settings.add_property_info(property_info)

	_register_setting(
		SHORTCUT_RECENT_FILES, "Ctrl+E", TYPE_STRING, "Shortcut for Recent Files popup"
	)
	_register_setting(
		ENABLE_DOUBLE_SHIFT, true, TYPE_BOOL, "Enable double-tap Shift for Quick Open"
	)
	_register_setting(
		ENABLE_ALT_TAB_SWITCHING, true, TYPE_BOOL, "Enable Alt + 1-9 for Tab Switching"
	)
	_register_setting(ENABLE_ALT_CLICK_LOCATE, true, TYPE_BOOL, "Enable Alt + Click to locate file")

	# Setup UI
	_toolbar_button = Button.new()
	var editor_base := EditorInterface.get_base_control()
	_toolbar_button.icon = editor_base.get_theme_icon("Folder", "EditorIcons")
	_toolbar_button.text = "Organize"
	_toolbar_button.tooltip_text = "Sort scene tabs (Right-click for settings)"
	_toolbar_button.flat = true
	_toolbar_button.pressed.connect(_on_button_pressed)
	_toolbar_button.gui_input.connect(_on_button_gui_input)

	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)

	_popup_menu = PopupMenu.new()
	_popup_menu.add_item("Organize Tabs", 0)
	_popup_menu.add_separator()
	_popup_menu.add_item("Edit Keyword Weights...", 1)
	_popup_menu.add_item("Reset to Default", 2)
	_popup_menu.id_pressed.connect(_on_menu_id_pressed)
	_toolbar_button.add_child(_popup_menu)

	_reset_confirm_dialog = ConfirmationDialog.new()
	_reset_confirm_dialog.dialog_text = "Reset keyword weights to default?"
	_reset_confirm_dialog.confirmed.connect(_on_reset_confirmed)
	_toolbar_button.add_child(_reset_confirm_dialog)

	# Signals
	EditorInterface.get_inspector().edited_object_changed.connect(_on_inspector_obj_changed)
	EditorInterface.get_inspector().property_selected.connect(_on_inspector_property_selected)
	EditorInterface.get_inspector().resource_selected.connect(_on_inspector_resource_selected)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	scene_changed.connect(_on_scene_changed)
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_script_changed)


func _exit_tree() -> void:
	if _toolbar_button:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)
		_toolbar_button.queue_free()

	if _signal_tooltip_handler:
		_signal_tooltip_handler.cleanup()

	var insp := EditorInterface.get_inspector()
	if insp:
		if insp.edited_object_changed.is_connected(_on_inspector_obj_changed):
			insp.edited_object_changed.disconnect(_on_inspector_obj_changed)
		if insp.property_selected.is_connected(_on_inspector_property_selected):
			insp.property_selected.disconnect(_on_inspector_property_selected)
		if insp.resource_selected.is_connected(_on_inspector_resource_selected):
			insp.resource_selected.disconnect(_on_inspector_resource_selected)

	var efs := EditorInterface.get_resource_filesystem()
	if efs and efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.disconnect(_on_filesystem_changed)


func _process(delta: float) -> void:
	if _signal_tooltip_handler:
		_signal_tooltip_handler.process(delta)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey

	# Recent Files popup handling
	if _recent_files_manager.is_popup_visible():
		if key_event.pressed:
			var key := key_event.keycode
			var idx := -1
			if key >= KEY_1 and key <= KEY_9:
				idx = int(key) - int(KEY_1)
			elif key == KEY_0:
				idx = 9

			if idx != -1 and idx < _recent_files_manager.get_recent_files_count():
				_log.debug("Numeric key {0} pressed. Focusing index {1}.", [key, idx])
				_recent_files_manager.set_popup_focused_item(idx)
				get_viewport().set_input_as_handled()
				return

	# Double-tap Shift
	var double_shift_triggered := _shortcut_handler.handle_double_shift(
		key_event, _on_double_shift_pressed
	)
	if double_shift_triggered:
		get_viewport().set_input_as_handled()
		return

	# Shortcut for Recent Files
	if key_event.pressed and not key_event.echo:
		if _shortcut_handler.is_shortcut_pressed(key_event, SHORTCUT_RECENT_FILES):
			_recent_files_manager.show_recent_files()
			get_viewport().set_input_as_handled()
			return

		# Alt + 1-9 Tab Switching
		if (
			_shortcut_handler.get_setting(ENABLE_ALT_TAB_SWITCHING)
			and key_event.alt_pressed
			and not key_event.shift_pressed
			and not key_event.ctrl_pressed
			and key_event.keycode >= KEY_1
			and key_event.keycode <= KEY_9
		):
			EditorInterface.set_main_screen_editor("2D")
			var index := int(key_event.keycode) - int(KEY_1)
			_activate_tab_by_index(index)
			get_viewport().set_input_as_handled()
			return


func _on_button_pressed() -> void:
	_tab_organizer.organize_tabs()


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
		0:
			_tab_organizer.organize_tabs()
		1:
			_settings_proxy = SettingsProxy.new()
			_settings_proxy.keyword_weights = _get_keyword_weights()
			_settings_proxy.shortcut_recent_files = _shortcut_handler.get_setting(
				SHORTCUT_RECENT_FILES
			)
			_settings_proxy.shortcut_enable_double_shift = _shortcut_handler.get_setting(
				ENABLE_DOUBLE_SHIFT
			)
			_settings_proxy.shortcut_enable_alt_tab_switching = _shortcut_handler.get_setting(
				ENABLE_ALT_TAB_SWITCHING
			)
			_settings_proxy.shortcut_enable_alt_click_locate = _shortcut_handler.get_setting(
				ENABLE_ALT_CLICK_LOCATE
			)
			EditorInterface.inspect_object(_settings_proxy)
		2:
			_reset_confirm_dialog.popup_centered()


func _on_reset_confirmed() -> void:
	EditorInterface.get_editor_settings().set_setting(SETTING_PATH, _get_default_weights())
	_log.info("Keyword weights reset to default.")


func _on_inspector_obj_changed() -> void:
	if _shortcut_handler.get_setting(ENABLE_ALT_CLICK_LOCATE) and _is_alt_only_pressed():
		var obj := EditorInterface.get_inspector().get_edited_object()
		if obj is Node and not obj.scene_file_path.is_empty():
			_open_in_file_system(obj.scene_file_path)


func _on_inspector_property_selected(property: String) -> void:
	if _shortcut_handler.get_setting(ENABLE_ALT_CLICK_LOCATE) and _is_alt_only_pressed():
		var obj := EditorInterface.get_inspector().get_edited_object()
		if not obj:
			return
		var res := obj.get(property) as Resource
		if res and not res.resource_path.is_empty():
			_open_in_file_system(res.resource_path)


func _on_inspector_resource_selected(res: Resource, _prop: String) -> void:
	if _shortcut_handler.get_setting(ENABLE_ALT_CLICK_LOCATE) and _is_alt_only_pressed():
		if res and not res.resource_path.is_empty():
			_open_in_file_system(res.resource_path)


func _on_filesystem_changed() -> void:
	await get_tree().create_timer(0.2).timeout
	var open_scenes := EditorInterface.get_open_scenes()
	var to_close: Array[int] = []
	for i in range(open_scenes.size()):
		if not FileAccess.file_exists(open_scenes[i]):
			to_close.append(i)
	if to_close.is_empty():
		return
	var tab_bar := _find_scene_tab_bar(EditorInterface.get_base_control())
	if not tab_bar:
		return
	to_close.sort()
	to_close.reverse()
	for index in to_close:
		tab_bar.tab_close_pressed.emit(index)


# ------------- [Private Method] -------------
func _register_setting(path: String, default: Variant, type: int, hint: String = "") -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		settings.set_setting(path, default)
		settings.set_initial_value(path, default, false)
		settings.add_property_info(
			{"name": path, "type": type, "hint": PROPERTY_HINT_NONE, "hint_string": hint}
		)


func _find_scene_tab_bar(node: Node) -> TabBar:
	if node is TabBar:
		var tb := node as TabBar
		var open_scenes := EditorInterface.get_open_scenes()
		if tb.tab_count == open_scenes.size() and tb.tab_count > 0:
			var title: String = tb.get_tab_title(0).replace("*", "")
			var file := open_scenes[0].get_file()
			if title == file or file.begins_with(title) or title.begins_with(file.get_basename()):
				return tb
	for child in node.get_children():
		var found := _find_scene_tab_bar(child)
		if found:
			return found
	return null


func _on_scene_changed(root: Node) -> void:
	if root:
		_recent_files_manager.add_to_recent_files(root.scene_file_path)


func _on_script_changed(script: Script) -> void:
	if script:
		_recent_files_manager.add_to_recent_files(script.resource_path)


func _on_double_shift_pressed() -> void:
	EditorInterface.popup_quick_open(
		func(path: String):
			if path.is_empty():
				return
			if Input.is_key_pressed(KEY_ALT):
				EditorInterface.select_file(path)
				var fs_dock := EditorInterface.get_file_system_dock()
				var parent := fs_dock.get_parent()
				if parent is TabContainer:
					parent.current_tab = fs_dock.get_index()
			elif path.ends_with(".tscn") or path.ends_with(".scn"):
				EditorInterface.open_scene_from_path(path)
			else:
				EditorInterface.edit_resource(ResourceLoader.load(path))
	)


func _activate_tab_by_index(index: int) -> void:
	var paths := EditorInterface.get_open_scenes()
	if index >= 0 and index < paths.size():
		EditorInterface.open_scene_from_path(paths[index])


func _get_keyword_weights() -> Dictionary:
	var val: Variant = EditorInterface.get_editor_settings().get_setting(SETTING_PATH)
	return val if val is Dictionary else {}


func _get_default_weights() -> Dictionary:
	return {"title": 50, "level_base": 30, "player": 10}


func _is_alt_only_pressed() -> bool:
	if not (
		Input.is_key_pressed(KEY_ALT)
		and not (
			Input.is_key_pressed(KEY_SHIFT)
			or Input.is_key_pressed(KEY_CTRL)
			or Input.is_key_pressed(KEY_META)
		)
	):
		return false
	for i in range(10):
		if Input.is_key_pressed(KEY_0 + i):
			return false
	return true


func _open_in_file_system(path: String) -> void:
	var now := Time.get_unix_time_from_system()
	if now - _last_operated < _OPERATE_DELAY:
		return
	_last_operated = now
	EditorInterface.select_file(path)
	var fs_dock := EditorInterface.get_file_system_dock()
	var parent := fs_dock.get_parent()
	if parent is TabContainer:
		parent.current_tab = fs_dock.get_index()


# ------------- [Private Class] -------------
class SettingsProxy:
	extends RefCounted
	@export var keyword_weights: Dictionary[String, int]:
		set(val):
			keyword_weights = val
			EditorInterface.get_editor_settings().set_setting(SETTING_PATH, val)
	@export_group("Shortcuts", "shortcut_")
	@export var shortcut_recent_files: String:
		set(val):
			shortcut_recent_files = val
			EditorInterface.get_editor_settings().set_setting(SHORTCUT_RECENT_FILES, val)
	@export var shortcut_enable_double_shift: bool:
		set(val):
			shortcut_enable_double_shift = val
			EditorInterface.get_editor_settings().set_setting(ENABLE_DOUBLE_SHIFT, val)
	@export var shortcut_enable_alt_tab_switching: bool:
		set(val):
			shortcut_enable_alt_tab_switching = val
			EditorInterface.get_editor_settings().set_setting(ENABLE_ALT_TAB_SWITCHING, val)
	@export var shortcut_enable_alt_click_locate: bool:
		set(val):
			shortcut_enable_alt_click_locate = val
			EditorInterface.get_editor_settings().set_setting(ENABLE_ALT_CLICK_LOCATE, val)
