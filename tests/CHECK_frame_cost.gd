extends SceneTree

# WHAT A FRAME COSTS: triangles and draw calls at the place the game starts,
# looking each way round, on whatever renderer this is run with.
#
#   godot --path . --script res://tests/CHECK_frame_cost.gd
#
# (Needs a real renderer: headless draws nothing and counts nothing.)

var _scene: Node
var _step := -1
var _wait := 0
var _rows: Array = []
var _all: Array = []
var _base: Array = []


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.0
			enviro.set_weather("clear", 0.0)
			_step = 0
			_wait = 30
		return false
	_wait -= 1
	if _wait > 0:
		return false
	if _step > 0:
		_rows.append([Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if _step == 4:
		var tris := 0.0
		var draws := 0.0
		var objects := 0.0
		for r in _rows:
			tris += float(r[0]) / _rows.size()
			draws += float(r[1]) / _rows.size()
			objects += float(r[2]) / _rows.size()
		print("frame cost: %d thousand triangles, %d draw calls, %d objects (mean of four directions)" % [
				int(tris / 1000.0), int(draws), int(objects)])
		for i in _rows.size():
			print("frame cost:   facing %d deg: %d k triangles, %d draws" % [i * 90, int(float(_rows[i][0]) / 1000.0), int(_rows[i][1])])
		_all = [tris, draws]
		_step = 100
		_wait = 1
		return false
	if _step >= 100:
		# WHERE IT GOES: each kind of plant hidden in turn, facing the first way.
		var flora := _scene.get_node("Flora")
		var names: Array = []
		for c in flora.get_children():
			names.append(c.name)
		var at := (_step - 100) / 2
		if (_step - 100) % 2 == 1:
			var now := [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
			if at == 0:
				_base = now
			else:
				var gone: String = names[at - 1]
				print("frame cost:   %-9s %5d k triangles, %4d draws" % [gone.to_lower(), int((float(_base[0]) - float(now[0])) / 1000.0),
						int(float(_base[1]) - float(now[1]))])
				(flora.get_node(gone) as Node3D).visible = true
			if at >= names.size():
				quit(0)
				return true
			(flora.get_node(String(names[at])) as Node3D).visible = false
		else:
			explorer.rotation.y = 0.0
		_step += 1
		_wait = 6
		return false
	explorer.rotation.y = float(_step) * PI * 0.5
	_step += 1
	_wait = 12
	return false
