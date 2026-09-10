extends Node2D

const BUILD: String = "0.3.0-stable-pressure"
const BOARD_RECT := Rect2(24, 44, 936, 652)
const PANEL_RECT := Rect2(980, 0, 300, 720)

const BASE_CONTROL_LIMIT: int = 5
const FAIL_QUEUE: int = 9
const FAIL_SECONDS: float = 6.0
const BASE_SPAWN_INTERVAL: float = 0.78
const MIN_SPAWN_INTERVAL: float = 0.30
const STAGE_INTERVAL_DROP: float = 0.065
const AGENT_SPEED: float = 105.0

const FULL_EDGE_COST_MULTIPLIER: float = 7.0
const QUEUE_COST_PER_AGENT: float = 36.0
const U_TURN_COST: float = 5000.0
const RECENT_NODE_COST: float = 950.0
const ONE_WAY_CAPACITY_BONUS: int = 1

const MAX_BYPASS_LENGTH: float = 330.0
const MAX_BYPASS_COUNT: int = 1
const BYPASS_CAPACITY: int = 1

const STAGE_SCORES := [30, 70, 120, 180, 250]
const CLEAR_SCORE: int = 330

var font: Font
var rng := RandomNumberGenerator.new()

var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var source_nodes: Array[int] = []
var sink_nodes: Array[int] = []
var agents: Array[Dictionary] = []
var overload_time: Array[float] = []
var base_inflight_limits: Array[int] = []

var running: bool = false
var paused: bool = false
var game_over: bool = false
var map_cleared: bool = false
var elapsed: float = 0.0
var score: int = 0
var spawn_sequence: int = 0
var spawn_accumulator: float = 0.0
var status_text: String = "Press START. Click roads to change their flow rule."

var hovered_edge: int = -1
var hovered_node: int = -1
var control_limit: int = BASE_CONTROL_LIMIT
var stage: int = 0

var upgrade_pending: bool = false
var upgrade_action: String = ""
var bypass_first_node: int = -1
var bypass_count: int = 0

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
	if running and not paused and not game_over and not map_cleared:
		elapsed += delta
		spawn_accumulator += delta
		var interval: float = _spawn_interval()
		while spawn_accumulator >= interval:
			spawn_accumulator -= interval
			_try_spawn_agent()
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
	base_inflight_limits.clear()

	var left: float = BOARD_RECT.position.x + 88.0
	var right: float = BOARD_RECT.end.x - 88.0
	var top: float = BOARD_RECT.position.y + 96.0
	var bottom: float = BOARD_RECT.end.y - 92.0
	var column_gap: float = (right - left) / 3.0
	var row_gap: float = (bottom - top) / 2.0

	for row in range(3):
		for col in range(4):
			var jitter: Vector2 = Vector2.ZERO
			if col > 0 and col < 3:
				jitter = Vector2(
					rng.randf_range(-34.0, 34.0),
					rng.randf_range(-40.0, 40.0)
				)
			var pos: Vector2 = Vector2(
				left + column_gap * float(col),
				top + row_gap * float(row)
			) + jitter
			nodes.append({"pos": pos})
			overload_time.append(0.0)

	# Main corridors are deliberately constrained. Player controls can turn a
	# bidirectional road into a higher-throughput one-way corridor.
	for row in range(3):
		var base: int = row * 4
		_add_edge(base, base + 1, 2)
		_add_edge(base + 1, base + 2, 2)
		_add_edge(base + 2, base + 3, 2)

	# Cross-corridors are natural conflict points.
	_add_edge(1, 5, 1)
	_add_edge(5, 9, 1)
	_add_edge(2, 6, 1)
	_add_edge(6, 10, 1)

	var shortcut_pool: Array = [
		[0, 5], [4, 1], [4, 9], [8, 5],
		[3, 6], [7, 2], [7, 10], [11, 6],
		[1, 6], [5, 10]
	]
	shortcut_pool.shuffle()
	for i in range(2):
		_add_edge(int(shortcut_pool[i][0]), int(shortcut_pool[i][1]), 1)

	source_nodes = [0, 4, 8]
	var right_nodes: Array[int] = [3, 7, 11]
	right_nodes.shuffle()
	if right_nodes == [3, 7, 11]:
		right_nodes = [7, 11, 3]
	sink_nodes = right_nodes

	# Every flow must retain an alternate route when one edge on its shortest
	# structural path disappears. Bad random boards are repaired before play.
	for i in range(2, shortcut_pool.size()):
		if _all_pairs_resilient():
			break
		_add_edge(int(shortcut_pool[i][0]), int(shortcut_pool[i][1]), 1)

	_calculate_base_inflight_limits()
	_reset_run_state(false, false)
	status_text = "Press START. Reach %d to clear this map." % CLEAR_SCORE
	print("[FLOW_CONTROL] MAP sinks=%s edges=%d resilient=%s limits=%s" % [
		str(sink_nodes), edges.size(), str(_all_pairs_resilient()),
		str(base_inflight_limits)
	])
	queue_redraw()


func _add_edge(a: int, b: int, capacity: int, is_bypass: bool = false) -> void:
	if a == b or _edge_between(a, b) >= 0:
		return
	var a_pos: Vector2 = nodes[a]["pos"]
	var b_pos: Vector2 = nodes[b]["pos"]
	edges.append({
		"a": a,
		"b": b,
		"mode": 0,
		"capacity": capacity,
		"base_capacity": capacity,
		"load": 0,
		"length": a_pos.distance_to(b_pos),
		"is_bypass": is_bypass
	})


func _edge_between(a: int, b: int) -> int:
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		if (int(edge["a"]) == a and int(edge["b"]) == b) or (int(edge["a"]) == b and int(edge["b"]) == a):
			return i
	return -1


func _effective_capacity(edge_id: int) -> int:
	var edge: Dictionary = edges[edge_id]
	var capacity: int = int(edge["capacity"])
	var mode: int = int(edge["mode"])
	if mode == 1 or mode == 2:
		capacity += ONE_WAY_CAPACITY_BONUS
	if mode == 3:
		return 0
	return capacity


func _restore_infrastructure() -> void:
	for i in range(edges.size() - 1, -1, -1):
		if bool(edges[i].get("is_bypass", false)):
			edges.remove_at(i)
		else:
			edges[i]["capacity"] = int(edges[i]["base_capacity"])
			edges[i]["load"] = 0
	control_limit = BASE_CONTROL_LIMIT
	bypass_count = 0


func _reset_run_state(
	reset_edge_modes: bool = true,
	reset_infrastructure: bool = true
) -> void:
	agents.clear()
	if reset_infrastructure:
		_restore_infrastructure()
	for i in range(edges.size()):
		edges[i]["load"] = 0
		if reset_edge_modes:
			edges[i]["mode"] = 0
	for i in range(overload_time.size()):
		overload_time[i] = 0.0

	running = false
	paused = false
	game_over = false
	map_cleared = false
	elapsed = 0.0
	score = 0
	spawn_sequence = 0
	spawn_accumulator = 0.0
	stage = 0
	upgrade_pending = false
	upgrade_action = ""
	bypass_first_node = -1


func _spawn_interval() -> float:
	var stage_pressure: float = float(stage) * STAGE_INTERVAL_DROP
	var time_pressure: float = minf(0.12, elapsed * 0.0007)
	return maxf(
		MIN_SPAWN_INTERVAL,
		BASE_SPAWN_INTERVAL - stage_pressure - time_pressure
	)


func _inflight_limit(color_index: int) -> int:
	if color_index < 0 or color_index >= base_inflight_limits.size():
		return 0
	return clampi(base_inflight_limits[color_index] + stage * 2, 8, 22)


func _try_spawn_agent() -> void:
	var color_index: int = spawn_sequence % 3
	spawn_sequence += 1
	if _inflight_for_color(color_index) >= _inflight_limit(color_index):
		return

	var source: int = source_nodes[color_index]
	var target: int = sink_nodes[color_index]
	agents.append({
		"node": source,
		"target": target,
		"color": color_index,
		"edge": -1,
		"to": -1,
		"progress": 0.0,
		"recent_nodes": [source]
	})


func _inflight_for_color(color_index: int) -> int:
	var count: int = 0
	for agent in agents:
		if int(agent["color"]) == color_index:
			count += 1
	return count


func _update_agents(delta: float) -> void:
	for i in range(agents.size() - 1, -1, -1):
		var agent: Dictionary = agents[i]
		var edge_id: int = int(agent["edge"])

		if edge_id >= 0:
			var edge: Dictionary = edges[edge_id]
			var length: float = maxf(1.0, float(edge["length"]))
			agent["progress"] = float(agent["progress"]) + (AGENT_SPEED / length) * delta
			if float(agent["progress"]) >= 1.0:
				edges[edge_id]["load"] = maxi(0, int(edges[edge_id]["load"]) - 1)
				var arrived_node: int = int(agent["to"])
				agent["node"] = arrived_node
				agent["edge"] = -1
				agent["to"] = -1
				agent["progress"] = 0.0
				_remember_node(agent, arrived_node)

				if arrived_node == int(agent["target"]):
					score += 1
					agents.remove_at(i)
					_check_progression()
					continue
		else:
			var current: int = int(agent["node"])
			var target: int = int(agent["target"])
			var recent: Array = agent.get("recent_nodes", [])
			var next: int = _next_hop(current, target, recent)
			if next >= 0:
				var candidate_edge: int = _edge_between(current, next)
				if candidate_edge >= 0:
					var capacity: int = _effective_capacity(candidate_edge)
					if capacity > 0 and int(edges[candidate_edge]["load"]) < capacity:
						edges[candidate_edge]["load"] = int(edges[candidate_edge]["load"]) + 1
						agent["edge"] = candidate_edge
						agent["to"] = next
						agent["progress"] = 0.0

		agents[i] = agent


func _remember_node(agent: Dictionary, node_id: int) -> void:
	var recent: Array = agent.get("recent_nodes", [])
	recent.append(node_id)
	while recent.size() > 4:
		recent.pop_front()
	agent["recent_nodes"] = recent


func _next_hop(start: int, target: int, recent_nodes: Array) -> int:
	if start == target:
		return target

	var count: int = nodes.size()
	var dist: Array[float] = []
	var prev: Array[int] = []
	var used: Array[bool] = []
	var waiting: Array[int] = _waiting_counts()
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

			var capacity: int = maxi(1, _effective_capacity(edge_id))
			var load: int = int(edges[edge_id]["load"])
			var load_ratio: float = float(load) / float(capacity)
			var congestion_multiplier: float = 1.0 + load_ratio * load_ratio * 2.6
			if load >= capacity:
				congestion_multiplier *= FULL_EDGE_COST_MULTIPLIER

			var queue_penalty: float = float(waiting[neighbor]) * QUEUE_COST_PER_AGENT
			var memory_penalty: float = _recent_node_penalty(neighbor, target, recent_nodes)
			var candidate: float = dist[current] + float(edges[edge_id]["length"]) * congestion_multiplier + queue_penalty + memory_penalty
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


func _recent_node_penalty(neighbor: int, target: int, recent_nodes: Array) -> float:
	if neighbor == target or recent_nodes.is_empty():
		return 0.0
	var size: int = recent_nodes.size()
	if size >= 2 and neighbor == int(recent_nodes[size - 2]):
		return U_TURN_COST
	if recent_nodes.has(neighbor):
		return RECENT_NODE_COST
	return 0.0


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
			paused = false
			upgrade_pending = false
			upgrade_action = ""
			status_text = "FLOW COLLAPSED — a queue stayed blocked too long."
			print("[FLOW_CONTROL] GAME_OVER score=%d stage=%d time=%.1f node=%d" % [
				score, stage, elapsed, i
			])
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


func _shortest_path_edges(start: int, target: int, blocked_edge: int = -1) -> Array[int]:
	var frontier: Array[int] = [start]
	var visited: Dictionary = {start: true}
	var prev_node: Array[int] = []
	var prev_edge: Array[int] = []
	for _i in range(nodes.size()):
		prev_node.append(-1)
		prev_edge.append(-1)

	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		if current == target:
			break
		for edge_id in range(edges.size()):
			if edge_id == blocked_edge:
				continue
			var other: int = _other_node(edge_id, current)
			if other < 0 or visited.has(other):
				continue
			visited[other] = true
			prev_node[other] = current
			prev_edge[other] = edge_id
			frontier.append(other)

	if start != target and prev_node[target] < 0:
		return []

	var result: Array[int] = []
	var cursor: int = target
	while cursor != start:
		var edge_id: int = prev_edge[cursor]
		if edge_id < 0:
			return []
		result.push_front(edge_id)
		cursor = prev_node[cursor]
	return result


func _other_node(edge_id: int, node_id: int) -> int:
	var edge: Dictionary = edges[edge_id]
	var a: int = int(edge["a"])
	var b: int = int(edge["b"])
	if node_id == a:
		return b
	if node_id == b:
		return a
	return -1


func _pair_resilient(start: int, target: int) -> bool:
	var first_path: Array[int] = _shortest_path_edges(start, target)
	if first_path.is_empty():
		return false
	for edge_id in first_path:
		if _shortest_path_edges(start, target, edge_id).is_empty():
			return false
	return true


func _all_pairs_resilient() -> bool:
	if source_nodes.size() < 3 or sink_nodes.size() < 3:
		return false
	for i in range(3):
		if not _pair_resilient(source_nodes[i], sink_nodes[i]):
			return false
	return true


func _calculate_base_inflight_limits() -> void:
	base_inflight_limits.clear()
	for color_index in range(3):
		var path: Array[int] = _shortest_path_edges(
			source_nodes[color_index], sink_nodes[color_index]
		)
		var path_slots: int = 0
		for edge_id in path:
			path_slots += int(edges[edge_id]["base_capacity"])
		base_inflight_limits.append(clampi(path_slots + 3, 8, 12))


func _check_progression() -> void:
	if map_cleared or game_over or upgrade_pending:
		return

	if score >= CLEAR_SCORE:
		map_cleared = true
		running = false
		paused = false
		status_text = "MAP STABILIZED — press NEXT MAP."
		print("[FLOW_CONTROL] MAP_CLEAR score=%d time=%.1f" % [score, elapsed])
		return

	if stage < STAGE_SCORES.size() and score >= int(STAGE_SCORES[stage]):
		upgrade_pending = true
		upgrade_action = ""
		bypass_first_node = -1
		paused = true
		status_text = "TRAFFIC SHIFT — choose one upgrade before the next pattern."
		print("[FLOW_CONTROL] STAGE_READY stage=%d score=%d" % [stage + 1, score])


func _choose_upgrade(kind: String) -> void:
	if not upgrade_pending:
		return

	if kind == "control":
		control_limit += 1
		_finish_upgrade("Control limit increased to %d." % control_limit)
		return

	if kind == "bypass" and bypass_count >= MAX_BYPASS_COUNT:
		status_text = "Only one bypass can be built on this map. Choose WIDEN or +CTRL."
		return

	upgrade_action = kind
	bypass_first_node = -1
	if kind == "widen":
		status_text = "WIDEN — click one road to add +1 capacity."
	elif kind == "bypass":
		status_text = "BYPASS — click two nearby junctions. One bypass per map."


func _apply_widen(edge_id: int) -> void:
	if edge_id < 0 or edge_id >= edges.size():
		status_text = "WIDEN — click a road."
		return
	edges[edge_id]["capacity"] = int(edges[edge_id]["capacity"]) + 1
	_finish_upgrade("Road widened. The next traffic pattern is starting.")


func _handle_bypass_click(node_id: int) -> void:
	if bypass_count >= MAX_BYPASS_COUNT:
		status_text = "Bypass already used on this map."
		return
	if node_id < 0:
		status_text = "BYPASS — click a junction node, not a road."
		return
	if bypass_first_node < 0:
		bypass_first_node = node_id
		status_text = "BYPASS — now click the second junction."
		return
	if node_id == bypass_first_node:
		status_text = "Choose a different second junction."
		return
	if _edge_between(bypass_first_node, node_id) >= 0:
		status_text = "Those junctions are already connected."
		return

	var a: Vector2 = nodes[bypass_first_node]["pos"]
	var b: Vector2 = nodes[node_id]["pos"]
	if a.distance_to(b) > MAX_BYPASS_LENGTH:
		status_text = "Bypass too long. Choose a closer junction."
		return

	_add_edge(bypass_first_node, node_id, BYPASS_CAPACITY, true)
	bypass_count += 1
	_finish_upgrade("Bypass opened. The next traffic pattern is starting.")


func _finish_upgrade(message: String) -> void:
	upgrade_pending = false
	upgrade_action = ""
	bypass_first_node = -1
	stage += 1
	_shift_destinations()
	spawn_accumulator = 0.0
	paused = false
	status_text = "%s Destinations shifted; re-check the flow." % message
	print("[FLOW_CONTROL] STAGE_START stage=%d sinks=%s" % [
		stage, str(sink_nodes)
	])


func _shift_destinations() -> void:
	if sink_nodes.size() < 3:
		return
	var old: Array[int] = sink_nodes.duplicate()
	sink_nodes = [old[1], old[2], old[0]]

	for i in range(agents.size()):
		var color_index: int = int(agents[i]["color"])
		agents[i]["target"] = sink_nodes[color_index]
		var current: int = int(agents[i]["node"])
		agents[i]["recent_nodes"] = [current]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_toggle_start_pause()
			KEY_R:
				_reset_run_state(true, true)
				status_text = "Reset. Press START."
			KEY_N:
				_generate_map()
				status_text = "New procedural map generated."

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		hovered_edge = _find_edge_at(motion.position)
		hovered_node = _find_node_at(motion.position)
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
		_reset_run_state(true, true)
		status_text = "Reset. Roads and infrastructure restored."
		return
	if buttons[2].has_point(pos):
		_generate_map()
		status_text = "New procedural map generated."
		return

	if upgrade_pending:
		if buttons[3].has_point(pos):
			_choose_upgrade("widen")
			return
		if buttons[4].has_point(pos):
			_choose_upgrade("bypass")
			return
		if buttons[5].has_point(pos):
			_choose_upgrade("control")
			return

	if not BOARD_RECT.has_point(pos):
		return

	if upgrade_pending and upgrade_action == "widen":
		_apply_widen(_find_edge_at(pos))
		return
	if upgrade_pending and upgrade_action == "bypass":
		_handle_bypass_click(_find_node_at(pos))
		return
	if upgrade_pending:
		return

	var edge_id: int = _find_edge_at(pos)
	if edge_id >= 0:
		_cycle_edge_mode(edge_id)


func _toggle_start_pause() -> void:
	if upgrade_pending:
		status_text = "Choose and apply an infrastructure upgrade first."
		return
	if map_cleared:
		_generate_map()
		return
	if game_over:
		_reset_run_state(true, true)
		status_text = "Fresh run. Press START."
		return
	if not running:
		running = true
		paused = false
		status_text = "Running. One-way roads gain +1 capacity."
		print("[FLOW_CONTROL] RUN_START")
	else:
		paused = not paused
		status_text = "Paused. Adjust directions." if paused else "Running."


func _cycle_edge_mode(edge_id: int) -> void:
	var current: int = int(edges[edge_id]["mode"])
	var next: int = (current + 1) % 4
	if current == 0 and next != 0 and _controls_used() >= control_limit:
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


func _find_node_at(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = 18.0
	for i in range(nodes.size()):
		var node_pos: Vector2 = nodes[i]["pos"]
		var distance: float = pos.distance_to(node_pos)
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
		Rect2(1134, 180, 122, 38),
		Rect2(1004, 238, 78, 38),
		Rect2(1091, 238, 78, 38),
		Rect2(1178, 238, 78, 38)
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
		var capacity: int = maxi(1, _effective_capacity(i))
		var ratio: float = float(load) / float(capacity)
		var width: float = 5.0 + ratio * 5.0 + float(int(edge["capacity"]) - int(edge["base_capacity"])) * 1.2
		var color: Color = Color("#b7b29f") if bool(edge.get("is_bypass", false)) else Color("#c8c5be")
		if i == hovered_edge:
			color = Color("#8f8a80")
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
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = mid + dir * 8.0
	var base: Vector2 = mid - dir * 7.0
	var arrow := PackedVector2Array([
		base + normal * 5.0,
		tip,
		base - normal * 5.0
	])
	draw_polyline(arrow, Color("#34383a"), 2.4, true)


func _draw_nodes() -> void:
	var waiting: Array[int] = _waiting_counts()
	for i in range(nodes.size()):
		var pos: Vector2 = nodes[i]["pos"]
		var queue: int = waiting[i]
		if queue > 0:
			var halo: float = 18.0 + minf(18.0, float(queue) * 1.8)
			draw_circle(
				pos,
				halo,
				Color(0.78, 0.28, 0.25, 0.06 + minf(0.24, float(queue) * 0.02))
			)
		if overload_time[i] > 0.0:
			var danger_ratio: float = clampf(overload_time[i] / FAIL_SECONDS, 0.0, 1.0)
			draw_arc(
				pos, 23.0, -PI / 2.0,
				-PI / 2.0 + TAU * danger_ratio,
				28, Color("#c34f4f"), 4.0, true
			)
		if upgrade_pending and upgrade_action == "bypass" and (i == hovered_node or i == bypass_first_node):
			draw_circle(pos, 15.0, Color(0.36, 0.49, 0.68, 0.16))
			draw_arc(pos, 15.0, 0.0, TAU, 24, Color("#5d789e"), 2.5, true)

		draw_circle(pos, 7.0, Color("#565b5d"))
		if queue > 0:
			draw_string(
				font, pos + Vector2(-15, 29), str(queue),
				HORIZONTAL_ALIGNMENT_CENTER, 30, 11, Color("#a84545")
			)

	for color_index in range(3):
		var source: int = source_nodes[color_index]
		var sink: int = sink_nodes[color_index]
		var source_pos: Vector2 = nodes[source]["pos"]
		var sink_pos: Vector2 = nodes[sink]["pos"]
		draw_rect(
			Rect2(source_pos - Vector2(14, 14), Vector2(28, 28)),
			Color("#fbfaf6"), true
		)
		draw_rect(
			Rect2(source_pos - Vector2(14, 14), Vector2(28, 28)),
			flow_colors[color_index], false, 3.0
		)
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
			pos = from_pos.lerp(
				to_pos,
				clampf(float(agent["progress"]), 0.0, 1.0)
			)
		else:
			var node_id: int = int(agent["node"])
			var index: int = int(waiting_index.get(node_id, 0))
			waiting_index[node_id] = index + 1
			var angle: float = float(index) * 2.2
			var radius: float = 12.0 + float(int(index / 5)) * 6.0
			pos = nodes[node_id]["pos"] + Vector2(cos(angle), sin(angle)) * radius
		draw_circle(pos, 4.3, flow_colors[color_index])


func _draw_panel() -> void:
	draw_rect(PANEL_RECT, Color("#e9e6dd"), true)
	draw_line(Vector2(980, 0), Vector2(980, 720), Color("#c5c0b5"), 1.0)
	draw_string(font, Vector2(1004, 34), "FLOW CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#292e31"))
	draw_string(font, Vector2(1004, 58), "stable pressure  v0.3", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#666b6d"))

	var buttons: Array[Rect2] = _buttons()
	var start_color: Color = Color("#dfc0b8") if game_over else Color("#c7d9bf")
	_button(buttons[0], _start_label(), start_color)
	_button(buttons[1], "RESET", Color("#d8d4cb"))
	_button(buttons[2], "NEW MAP", Color("#d8d4cb"))

	if upgrade_pending:
		draw_string(font, Vector2(1004, 232), "TRAFFIC SHIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#5b6062"))
		_button(buttons[3], "WIDEN", Color("#cfd9c8") if upgrade_action == "widen" else Color("#ddd8cf"))
		var bypass_label: String = "USED" if bypass_count >= MAX_BYPASS_COUNT else "BYPASS"
		_button(buttons[4], bypass_label, Color("#cbd6df") if upgrade_action == "bypass" else Color("#ddd8cf"))
		_button(buttons[5], "+CTRL", Color("#ddd8cf"))

	draw_string(font, Vector2(1004, 314), "Score", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#696d6f"))
	draw_string(font, Vector2(1004, 348), "%d / %d" % [score, CLEAR_SCORE], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#303538"))
	draw_string(font, Vector2(1004, 384), "Stage  %d / %d" % [stage + 1, STAGE_SCORES.size() + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#555a5c"))
	draw_string(font, Vector2(1004, 408), "Time  %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#555a5c"))
	draw_string(font, Vector2(1004, 432), "Controls  %d / %d" % [_controls_used(), control_limit], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#555a5c"))
	draw_string(font, Vector2(1004, 456), "Flow rate  %.1f / sec" % (1.0 / _spawn_interval()), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#555a5c"))

	draw_string(font, Vector2(1004, 496), "ROAD CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#363b3d"))
	draw_string(font, Vector2(1004, 520), "↔  →  ←  ×", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#363b3d"))
	draw_string(font, Vector2(1004, 548), "One-way roads get +1 capacity.", HORIZONTAL_ALIGNMENT_LEFT, 252, 11, Color("#656a6c"))
	draw_string(font, Vector2(1004, 566), "Agents avoid recent nodes to stop loops.", HORIZONTAL_ALIGNMENT_LEFT, 252, 11, Color("#656a6c"))

	draw_string(font, Vector2(1004, 604), status_text, HORIZONTAL_ALIGNMENT_LEFT, 252, 11, Color("#464b4d"))
	draw_string(font, Vector2(1004, 644), _next_stage_text(), HORIZONTAL_ALIGNMENT_LEFT, 252, 10, Color("#74787a"))
	draw_string(font, Vector2(1004, 674), "Space: start/pause   R: reset   N: new", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#777b7d"))


func _next_stage_text() -> String:
	if map_cleared:
		return "Map cleared. Start a fresh procedural board."
	if upgrade_pending:
		return "Choose an upgrade; then destinations rotate."
	if stage < STAGE_SCORES.size():
		return "Next traffic shift at %d score" % int(STAGE_SCORES[stage])
	return "Final pattern — stabilize to %d" % CLEAR_SCORE


func _start_label() -> String:
	if upgrade_pending:
		return "UPGRADE"
	if map_cleared:
		return "NEXT MAP"
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
	draw_string(
		font, rect.position + Vector2(6, 27), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12.0, 12,
		Color("#303437")
	)


func _mode_label(mode: int) -> String:
	match mode:
		0:
			return "BOTH ↔"
		1:
			return "A → B (+capacity)"
		2:
			return "B → A (+capacity)"
		3:
			return "CLOSED ×"
		_:
			return "?"
