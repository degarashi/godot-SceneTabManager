@tool
class_name ShortcutHandler
extends RefCounted

# ------------- [Constants] -------------
const SHORTCUT_RECENT_FILES: String = "editors/plugins/scene_tab_manager/shortcuts/recent_files"
const ENABLE_DOUBLE_SHIFT: String = "editors/plugins/scene_tab_manager/shortcuts/enable_double_shift"
const ENABLE_ALT_TAB_SWITCHING: String = "editors/plugins/scene_tab_manager/shortcuts/enable_alt_tab_switching"
const ENABLE_ALT_CLICK_LOCATE: String = "editors/plugins/scene_tab_manager/shortcuts/enable_alt_click_locate"
const SHIFT_DOUBLE_TAP_THRESHOLD: int = 300

# ------------- [Private Variable] -------------
var _log: RefCounted
var _last_shift_pressed: int = 0


# ------------- [Public Method] -------------
func _init(logger: RefCounted) -> void:
	_log = logger


func get_setting(path: String, default: Variant = null) -> Variant:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(path):
		return settings.get_setting(path)
	return default


func is_shortcut_pressed(event: InputEventKey, setting_path: String) -> bool:
	var shortcut_str: String = get_setting(setting_path, "")
	if shortcut_str.is_empty():
		return false
	return event.as_text().to_lower() == shortcut_str.to_lower()


func handle_double_shift(event: InputEventKey, on_triggered: Callable) -> bool:
	if event.keycode == KEY_SHIFT:
		if get_setting(ENABLE_DOUBLE_SHIFT) and event.pressed and not event.echo:
			var now := Time.get_ticks_msec()
			if now - _last_shift_pressed < SHIFT_DOUBLE_TAP_THRESHOLD:
				on_triggered.call()
				_last_shift_pressed = 0
				return true
			else:
				_last_shift_pressed = now
		return true  # Handled SHIFT press but not yet double-tap

	if event.pressed:
		_last_shift_pressed = 0
	return false


func reset_shift_timer() -> void:
	_last_shift_pressed = 0
