extends Node2D

const BUILD: String = "0.1.0-flow-control"
const BOARD_RECT := Rect2(24, 44, 936, 652)
const PANEL_RECT := Rect2(980, 0, 300, 720)
const MAX_CONTROLS: int = 5
const FAIL_QUEUE: int = 8
const FAIL_SECONDS: float = 5.0
const BASE_SPAWN_INTERVAL: float = 0.82
const MIN_SPAWN_INTERVAL: float = 0.26

var font: Font
var rng := RandomNumberGenerator.new()

var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var source_nodes: Array[int] = []
var sink_nodes: Array[int] = []
var agents: Array[Dictionary] = []
var overload_time: Array[float] = []

var running: bool = false
var paused: bool = false
var game_over: bool = false
var elapsed: float = 0.0
var score: int = 0
var spawned: int = 0
var spawn_accumulator: float = 0.0
var status_text: String = "Press START. Click roads to change their flow rule."
var hovered_edge: int = -1

var flow_colors: Array[Color] = [
	Color("#e75d66"),
	Color("#4d83d1"),
	Color("#55a56a")
]


func _ready() -> void:
	font = ThemeDB.fallback_font
	rng.randomize()
	_generate_map()
	print("[FLOW_CONTROL] START build=%s godot=%s" % [
		BUILD, String(Engine.get_version_info().get("string", "unknown"))
	])
	queue_redraw()


func _process(delta: float) -> void:
	if running and not paused and not game_over:
		elapsed += delta
		spawn_accumulator += delta
		var interval: float = _spawn_interval()
		while spawn_accumulator >= interval:
			spawn_accumulator -= interval
			_spawn_agent()
			interval = _spawn_interval()
		_update_agents(delta)
		_update_overload(delta)
	queue_redraw()


func _generate_map() -> void:
	nodes.clear()
	edges.clear()
	source_nodes.clear()
	sink_nodes.clear()
	agents.clear()
	overload_time.clear()

	var left: float = BOARD_RECT.position.x + 88.0
	var right: float = BOARD_RECT.end.x - 88.0
	var top: float = BOARD_RECT.position.y + 96.0
	var bottom: float = BOARD_RECT.end.y - 92.0
	var column_gap: float = (right - left) / 3.0
	var row_gap: float = (bottom - top) / 2.0

	for row in range(3):
		for col in range(4):
			var jitter := Vector2.ZERO
			if col > 0 and col < 3:
				jitter = Vector2(rng.randf_range(-34.0, 34.0), rng.randf_range(-40.0, 40.0))
			var pos := Vector2(left + column_gap * float(col), top + row_gap * float(row)) + jitter
			nodes.append({"pos": pos})
			overload_time.append(0.0)

	# Three horizontal corridors.
	for row in range(3):
		var base: int = row * 4
		_add_edge(base, base + 1, 3)
		_add_edge(base + 1, base + 2, 3)
		_add_edge(base + 2, base + 3, 3)

	# Two central cross-corridors create recurring head-on conflicts.
	_add_edge(1, 5, 2)
	_add_edge(5, 9, 2)
	_add_edge(2, 6, 2)
	_add_edge(6, 10, 2)

	# Add two procedural shortcuts from a curated motif set.
	var shortcuts: Array[Array] = [
		[0, 5], [4, 1], [4, 9], [8, 5],
		[3, 6], [7, 2], [7, 10], [11, 6]
	]
	shortcuts.shuffle()
	for i in range(2):
		_add_edge(int(shortcuts[i][0]), int(shortcuts[i][1]), 2)

	source_nodes = [0, 4, 8]
	var right_nodes: Array[int] = [3, 7, 11]
	right_nodes.shuffle()
	if right_nodes == [3, 7, 11]:
		right_nodes = [7, 11, 3]
	sink_nodes = right_nodes

	_reset_run_state(false)
	status_text = "Press START. Each color must reach its matching destination."
	print("[FLOW_CONTROL] MAP sinks=%s edges=%d" % [str(sink_nodes), edges.size()])


func _add_edge(a: int, b: int, capacity: int) -> void:
	if _edge_between(a, b) >= 0:
		return
	var a_pos: Vector2 = nodes[a]["pos"]
	var b_pos: Vector2 = nodes[b]["pos"]
	edges.append({
		"a": a,
		"b": b,
		"mode": 0,
		"capacity": capacity,
		"load": 0,
		"length": a_pos.distance_to(b_pos)
	})


func _edge_between(a: int, b: int) -> int:
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		if (int(edge["a"]) == a and int(edge["b"]) == b) or (int(edge["a"]) == b and int(edge["b"]) == a):
			return i
	return -1


func _reset_run_state(reset_edge_modes: bool = true) -> void:
	agents.clear()
	for i in range(edges.size()):
		edges[i]["load"] = 0
		if reset_edge_modes:
			edges[i]["mode"] = 0
	for i in range(overload_time.size()):
		overload_time[i] = 0.0
	running = false
	paused = false
	game_over = false
	elapsed = 0.0
	score = 0
	spawned = 0
	spawn_accumulator = 0.0


func _spawn_interval() -> float:
	return maxf(MIN_SPAWN_INTERVAL, BASE_SPAWN_INTERVAL - elapsed * 0.0065)


func _spawn_agent() -> void:
	var color_index: int = spawned % 3
	spawned += 1
	var source: int = source_nodes[color_index]
	var target: int = sink_nodes[color_index]
	agents.append({
		"node": source,
		"target": target,
		"color": color_index,
		"edge": -1,
		"to": -1,
		"progress": 0.0
	})


func _update_agents(delta: float) -> void:
	for i in range(agents.size() - 1, -1, -1):
		var agent: Dictionary = agents[i]
		var edge_id: int = int(agent["edge"])
		if edge_id >= 0:
			var edge: Dictionary = edges[edge_id]
			var length: float = maxf(1.0, float(edge["length"]))
			var speed: float = 105.0
			agent["progress"] = float(agent["progress"]) + (speed / length) * delta
			if float(agent["progress"]) >= 1.0:
				edges[edge_id]["load"] = maxi(0, int(edges[edge_id]["load"]) - 1)
				agent["node"] = int(agent["to"])
				agent["edge"] = -1
				agent["to"] = -1
				agent["progress"] = 0.0
				if int(agent["node"]) == int(agent["target"]):
					score += 1
					agents.remove_at(i)
					continue
		else:
			var current: int = int(agent["node"])
			var target: int = int(agent["target"])
			var next: int = _next_hop(current, target)
			if next >= 0:
				var candidate_edge: int = _edge_between(current, next)
				if candidate_edge >= 0 and int(edges[candidate_edge]["load"]) < int(edges[candidate_edge]["capacity"]):
					edges[candidate_edge]["load"] = int(edges[candidate_edge]["load"]) + 1
					agent["edge"] = candidate_edge
					agent["to"] = next
					agent["progress"] = 0.0
		agents[i] = agent


func _next_hop(start: int, target: int) -> int:
	if start == target:
		return target
	var count: int = nodes.size()
	var dist: Array[float] = []
	var prev: Array[int] = []
	var used: Array[bool] = []
	for _i in range(count):
		dist.append(INF)
		prev.append(-1)
		used.append(false)
	dist[start] = 0.0

	for _step in range(count):
		var current: int = -1
		var best: float = INF
		for i in range(count):
			if not used[i] and dist[i] < best:
				best = dist[i]
				current = i
		if current < 0:
			break
		if current == target:
			break
		used[current] = true

		for edge_id in range(edges.size()):
			var neighbor: int = _neighbor_allowed(edge_id, current)
			if neighbor < 0:
				continue
			var edge: Dictionary = edges[edge_id]
			var load_ratio: float = float(edge["load"]) / float(maxi(1, int(edge["capacity"])))
			var cost: float = float(edge["length"]) * (1.0 + load_ratio * 1.7)
			var candidate: float = dist[current] + cost
			if candidate < dist[neighbor]:
				dist[neighbor] = candidate
				prev[neighbor] = current

	if prev[target] < 0:
		return -1
	var cursor: int = target
	while prev[cursor] >= 0 and prev[cursor] != start:
		cursor = prev[cursor]
	if prev[cursor] == start:
		return cursor
	return -1


func _neighbor_allowed(edge_id: int, from_node: int) -> int:
	var edge: Dictionary = edges[edge_id]
	var a: int = int(edge["a"])
	var b: int = int(edge["b"])
	var mode: int = int(edge["mode"])
	if mode == 3:
		return -1
	if mode == 0:
		if from_node == a:
			return b
		if from_node == b:
			return a
		return -1
	if mode == 1 and from_node == a:
		return b
	if mode == 2 and from_node == b:
		return a
	return -1


func _update_overload(delta: float) -> void:
	var waiting: Array[int] = _waiting_counts()
	for i in range(waiting.size()):
		if waiting[i] >= FAIL_QUEUE:
			overload_time[i] += delta
		else:
			overload_time[i] = maxf(0.0, overload_time[i] - delta * 1.6)
		if overload_time[i] >= FAIL_SECONDS:
			game_over = true
			running = false
			status_text = "FLOW COLLAPSED — press TRY AGAIN or generate a new map."
			print("[FLOW_CONTROL] GAME_OVER score=%d time=%.1f node=%d" % [score, elapsed, i])
			return


func _waiting_counts() -> Array[int]:
	var result: Array[int] = []
	for _i in range(nodes.size()):
		result.append(0)
	for agent in agents:
		if int(agent["edge"]) < 0 and int(agent["node"]) != int(agent["target"]):
			var node_id: int = int(agent["node"])
			result[node_id] += 1
	return result


func _controls_used() -> int:
	var count: int = 0
	for edge in edges:
		if int(edge["mode"]) != 0:
			count += 1
	return count


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_toggle_start_pause()
			KEY_R:
				_reset_run_state(true)
				status_text = "Reset. Press START."
			KEY_N:
				_generate_map()
				status_text = "New procedural map generated."

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		hovered_edge = _find_edge_at(motion.position)
		queue_redraw()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse: InputEventMouseButton = event
		_handle_click(mouse.position)


func _handle_click(pos: Vector2) -> void:
	var buttons: Array[Rect2] = _buttons()
	if buttons[0].has_point(pos):
		_toggle_start_pause()
		return
	if buttons[1].has_point(pos):
		_reset_run_state(true)
		status_text = "Reset. All roads are bidirectional again."
		return
	if buttons[2].has_point(pos):
		_generate_map()
		status_text = "New procedural map generated."
		return

	if not BOARD_RECT.has_point(pos):
		return
	var edge_id: int = _find_edge_at(pos)
	if edge_id >= 0:
		_cycle_edge_mode(edge_id)


func _toggle_start_pause() -> void:
	if game_over:
		_reset_run_state(false)
		status_text = "Fresh run. Controls preserved."
		return
	if not running:
		running = true
		paused = false
		status_text = "Running. Redirect flow before queues overload."
		print("[FLOW_CONTROL] RUN_START")
	else:
		paused = not paused
		status_text = "Paused. Adjust directions." if paused else "Running."


func _cycle_edge_mode(edge_id: int) -> void:
	var current: int = int(edges[edge_id]["mode"])
	var next: int = (current + 1) % 4
	if current == 0 and next != 0 and _controls_used() >= MAX_CONTROLS:
		status_text = "No control tokens left. Return another road to ↔ first."
		return
	edges[edge_id]["mode"] = next
	status_text = "Road rule: %s" % _mode_label(next)
	print("[FLOW_CONTROL] EDGE id=%d mode=%s" % [edge_id, _mode_label(next)])
	queue_redraw()


func _find_edge_at(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = 14.0
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		var a: Vector2 = nodes[int(edge["a"])]["pos"]
		var b: Vector2 = nodes[int(edge["b"])]["pos"]
		var distance: float = _distance_to_segment(pos, a, b)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq <= 0.001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _buttons() -> Array[Rect2]:
	return [
		Rect2(1004, 118, 252, 46),
		Rect2(1004, 180, 122, 38),
		Rect2(1134, 180, 122, 38)
	]


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#f2f0e9"), true)
	draw_rect(BOARD_RECT, Color("#fbfaf6"), true)
	_draw_edges()
	_draw_nodes()
	_draw_agents()
	draw_rect(BOARD_RECT, Color("#b9b5ac"), false, 1.0)
	_draw_panel()


func _draw_edges() -> void:
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		var a: Vector2 = nodes[int(edge["a"])]["pos"]
		var b: Vector2 = nodes[int(edge["b"])]["pos"]
		var load: int = int(edge["load"])
		var capacity: int = int(edge["capacity"])
		var ratio: float = float(load) / float(maxi(1, capacity))
		var width: float = 5.0 + ratio * 5.0
		var color := Color("#c8c5be")
		if i == hovered_edge:
			color = Color("#9e9a91")
		draw_line(a, b, color, width, true)
		draw_line(a, b, Color("#f8f7f2"), maxf(2.0, width - 3.0), true)
		_draw_edge_rule(i, a, b)


func _draw_edge_rule(edge_id: int, a: Vector2, b: Vector2) -> void:
	var mode: int = int(edges[edge_id]["mode"])
	if mode == 0:
		return
	var mid: Vector2 = (a + b) * 0.5
	if mode == 3:
		draw_circle(mid, 10.0, Color("#f8f7f2"))
		draw_line(mid + Vector2(-6, -6), mid + Vector2(6, 6), Color("#44484a"), 2.5, true)
		draw_line(mid + Vector2(-6, 6), mid + Vector2(6, -6), Color("#44484a"), 2.5, true)
		return
	var start: Vector2 = a if mode == 1 else b
	var finish: Vector2 = b if mode == 1 else a
	var dir: Vector2 = (finish - start).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var tip: Vector2 = mid + dir * 8.0
	var base: Vector2 = mid - dir * 7.0
	var arrow := PackedVector2Array([base + normal * 5.0, tip, base - normal * 5.0])
	draw_polyline(arrow, Color("#34383a"), 2.4, true)


func _draw_nodes() -> void:
	var waiting: Array[int] = _waiting_counts()
	for i in range(nodes.size()):
		var pos: Vector2 = nodes[i]["pos"]
		var queue: int = waiting[i]
		if queue > 0:
			var halo: float = 18.0 + minf(18.0, float(queue) * 1.8)
			draw_circle(pos, halo, Color(0.78, 0.28, 0.25, 0.06 + minf(0.24, float(queue) * 0.02)))
		if overload_time[i] > 0.0:
			var ratio: float = clampf(overload_time[i] / FAIL_SECONDS, 0.0, 1.0)
			draw_arc(pos, 23.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 28, Color("#c34f4f"), 4.0, true)

		draw_circle(pos, 7.0, Color("#565b5d"))
		if queue > 0:
			draw_string(font, pos + Vector2(-15, 29), str(queue), HORIZONTAL_ALIGNMENT_CENTER, 30, 11, Color("#a84545"))

	for color_index in range(3):
		var source: int = source_nodes[color_index]
		var sink: int = sink_nodes[color_index]
		var source_pos: Vector2 = nodes[source]["pos"]
		var sink_pos: Vector2 = nodes[sink]["pos"]
		draw_rect(Rect2(source_pos - Vector2(14, 14), Vector2(28, 28)), Color("#fbfaf6"), true)
		draw_rect(Rect2(source_pos - Vector2(14, 14), Vector2(28, 28)), flow_colors[color_index], false, 3.0)
		draw_circle(sink_pos, 16.0, Color("#fbfaf6"))
		draw_arc(sink_pos, 16.0, 0.0, TAU, 28, flow_colors[color_index], 4.0, true)
		draw_string(font, source_pos + Vector2(-18, -22), "IN", HORIZONTAL_ALIGNMENT_CENTER, 36, 10, flow_colors[color_index])
		draw_string(font, sink_pos + Vector2(-22, -24), "OUT", HORIZONTAL_ALIGNMENT_CENTER, 44, 10, flow_colors[color_index])


func _draw_agents() -> void:
	var waiting_index: Dictionary = {}
	for agent in agents:
		var color_index: int = int(agent["color"])
		var pos: Vector2
		var edge_id: int = int(agent["edge"])
		if edge_id >= 0:
			var from_pos: Vector2 = nodes[int(agent["node"])]["pos"]
			var to_pos: Vector2 = nodes[int(agent["to"])]["pos"]
			pos = from_pos.lerp(to_pos, clampf(float(agent["progress"]), 0.0, 1.0))
		else:
			var node_id: int = int(agent["node"])
			var index: int = int(waiting_index.get(node_id, 0))
			waiting_index[node_id] = index + 1
			var angle: float = float(index) * 2.2
			var radius: float = 12.0 + float(index / 5) * 6.0
			pos = nodes[node_id]["pos"] + Vector2(cos(angle), sin(angle)) * radius
		draw_circle(pos, 4.3, flow_colors[color_index])


func _draw_panel() -> void:
	draw_rect(PANEL_RECT, Color("#e9e6dd"), true)
	draw_line(Vector2(980, 0), Vector2(980, 720), Color("#c5c0b5"), 1.0)
	draw_string(font, Vector2(1004, 34), "FLOW CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#292e31"))
	draw_string(font, Vector2(1004, 58), "procedural prototype  v0.1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#666b6d"))

	var buttons: Array[Rect2] = _buttons()
	_button(buttons[0], _start_label(), Color("#c7d9bf") if not game_over else Color("#dfc0b8"))
	_button(buttons[1], "RESET", Color("#d8d4cb"))
	_button(buttons[2], "NEW MAP", Color("#d8d4cb"))

	draw_string(font, Vector2(1004, 260), "Score", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#696d6f"))
	draw_string(font, Vector2(1004, 294), str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#303538"))
	draw_string(font, Vector2(1004, 330), "Time  %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#555a5c"))
	draw_string(font, Vector2(1004, 354), "Controls  %d / %d" % [_controls_used(), MAX_CONTROLS], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#555a5c"))
	draw_string(font, Vector2(1004, 378), "Flow rate  %.1f / sec" % (1.0 / _spawn_interval()), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#555a5c"))

	draw_string(font, Vector2(1004, 430), "CLICK A ROAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#363b3d"))
	draw_string(font, Vector2(1004, 454), "↔  →  ←  ×", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#363b3d"))
	draw_string(font, Vector2(1004, 480), "Cycle its flow rule.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#656a6c"))
	draw_string(font, Vector2(1004, 502), "Directional roads stop head-on", HORIZONTAL_ALIGNMENT_LEFT, 252, 11, Color("#656a6c"))
	draw_string(font, Vector2(1004, 520), "traffic but may create detours.", HORIZONTAL_ALIGNMENT_LEFT, 252, 11, Color("#656a6c"))

	draw_string(font, Vector2(1004, 568), status_text, HORIZONTAL_ALIGNMENT_LEFT, 252, 12, Color("#464b4d"))
	draw_string(font, Vector2(1004, 650), "Space: start/pause", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#777b7d"))
	draw_string(font, Vector2(1004, 670), "R: reset   N: new map", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#777b7d"))


func _start_label() -> String:
	if game_over:
		return "TRY AGAIN"
	if not running:
		return "START"
	if paused:
		return "RESUME"
	return "PAUSE"


func _button(rect: Rect2, label: String, fill: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color("#77736b"), false, 1.0)
	draw_string(font, rect.position + Vector2(8, 28), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16.0, 13, Color("#303437"))


func _mode_label(mode: int) -> String:
	match mode:
		0:
			return "BOTH ↔"
		1:
			return "A → B"
		2:
			return "B → A"
		3:
			return "CLOSED ×"
		_:
			return "?"
