@tool
class_name SignalTooltipHandler
extends RefCounted

# ------------- [Constants] -------------
const _TOOLTIP_UPDATE_INTERVAL: float = 0.1

# ------------- [Private Variable] -------------
var _log: RefCounted
var _scene_tree_control: Tree
var _last_hovered_item: TreeItem
var _last_ctrl_state: bool = false
var _tooltip_timer: float = 0.0


# ------------- [Public Method] -------------
func _init(logger: RefCounted) -> void:
	_log = logger
	_find_and_setup_scene_tree()


func process(delta: float) -> void:
	_tooltip_timer += delta
	if _tooltip_timer >= _TOOLTIP_UPDATE_INTERVAL:
		_tooltip_timer = 0.0
		_update_scene_tree_tooltip()


func cleanup() -> void:
	_scene_tree_control = null
	_last_hovered_item = null


# ------------- [Private Method] -------------
func _find_and_setup_scene_tree() -> void:
	if _scene_tree_control and is_instance_valid(_scene_tree_control):
		return

	var base := EditorInterface.get_base_control()
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

	for i in range(_scene_tree_control.columns):
		item.set_tooltip_text(i, tooltip)

	_scene_tree_control.tooltip_text = tooltip


func _get_connections_tooltip(node: Node, detailed: bool) -> String:
	var lines: Array[String] = []
	lines.append("Node: {0} ({1})".format([node.name, node.get_class()]))
	if not detailed:
		lines[0] += " [Ctrl for detail]"

	var outgoing: Array[String] = []
	for sig in node.get_signal_list():
		var sig_name: String = sig.name
		for conn in node.get_signal_connection_list(sig_name):
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

	var incoming: Array[String] = []
	for conn in node.get_incoming_connections():
		if not detailed:
			if not (conn.flags & CONNECT_PERSIST):
				continue

		var sig: Signal = conn.signal
		var source: Object = sig.get_object()

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
