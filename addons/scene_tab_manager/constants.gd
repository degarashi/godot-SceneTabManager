@tool
class_name STMConstants
extends Object

# ------------- [Constants] -------------
const SETTING_PATH: String = "editors/plugins/scene_tab_manager/keyword_weights"
const SHORTCUT_RECENT_FILES: String = "editors/plugins/scene_tab_manager/shortcuts/recent_files"
const ENABLE_DOUBLE_SHIFT: String = "editors/plugins/scene_tab_manager/shortcuts/enable_double_shift"
const ENABLE_ALT_TAB_SWITCHING: String = "editors/plugins/scene_tab_manager/shortcuts/enable_alt_tab_switching"
const ENABLE_ALT_CLICK_LOCATE: String = "editors/plugins/scene_tab_manager/shortcuts/enable_alt_click_locate"

const RECENT_FILES_SECTION: String = "scene_tab_manager"
const RECENT_FILES_KEY: String = "recent_files"


# ------------- [Public Method] -------------
static func find_scene_tab_bar(node: Node) -> TabBar:
	if node is TabBar:
		var tb := node as TabBar
		var open_scenes := EditorInterface.get_open_scenes()
		if tb.tab_count == open_scenes.size() and tb.tab_count > 0:
			var title: String = tb.get_tab_title(0).replace("*", "")
			var file := open_scenes[0].get_file()
			if title == file or file.begins_with(title) or title.begins_with(file.get_basename()):
				return tb
	for child in node.get_children():
		var found := find_scene_tab_bar(child)
		if found:
			return found
	return null
