# object_pool.gd — reuse instances of one PackedScene instead of instantiating
# and freeing every frame. Bullets, hit sparks, damage numbers, footstep decals.
#
# Expected scene tree (node name : type):
#   Level : Node2D
#     BulletPool : Node               <- attach this script here
#   Pooled nodes are parked as children of the pool while free, and reparented
#   by the caller (add_child) when acquired.
#   unique_name_in_owner: mark the pool unique (`%BulletPool`) so spawners can
#   reach it with one path.
#
# Autoload: no. Declares `class_name ObjectPool`; run
#   godot --headless --path /absolute/path/to/project --import
# after copying it, before any script annotates a variable as `ObjectPool`.
#
# Input actions: none.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/level.tscn","actions":[
#     {"type":"add_node","parent_node_path":"root","node_type":"Node","node_name":"BulletPool"},
#     {"type":"attach_script","node_path":"root/BulletPool","script_path":"scripts/object_pool.gd",
#      "script_properties":{"scene":{"__resource":"res://scenes/bullet.tscn"},"initial_size":32}}]}'
class_name ObjectPool
extends Node

@export var scene: PackedScene
@export var initial_size: int = 16
## When the pool runs dry: true instantiates one more, false returns null.
@export var grow: bool = true

var _free: Array[Node] = []
var _in_use: Array[Node] = []


func _ready() -> void:
	prewarm(initial_size)


func prewarm(count: int) -> void:
	if scene == null:
		push_error("ObjectPool '%s': set `scene` to a PackedScene before prewarming." % name)
		return
	for _i in count:
		var node: Node = scene.instantiate()
		node.set_process(false)
		node.set_physics_process(false)
		_free.append(node)


## Take a node out of the pool. The caller adds it to the tree and positions it.
## Returns null only when the pool is empty and `grow` is false.
func acquire() -> Node:
	if _free.is_empty():
		if not grow:
			return null
		prewarm(1)
	if _free.is_empty():
		return null
	var node: Node = _free.pop_back()
	_in_use.append(node)
	node.set_process(true)
	node.set_physics_process(true)
	return node


## Give a node back. Never call queue_free() on a pooled node — that is the one
## mistake that turns a pool into a source of freed-instance errors.
func release(node: Node) -> void:
	var index: int = _in_use.find(node)
	if index == -1:
		return
	_in_use.remove_at(index)
	node.set_process(false)
	node.set_physics_process(false)
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	_free.append(node)


func free_count() -> int:
	return _free.size()


func in_use_count() -> int:
	return _in_use.size()


func _exit_tree() -> void:
	# Free nodes are not in the tree, so nothing else would ever release them.
	for node in _free:
		if node.get_parent() == null:
			node.queue_free()
	_free.clear()
