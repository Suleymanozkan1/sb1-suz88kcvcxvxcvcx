extends SceneTree
## Prints the triangle count of every code-built mesh, the figures quoted in the
## mobile_cost column of game/data/art/asset_gate.json. Read-only: it builds the
## meshes in memory and changes nothing.
##
## Usage (from the repository root, after an import of the project):
##   godot --headless --path game -s ../tools/report/mesh_budget.gd


func _initialize() -> void:
	_row("MeshFactory.chamfered_box(1, 1, 1)", MeshFactory.chamfered_box(Vector3.ONE))
	_row("MeshFactory.shard(0.11, 0.3)", MeshFactory.shard(0.11, 0.3))
	for profile: String in WorldTheme.RIB_PROFILES:
		_row('MeshFactory.rib("%s")' % profile, MeshFactory.rib(profile))
	for kind: String in ["turbine", "ridge", "glacier", "chimneys", "towers", "pylons", "dome", "canopy", "reactor", "ring"]:
		_row('MeshFactory.silhouette("%s")' % kind, MeshFactory.silhouette(kind))
	var kit: ViewKit = ViewKit.new(WorldTheme.new())
	_row("ViewKit.block_mesh", kit.block_mesh)
	_row("ViewKit.glass_mesh", kit.glass_mesh)
	_row("ViewKit.portal_ring_mesh", kit.portal_ring_mesh)
	_row("ViewKit.shield_mesh", kit.shield_mesh)
	_row("ViewKit.magnet_mesh", kit.magnet_mesh)
	_row("ViewKit.plate_ring_mesh", kit.plate_ring_mesh)
	_row("ViewKit.arch_mesh(3)", kit.arch_mesh(3))
	_row("ViewKit.phase_marker_mesh(0)", kit.phase_marker_mesh(0))
	for form: int in 4:
		_row("ViewKit.form_icon_mesh(%d)" % form, kit.form_icon_mesh(form))
	var core: CoreView = CoreView.new()
	core._ensure_built()
	for form2: int in 4:
		_row("CoreView form %d" % form2, core._meshes[form2] as Mesh)
	_row("CoreView.ring (surge)", core.ring.mesh)
	_row("CoreView.shield_ring", core.shield_ring.mesh)
	_row("CoreView.stack_discs[0]", core.stack_discs[0].mesh)
	core.free()
	quit()


func _row(label: String, mesh: Mesh) -> void:
	print("%-40s %6d triangles" % [label, _triangles(mesh)])


static func _triangles(mesh: Mesh) -> int:
	var total: int = 0
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		if index != null and (index as PackedInt32Array).size() > 0:
			total += (index as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total
