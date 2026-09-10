extends Node2D

const BUILD := "0.4.0-rush-waves"
const BOARD := Rect2(24, 44, 936, 652)
const PANEL := Rect2(980, 0, 300, 720)
const FAIL_QUEUE := 9
const FAIL_SECONDS := 6.0
const AGENT_SPEED := 105.0
const BASE_INTERVAL := 0.78
const MIN_INTERVAL := 0.30
const CONTROL_BASE := 5
const ONE_WAY_BONUS := 1
const RUSH_FIRST := 20.0
const RUSH_WARNING := 5.0
const RUSH_DURATION := 11.0
const RUSH_GAP_MIN := 25.0
const RUSH_GAP_MAX := 34.0
const RUSH_BONUS := 5
const STAGE_SCORES := [45, 110, 190]
const CLEAR_SCORE := 280
const BYPASS_MAX := 1
const BYPASS_LENGTH := 330.0

var font: Font
var rng := RandomNumberGenerator.new()
var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var agents: Array[Dictionary] = []
var source_nodes: Array[int] = [0, 4, 8]
var sink_nodes: Array[int] = [7, 11, 3]
var overload: Array[float] = []
var base_limits: Array[int] = [10, 10, 10]

var running := false
var paused := false
var game_over := false
var cleared := false
var elapsed := 0.0
var score := 0
var stage := 0
var speed := 1
var spawn_acc := 0.0
var spawn_seq := 0
var control_limit := CONTROL_BASE
var hovered_edge := -1
var hovered_node := -1
var status := "Press START."

var upgrade_pending := false
var upgrade_action := ""
var bypass_first := -1
var bypass_count := 0

var rush_color := -1
var next_rush_color := 0
var rush_remaining := 0.0
var next_rush_at := RUSH_FIRST

var flow_colors: Array[Color] = [Color("#e75d66"), Color("#4d83d1"), Color("#55a56a")]

func _ready() -> void:
	font = ThemeDB.fallback_font
	rng.randomize()
	_generate_map()
	print("[FLOW_CONTROL] START %s" % BUILD)

func _process(delta: float) -> void:
	if running and not paused and not game_over and not cleared:
		var d := delta * float(speed)
		elapsed += d
		_update_rush(d)
		spawn_acc += d
		while spawn_acc >= _spawn_interval():
			spawn_acc -= _spawn_interval()
			_spawn_agent()
		_update_agents(d)
		_update_overload(d)
	queue_redraw()

func _generate_map() -> void:
	nodes.clear()
	edges.clear()
	overload.clear()
	var left := BOARD.position.x + 88.0
	var right := BOARD.end.x - 88.0
	var top := BOARD.position.y + 96.0
	var bottom := BOARD.end.y - 92.0
	for row in range(3):
		for col in range(4):
			var p := Vector2(lerpf(left, right, float(col) / 3.0), lerpf(top, bottom, float(row) / 2.0))
			if col == 1 or col == 2:
				p += Vector2(rng.randf_range(-28, 28), rng.randf_range(-34, 34))
			nodes.append({"pos": p})
			overload.append(0.0)
	for row in range(3):
		var b := row * 4
		_add_edge(b, b + 1, 2)
		_add_edge(b + 1, b + 2, 2)
		_add_edge(b + 2, b + 3, 2)
	_add_edge(1, 5, 1)
	_add_edge(5, 9, 1)
	_add_edge(2, 6, 1)
	_add_edge(6, 10, 1)
	var diagonals := [[0,5], [4,1], [4,9], [8,5], [3,6], [7,2], [7,10], [11,6]]
	diagonals.shuffle()
	for i in range(4):
		_add_edge(int(diagonals[i][0]), int(diagonals[i][1]), 1)
	var outs: Array[int] = [3, 7, 11]
	outs.shuffle()
	if outs == [3, 7, 11]:
		outs = [7, 11, 3]
	sink_nodes = outs
	_reset(false)
	status = "Rush waves will keep changing which corridor is under pressure."

func _add_edge(a: int, b: int, cap: int, bypass := false) -> void:
	if _edge_between(a, b) >= 0:
		return
	edges.append({"a": a, "b": b, "capacity": cap, "base_capacity": cap, "widen": 0, "mode": 0, "load": 0, "length": nodes[a]["pos"].distance_to(nodes[b]["pos"]), "bypass": bypass})

func _reset(reset_infra := true) -> void:
	agents.clear()
	if reset_infra:
		for i in range(edges.size() - 1, -1, -1):
			if bool(edges[i].get("bypass", false)):
				edges.remove_at(i)
			else:
				edges[i]["capacity"] = int(edges[i]["base_capacity"])
				edges[i]["widen"] = 0
				edges[i]["mode"] = 0
		control_limit = CONTROL_BASE
		bypass_count = 0
	for i in range(edges.size()):
		edges[i]["load"] = 0
	for i in range(overload.size()):
		overload[i] = 0.0
	running = false
	paused = false
	game_over = false
	cleared = false
	elapsed = 0.0
	score = 0
	stage = 0
	speed = 1
	spawn_acc = 0.0
	spawn_seq = 0
	upgrade_pending = false
	upgrade_action = ""
	bypass_first = -1
	rush_color = -1
	next_rush_color = rng.randi_range(0, 2)
	rush_remaining = 0.0
	next_rush_at = RUSH_FIRST

func _spawn_interval() -> float:
	return maxf(MIN_INTERVAL, BASE_INTERVAL - float(stage) * 0.07 - minf(0.10, elapsed * 0.0006))

func _spawn_agent() -> void:
	var color := spawn_seq % 3
	if rush_color >= 0 and rush_remaining > 0.0 and spawn_seq % 3 != 0:
		color = rush_color
	spawn_seq += 1
	var limit := base_limits[color] + stage * 2
	if color == rush_color and rush_remaining > 0.0:
		limit += RUSH_BONUS
	if _inflight(color) >= limit:
		return
	agents.append({"node": source_nodes[color], "target": sink_nodes[color], "color": color, "edge": -1, "to": -1, "progress": 0.0, "recent": [source_nodes[color]]})

func _inflight(color: int) -> int:
	var n := 0
	for a in agents:
		if int(a["color"]) == color:
			n += 1
	return n

func _update_rush(delta: float) -> void:
	if rush_remaining > 0.0:
		rush_remaining = maxf(0.0, rush_remaining - delta)
		if rush_remaining == 0.0:
			var old := rush_color
			rush_color = -1
			next_rush_color = rng.randi_range(0, 2)
			if next_rush_color == old:
				next_rush_color = (old + 1) % 3
			next_rush_at = elapsed + rng.randf_range(RUSH_GAP_MIN, RUSH_GAP_MAX)
			status = "Rush cleared. Rebalance for the next one."
		return
	if elapsed >= next_rush_at:
		rush_color = next_rush_color
		rush_remaining = RUSH_DURATION
		status = "RUSH ACTIVE: %s" % _color_name(rush_color)

func _update_agents(delta: float) -> void:
	for i in range(agents.size() - 1, -1, -1):
		var a: Dictionary = agents[i]
		var edge_id := int(a["edge"])
		if edge_id >= 0:
			var length := maxf(1.0, float(edges[edge_id]["length"]))
			a["progress"] = float(a["progress"]) + AGENT_SPEED / length * delta
			if float(a["progress"]) >= 1.0:
				edges[edge_id]["load"] = maxi(0, int(edges[edge_id]["load"]) - 1)
				var arrived := int(a["to"])
				a["node"] = arrived
				a["edge"] = -1
				a["to"] = -1
				a["progress"] = 0.0
				var recent: Array = a["recent"]
				recent.append(arrived)
				while recent.size() > 4:
					recent.pop_front()
				a["recent"] = recent
				if arrived == int(a["target"]):
					score += 1
					agents.remove_at(i)
					_check_progress()
					continue
		else:
			var current := int(a["node"])
			var next := _next_hop(current, int(a["target"]), a["recent"])
			if next >= 0:
				var e := _edge_between(current, next)
				var cap := _capacity(e)
				if e >= 0 and cap > 0 and int(edges[e]["load"]) < cap:
					edges[e]["load"] = int(edges[e]["load"]) + 1
					a["edge"] = e
					a["to"] = next
		agents[i] = a

func _next_hop(start: int, target: int, recent: Array) -> int:
	var dist: Array[float] = []
	var prev: Array[int] = []
	var used: Array[bool] = []
	var waiting := _waiting_counts()
	for i in range(nodes.size()):
		dist.append(INF)
		prev.append(-1)
		used.append(false)
	dist[start] = 0.0
	for step in range(nodes.size()):
		var cur := -1
		var best := INF
		for i in range(nodes.size()):
			if not used[i] and dist[i] < best:
				cur = i
				best = dist[i]
		if cur < 0 or cur == target:
			break
		used[cur] = true
		for e in range(edges.size()):
			var n := _neighbor(e, cur)
			if n < 0:
				continue
			var cap := maxi(1, _capacity(e))
			var ratio := float(edges[e]["load"]) / float(cap)
			var cost := float(edges[e]["length"]) * (1.0 + ratio * ratio * 2.6)
			if int(edges[e]["load"]) >= cap:
				cost *= 7.0
			cost += float(waiting[n]) * 36.0
			if recent.size() >= 2 and n == int(recent[recent.size() - 2]):
				cost += 5000.0
			elif recent.has(n) and n != target:
				cost += 950.0
			if dist[cur] + cost < dist[n]:
				dist[n] = dist[cur] + cost
				prev[n] = cur
	if prev[target] < 0:
		return -1
	var cursor := target
	while prev[cursor] >= 0 and prev[cursor] != start:
		cursor = prev[cursor]
	return cursor if prev[cursor] == start else -1

func _neighbor(edge_id: int, from_node: int) -> int:
	var e := edges[edge_id]
	var a := int(e["a"])
	var b := int(e["b"])
	var mode := int(e["mode"])
	if mode == 3:
		return -1
	if mode == 0:
		if from_node == a:
			return b
		if from_node == b:
			return a
	if mode == 1 and from_node == a:
		return b
	if mode == 2 and from_node == b:
		return a
	return -1

func _capacity(edge_id: int) -> int:
	if edge_id < 0:
		return 0
	var c := int(edges[edge_id]["capacity"])
	var mode := int(edges[edge_id]["mode"])
	if mode == 1 or mode == 2:
		c += ONE_WAY_BONUS
	return 0 if mode == 3 else c

func _waiting_counts() -> Array[int]:
	var out: Array[int] = []
	for i in range(nodes.size()):
		out.append(0)
	for a in agents:
		if int(a["edge"]) < 0 and int(a["node"]) != int(a["target"]):
			out[int(a["node"])] += 1
	return out

func _update_overload(delta: float) -> void:
	var waiting := _waiting_counts()
	for i in range(waiting.size()):
		if waiting[i] >= FAIL_QUEUE:
			overload[i] += delta
		else:
			overload[i] = maxf(0.0, overload[i] - delta * 1.6)
		if overload[i] >= FAIL_SECONDS:
			game_over = true
			running = false
			status = "FLOW COLLAPSED — retry with a different control pattern."
			return

func _check_progress() -> void:
	if score >= CLEAR_SCORE:
		cleared = true
		running = false
		status = "MAP STABILIZED — NEXT MAP."
		return
	if stage < STAGE_SCORES.size() and score >= int(STAGE_SCORES[stage]) and not upgrade_pending:
		upgrade_pending = true
		paused = true
		status = "TRAFFIC SHIFT — choose an upgrade."

func _finish_upgrade(message: String) -> void:
	upgrade_pending = false
	upgrade_action = ""
	bypass_first = -1
	stage += 1
	var old := sink_nodes.duplicate()
	sink_nodes = [old[1], old[2], old[0]]
	for i in range(agents.size()):
		var color := int(agents[i]["color"])
		agents[i]["target"] = sink_nodes[color]
		agents[i]["recent"] = [int(agents[i]["node"])]
	paused = false
	spawn_acc = 0.0
	status = message + " Destinations rotated."

func _apply_widen(edge_id: int) -> void:
	if edge_id < 0:
		status = "WIDEN — click a road."
		return
	edges[edge_id]["capacity"] = int(edges[edge_id]["capacity"]) + 1
	edges[edge_id]["widen"] = int(edges[edge_id]["widen"]) + 1
	_finish_upgrade("Road widened.")

func _apply_bypass(node_id: int) -> void:
	if bypass_count >= BYPASS_MAX:
		status = "Bypass already used."
		return
	if node_id < 0:
		status = "BYPASS — click a junction."
		return
	if bypass_first < 0:
		bypass_first = node_id
		status = "BYPASS — click the second junction."
		return
	if node_id == bypass_first or _edge_between(bypass_first, node_id) >= 0:
		status = "Choose a different unconnected junction."
		return
	if nodes[bypass_first]["pos"].distance_to(nodes[node_id]["pos"]) > BYPASS_LENGTH:
		status = "Bypass too long."
		return
	_add_edge(bypass_first, node_id, 1, true)
	bypass_count += 1
	_finish_upgrade("Bypass opened.")

func _edge_between(a: int, b: int) -> int:
	for i in range(edges.size()):
		if (int(edges[i]["a"]) == a and int(edges[i]["b"]) == b) or (int(edges[i]["a"]) == b and int(edges[i]["b"]) == a):
			return i
	return -1

func _controls_used() -> int:
	var n := 0
	for e in edges:
		if int(e["mode"]) != 0:
			n += 1
	return n

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()
		elif event.keycode == KEY_R:
			_reset(true)
		elif event.keycode == KEY_N:
			_generate_map()
		elif event.keycode == KEY_1:
			speed = 1
		elif event.keycode == KEY_2:
			speed = 2
		elif event.keycode == KEY_3:
			speed = 3
	if event is InputEventMouseMotion:
		hovered_edge = _find_edge(event.position)
		hovered_node = _find_node(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_click(event.position)

func _click(pos: Vector2) -> void:
	var b := _buttons()
	if b[0].has_point(pos):
		_toggle_pause(); return
	if b[1].has_point(pos):
		_reset(true); return
	if b[2].has_point(pos):
		_generate_map(); return
	if b[3].has_point(pos):
		speed = 1; return
	if b[4].has_point(pos):
		speed = 2; return
	if b[5].has_point(pos):
		speed = 3; return
	if upgrade_pending:
		if b[6].has_point(pos):
			upgrade_action = "widen"; status = "WIDEN — click a road."; return
		if b[7].has_point(pos):
			if bypass_count >= BYPASS_MAX:
				status = "Bypass already used."; return
			upgrade_action = "bypass"; status = "BYPASS — click two junctions."; return
		if b[8].has_point(pos):
			control_limit += 1; _finish_upgrade("Control +1."); return
	if not BOARD.has_point(pos):
		return
	if upgrade_pending and upgrade_action == "widen":
		_apply_widen(_find_edge(pos)); return
	if upgrade_pending and upgrade_action == "bypass":
		_apply_bypass(_find_node(pos)); return
	if upgrade_pending:
		return
	var e := _find_edge(pos)
	if e >= 0:
		var next := (int(edges[e]["mode"]) + 1) % 4
		if int(edges[e]["mode"]) == 0 and next != 0 and _controls_used() >= control_limit:
			status = "No control tokens left."
			return
		edges[e]["mode"] = next

func _toggle_pause() -> void:
	if upgrade_pending:
		status = "Choose an upgrade first."
		return
	if cleared:
		_generate_map()
		return
	if game_over:
		_reset(true)
		return
	if not running:
		running = true
		paused = false
	else:
		paused = not paused

func _find_edge(pos: Vector2) -> int:
	var best := -1
	var best_d := 14.0
	for i in range(edges.size()):
		var a: Vector2 = nodes[int(edges[i]["a"])]["pos"]
		var b: Vector2 = nodes[int(edges[i]["b"])]["pos"]
		var d := _segment_distance(pos, a, b)
		if d < best_d:
			best_d = d
			best = i
	return best

func _find_node(pos: Vector2) -> int:
	var best := -1
	var best_d := 18.0
	for i in range(nodes.size()):
		var d := pos.distance_to(nodes[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best

func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _buttons() -> Array[Rect2]:
	return [Rect2(1004,104,252,44), Rect2(1004,160,122,36), Rect2(1134,160,122,36), Rect2(1004,210,78,34), Rect2(1091,210,78,34), Rect2(1178,210,78,34), Rect2(1004,268,78,36), Rect2(1091,268,78,36), Rect2(1178,268,78,36)]

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720), Color("#f2f0e9"), true)
	draw_rect(BOARD, Color("#fbfaf6"), true)
	_draw_edges()
	_draw_nodes()
	_draw_agents()
	_draw_rush_banner()
	draw_rect(BOARD, Color("#b9b5ac"), false, 1.0)
	_draw_panel()

func _draw_edges() -> void:
	for i in range(edges.size()):
		var e := edges[i]
		var a: Vector2 = nodes[int(e["a"])]["pos"]
		var b: Vector2 = nodes[int(e["b"])]["pos"]
		var ratio := float(e["load"]) / float(maxi(1, _capacity(i)))
		var width := 5.0 + ratio * 4.0
		var color := Color("#b7b29f") if bool(e.get("bypass", false)) else Color("#c8c5be")
		if int(e["widen"]) > 0:
			width += 5.0
			color = Color("#8f8468")
		if i == hovered_edge:
			color = Color("#77736b")
		draw_line(a, b, color, width, true)
		draw_line(a, b, Color("#f8f7f2"), maxf(2.0, width - 3.0), true)
		if int(e["widen"]) > 0:
			_draw_widen(a, b, int(e["widen"]))
		_draw_rule(i, a, b)

func _draw_widen(a: Vector2, b: Vector2, level: int) -> void:
	var mid := (a + b) * 0.5
	draw_circle(mid, 10.0, Color("#fbfaf6"))
	draw_arc(mid, 10.0, 0.0, TAU, 20, Color("#8f8468"), 2.0, true)
	draw_string(font, mid + Vector2(-7,4), "+%d" % level, HORIZONTAL_ALIGNMENT_CENTER, 14, 9, Color("#655f50"))

func _draw_rule(id: int, a: Vector2, b: Vector2) -> void:
	var mode := int(edges[id]["mode"])
	if mode == 0:
		return
	var mid := (a + b) * 0.5
	if mode == 3:
		draw_circle(mid, 9.0, Color("#fbfaf6"))
		draw_line(mid + Vector2(-5,-5), mid + Vector2(5,5), Color("#44484a"), 2.2)
		draw_line(mid + Vector2(-5,5), mid + Vector2(5,-5), Color("#44484a"), 2.2)
		return
	var start := a if mode == 1 else b
	var finish := b if mode == 1 else a
	var dir := (finish - start).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var tip := mid + dir * 8.0
	var base := mid - dir * 7.0
	draw_polyline(PackedVector2Array([base + normal * 5.0, tip, base - normal * 5.0]), Color("#34383a"), 2.3, true)

func _draw_nodes() -> void:
	var waiting := _waiting_counts()
	for i in range(nodes.size()):
		var p: Vector2 = nodes[i]["pos"]
		if waiting[i] > 0:
			draw_circle(p, 18.0 + minf(18.0, float(waiting[i]) * 1.8), Color(0.78,0.28,0.25,0.08))
		if overload[i] > 0.0:
			draw_arc(p, 23.0, -PI/2.0, -PI/2.0 + TAU * clampf(overload[i]/FAIL_SECONDS,0,1), 28, Color("#c34f4f"), 4.0)
		draw_circle(p, 7.0, Color("#565b5d"))
	for c in range(3):
		var s := source_nodes[c]
		var t := sink_nodes[c]
		var sp: Vector2 = nodes[s]["pos"]
		var tp: Vector2 = nodes[t]["pos"]
		if c == rush_color and rush_remaining > 0.0:
			draw_arc(sp, 20.0 + sin(elapsed*7.0)*3.0, 0, TAU, 30, flow_colors[c], 3.0)
		elif _rush_warning() and c == next_rush_color:
			draw_arc(sp, 19.0 + sin(elapsed*6.0)*2.0, 0, TAU, 30, flow_colors[c], 2.0)
		draw_rect(Rect2(sp-Vector2(14,14), Vector2(28,28)), Color("#fbfaf6"), true)
		draw_rect(Rect2(sp-Vector2(14,14), Vector2(28,28)), flow_colors[c], false, 3.0)
		draw_circle(tp, 16.0, Color("#fbfaf6"))
		draw_arc(tp, 16.0, 0, TAU, 28, flow_colors[c], 4.0)

func _draw_agents() -> void:
	var waiting_index := {}
	for a in agents:
		var p: Vector2
		if int(a["edge"]) >= 0:
			p = nodes[int(a["node"])]["pos"].lerp(nodes[int(a["to"])]["pos"], clampf(float(a["progress"]),0,1))
		else:
			var n := int(a["node"])
			var idx := int(waiting_index.get(n,0))
			waiting_index[n] = idx + 1
			p = nodes[n]["pos"] + Vector2(cos(float(idx)*2.2), sin(float(idx)*2.2)) * (12.0 + float(int(idx/5))*6.0)
		draw_circle(p, 4.3, flow_colors[int(a["color"])])

func _rush_warning() -> bool:
	return rush_remaining <= 0.0 and next_rush_at > elapsed and next_rush_at - elapsed <= RUSH_WARNING

func _draw_rush_banner() -> void:
	if rush_color >= 0 and rush_remaining > 0.0:
		var r := Rect2(BOARD.position + Vector2(280,10), Vector2(380,36))
		draw_rect(r, Color(1,1,1,0.9), true)
		draw_rect(r, flow_colors[rush_color], false, 2.0)
		draw_string(font, r.position + Vector2(8,24), "RUSH: %s  %.0fs" % [_color_name(rush_color), rush_remaining], HORIZONTAL_ALIGNMENT_CENTER, r.size.x-16, 13, flow_colors[rush_color])
	elif _rush_warning():
		var r := Rect2(BOARD.position + Vector2(300,10), Vector2(340,34))
		draw_rect(r, Color(1,1,1,0.9), true)
		draw_rect(r, flow_colors[next_rush_color], false, 1.5)
		draw_string(font, r.position + Vector2(8,23), "%s RUSH IN %ds" % [_color_name(next_rush_color), int(ceil(next_rush_at-elapsed))], HORIZONTAL_ALIGNMENT_CENTER, r.size.x-16, 12, flow_colors[next_rush_color])

func _draw_panel() -> void:
	draw_rect(PANEL, Color("#e9e6dd"), true)
	draw_string(font, Vector2(1004,32), "FLOW CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#292e31"))
	draw_string(font, Vector2(1004,56), "rush waves  v0.4", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#666b6d"))
	var b := _buttons()
	_button(b[0], _start_label(), Color("#c7d9bf"))
	_button(b[1], "RESET", Color("#d8d4cb"))
	_button(b[2], "NEW MAP", Color("#d8d4cb"))
	draw_string(font, Vector2(1004,206), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#666b6d"))
	_button(b[3], "x1", Color("#c7d9bf") if speed == 1 else Color("#ddd8cf"))
	_button(b[4], "x2", Color("#c7d9bf") if speed == 2 else Color("#ddd8cf"))
	_button(b[5], "x3", Color("#c7d9bf") if speed == 3 else Color("#ddd8cf"))
	if upgrade_pending:
		_button(b[6], "WIDEN", Color("#cfd9c8") if upgrade_action == "widen" else Color("#ddd8cf"))
		_button(b[7], "USED" if bypass_count >= BYPASS_MAX else "BYPASS", Color("#cbd6df") if upgrade_action == "bypass" else Color("#ddd8cf"))
		_button(b[8], "+CTRL", Color("#ddd8cf"))
	draw_string(font, Vector2(1004,338), "Score  %d / %d" % [score,CLEAR_SCORE], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#303538"))
	draw_string(font, Vector2(1004,372), "Stage  %d / %d" % [stage+1,STAGE_SCORES.size()+1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#555a5c"))
	draw_string(font, Vector2(1004,394), "Time  %02d:%02d" % [int(elapsed)/60,int(elapsed)%60], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#555a5c"))
	draw_string(font, Vector2(1004,416), "Controls  %d / %d" % [_controls_used(),control_limit], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#555a5c"))
	draw_string(font, Vector2(1004,456), _rush_text(), HORIZONTAL_ALIGNMENT_LEFT, 252, 12, _rush_color())
	draw_string(font, Vector2(1004,505), "ROAD CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#363b3d"))
	draw_string(font, Vector2(1004,530), "↔  →  ←  ×", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("#363b3d"))
	draw_string(font, Vector2(1004,558), "Widen = bold road + badge", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#656a6c"))
	draw_string(font, Vector2(1004,590), status, HORIZONTAL_ALIGNMENT_LEFT, 252, 10, Color("#464b4d"))
	draw_string(font, Vector2(1004,675), "1/2/3 speed   Space pause   R/N", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#777b7d"))

func _rush_text() -> String:
	if rush_color >= 0 and rush_remaining > 0:
		return "RUSH  %s  %.0fs" % [_color_name(rush_color),rush_remaining]
	if _rush_warning():
		return "%s rush in %ds" % [_color_name(next_rush_color),int(ceil(next_rush_at-elapsed))]
	return "Next rush in ~%ds" % maxi(0,int(next_rush_at-elapsed))

func _rush_color() -> Color:
	return flow_colors[rush_color] if rush_color >= 0 and rush_remaining > 0 else Color("#666b6d")

func _start_label() -> String:
	if upgrade_pending:
		return "UPGRADE"
	if cleared:
		return "NEXT MAP"
	if game_over:
		return "TRY AGAIN"
	if not running:
		return "START"
	return "RESUME" if paused else "PAUSE"

func _button(rect: Rect2, label: String, fill: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color("#77736b"), false, 1.0)
	draw_string(font, rect.position + Vector2(6,24), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x-12, 11, Color("#303437"))

func _color_name(i: int) -> String:
	return ["RED","BLUE","GREEN"][i] if i >= 0 and i < 3 else "?"
