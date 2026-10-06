class_name NodePool
extends RefCounted
## Reusable node pool (prewarm / acquire / release) to avoid instantiate/free
## churn during gameplay. Released nodes are hidden and parked, never freed.

var created_count: int = 0
var _factory: Callable
var _parent: Node
var _free: Array[Node] = []
var _active: Array[Node] = []
var _reset_method: StringName = &"pool_reset"


func _init(factory: Callable, parent: Node, prewarm: int = 0) -> void:
	_factory = factory
	_parent = parent
	for _i: int in prewarm:
		_free.append(_create())


func _create() -> Node:
	var node: Node = _factory.call() as Node
	created_count += 1
	_hide(node)
	_parent.add_child(node)
	return node


func acquire() -> Node:
	var node: Node = _free.pop_back() if not _free.is_empty() else _create()
	_active.append(node)
	if node is Node3D:
		(node as Node3D).visible = true
	elif node is CanvasItem:
		(node as CanvasItem).visible = true
	node.process_mode = Node.PROCESS_MODE_INHERIT
	return node


func release(node: Node) -> void:
	var idx: int = _active.find(node)
	if idx < 0:
		return
	_active.remove_at(idx)
	if node.has_method(_reset_method):
		node.call(_reset_method)
	_hide(node)
	_free.append(node)


func active_count() -> int:
	return _active.size()


func free_count() -> int:
	return _free.size()


func _hide(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).visible = false
	elif node is CanvasItem:
		(node as CanvasItem).visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
