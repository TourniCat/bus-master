extends Node2D

const BUILD: String = "0.1.0-grow-core"
const BOARD := Rect2(18, 18, 950, 684)
const PANEL := Rect2(986, 0, 294, 720)

const START_ENERGY: float = 105.0
const BASE_METABOLISM: float = 0.75
const GROW_COST_PER_PIXEL: float = 0.16
const MAINTENANCE_PER_PIXEL: float = 0.0045
const HARVEST_RATE: float = 4.8
const ENERGY_PER_NUTRIENT: float = 1.0
const RESOURCE_MIN: float = 70.0
const RESOURCE_MAX: float = 115.0
const INITIAL_RESOURCES: int = 5
const MAX_LIVE_RESOURCES: int = 9
const RESOURCE_SPAWN_MIN: float = 10.0
const RESOURCE_SPAWN_MAX: float = 16.0
const SNAP_RADIUS: float = 38.0
const NODE_PICK_RADIUS: float = 17.0
const BRANCH_PICK_RADIUS: float = 11.0
const MIN_BRANCH_LENGTH: float = 20.0
const MAX_BRANCH_LENGTH: float = 210.0
const PRUNE_REFUND_PER_PIXEL: float = 0.045
const RESOURCE_HIDE_AFTER: float = 9.0

var font: Font
var rng := RandomNumberGenerator.new()

var nodes: Array[Dictionary] = []
var branches: Array[Dictionary] = []
var resources: Array[Dictionary] = []

var energy: float = START_ENERGY
var absorbed: float = 0.0
var elapsed: float = 0.0
var running: bool = true
var game_over: bool = false
var speed: int = 1
var spawn_timer: float = 12.0
var status_text: String = "Drag from a white node to grow. Right-click a branch to prune."

var growing: bool = false
var grow_from_node: int = -1
var grow_preview: Vector2 = Vector2.ZERO
var hovered_node: int = -1
var hovered_branch: int = -1


func _ready() -> void:
	font = ThemeDB.fallback_font
	rng.randomize()
	_new_map()
	print("[GROW] START build=%s godot=%s" % [BUILD, String(Engine.get_version_info().get("string", "unknown"))])


func _process(delta: float) -> void:
	if running and not game_over:
		var d: float = delta * float(speed)
		elapsed += d
		spawn_timer -= d
		if spawn_timer <= 0.0:
			_spawn_resource()
			spawn_timer = rng.randf_range(RESOURCE_SPAWN_MIN, RESOURCE_SPAWN_MAX)
		_update_resources(d)
		energy -= _total_upkeep() * d
		if energy <= 0.0:
			energy = 0.0
			game_over = true
			running = false
			growing = false
			status_text = "THE NETWORK STARVED — start a new map."
			print("[GROW] GAME_OVER absorbed=%.1f time=%.1f" % [absorbed, elapsed])
	queue_redraw()


func _new_map() -> void:
	nodes.clear()
	branches.clear()
	resources.clear()
	energy = START_ENERGY
	absorbed = 0.0
	elapsed = 0.0
	running = true
	game_over = false
	speed = 1
	spawn_timer = rng.randf_range(RESOURCE_SPAWN_MIN, RESOURCE_SPAWN_MAX)
	growing = false
	grow_from_node = -1
	hovered_node = -1
	hovered_branch = -1
	status_text = "Grow toward nutrients. Old empty branches still cost energy."

	var core_pos := Vector2(BOARD.position.x + BOARD.size.x * 0.48, BOARD.position.y + BOARD.size.y * 0.52)
	nodes.append({"pos": core_pos, "parent_branch": -1, "alive": true, "core": true})

	for _i in range(INITIAL_RESOURCES):
		_spawn_resource(true)

	print("[GROW] NEW_MAP resources=%d" % resources.size())
	queue_redraw()


func _spawn_resource(initial: bool = false) -> void:
	if _live_resource_count() >= MAX_LIVE_RESOURCES:
		return

	var margin: float = 62.0
	var candidate := Vector2.ZERO
	var found: bool = false
	for _attempt in range(60):
		candidate = Vector2(
			rng.randf_range(BOARD.position.x + margin, BOARD.end.x - margin),
			rng.randf_range(BOARD.position.y + margin, BOARD.end.y - margin)
		)
		if candidate.distance_to(Vector2(nodes[0]["pos"])) < (135.0 if initial else 105.0):
			continue
		var clear: bool = true
		for resource in resources:
			if bool(resource.get("visible", true)) and candidate.distance_to(Vector2(resource["pos"])) < 82.0:
				clear = false
				break
		if clear:
			found = true
			break
	if not found:
		return

	var amount: float = rng.randf_range(RESOURCE_MIN, RESOURCE_MAX)
	resources.append({
		"pos": candidate,
		"amount": amount,
		"max_amount": amount,
		"connected_node": -1,
		"depleted_age": 0.0,
		"visible": true
	})
	if not initial:
		status_text = "A new nutrient pocket appeared."


func _live_resource_count() -> int:
	var count: int = 0
	for resource in resources:
		if bool(resource.get("visible", true)) and float(resource["amount"]) > 0.0:
			count += 1
	return count


func _update_resources(delta: float) -> void:
	for i in range(resources.size()):
		var resource: Dictionary = resources[i]
		if not bool(resource.get("visible", true)):
			continue
		var amount: float = float(resource["amount"])
		var connected_node: int = int(resource["connected_node"])
		if amount > 0.0 and connected_node >= 0 and _node_alive(connected_node):
			var harvested: float = minf(amount, HARVEST_RATE * delta)
			resource["amount"] = amount - harvested
			energy += harvested * ENERGY_PER_NUTRIENT
			absorbed += harvested
			if float(resource["amount"]) <= 0.001:
				resource["amount"] = 0.0
				resource["connected_node"] = -1
				resource["depleted_age"] = 0.0
				status_text = "A nutrient pocket is empty. Prune dead wood or extend onward."
		else:
			if amount <= 0.0:
				resource["depleted_age"] = float(resource["depleted_age"]) + delta
				if float(resource["depleted_age"]) >= RESOURCE_HIDE_AFTER:
					resource["visible"] = false
		resources[i] = resource


func _total_branch_length() -> float:
	var total: float = 0.0
	for branch in branches:
		if bool(branch["alive"]):
			total += float(branch["length"])
	return total


func _maintenance() -> float:
	return _total_branch_length() * MAINTENANCE_PER_PIXEL


func _income_per_second() -> float:
	var connected: int = 0
	for resource in resources:
		var node_id: int = int(resource["connected_node"])
		if float(resource["amount"]) > 0.0 and node_id >= 0 and _node_alive(node_id):
			connected += 1
	return float(connected) * HARVEST_RATE * ENERGY_PER_NUTRIENT


func _total_upkeep() -> float:
	return BASE_METABOLISM + _maintenance()


func _net_rate() -> float:
	return _income_per_second() - _total_upkeep()


func _node_alive(node_id: int) -> bool:
	return node_id >= 0 and node_id < nodes.size() and bool(nodes[node_id]["alive"])


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if not game_over:
					running = not running
					status_text = "Paused." if not running else "Growing."
			KEY_N:
				_new_map()
			KEY_1:
				speed = 1
			KEY_2:
				speed = 2
			KEY_3:
				speed = 3

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if growing:
			grow_preview = _clamped_growth_point(motion.position)
		else:
			hovered_node = _find_node_at(motion.position)
			hovered_branch = _find_branch_at(motion.position)
		queue_redraw()

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_handle_left_press(mouse.position)
			else:
				_handle_left_release(mouse.position)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			_handle_right_click(mouse.position)


func _handle_left_press(pos: Vector2) -> void:
	var buttons: Array[Rect2] = _buttons()
	if buttons[0].has_point(pos):
		if game_over:
			_new_map()
		else:
			running = not running
			status_text = "Paused." if not running else "Growing."
		return
	if buttons[1].has_point(pos):
		_new_map()
		return
	for i in range(3):
		if buttons[2 + i].has_point(pos):
			speed = i + 1
			return
	if game_over or not BOARD.has_point(pos):
		return

	var node_id: int = _find_node_at(pos)
	if node_id < 0:
		status_text = "Start a branch from an existing white junction."
		return
	growing = true
	grow_from_node = node_id
	grow_preview = Vector2(nodes[node_id]["pos"])


func _handle_left_release(pos: Vector2) -> void:
	if not growing:
		return
	growing = false
	if grow_from_node < 0 or game_over:
		grow_from_node = -1
		return

	var start := Vector2(nodes[grow_from_node]["pos"])
	var end := _clamped_growth_point(pos)
	var resource_id: int = _nearest_unconnected_resource(end, SNAP_RADIUS)
	if resource_id >= 0:
		end = Vector2(resources[resource_id]["pos"])
		end = _limit_from_start(start, end)

	var length: float = start.distance_to(end)
	if length < MIN_BRANCH_LENGTH:
		status_text = "Branch too short."
		grow_from_node = -1
		return

	var cost: float = length * GROW_COST_PER_PIXEL
	if cost > energy:
		status_text = "Not enough energy: need %.0f." % cost
		grow_from_node = -1
		return

	energy -= cost
	var new_node: int = nodes.size()
	var branch_id: int = branches.size()
	nodes.append({"pos": end, "parent_branch": branch_id, "alive": true, "core": false})
	branches.append({"a": grow_from_node, "b": new_node, "length": length, "alive": true})

	if resource_id >= 0 and end.distance_to(Vector2(resources[resource_id]["pos"])) <= 1.0:
		resources[resource_id]["connected_node"] = new_node
		status_text = "Nutrient connected. Energy is flowing back to the core."
	else:
		status_text = "Branch grown: -%.0f energy." % cost

	grow_from_node = -1
	queue_redraw()


func _handle_right_click(pos: Vector2) -> void:
	if game_over or not BOARD.has_point(pos):
		return
	var branch_id: int = _find_branch_at(pos)
	if branch_id < 0:
		status_text = "Right-click directly on a branch to prune it."
		return
	_prune_branch(branch_id)


func _prune_branch(branch_id: int) -> void:
	if branch_id < 0 or branch_id >= branches.size() or not bool(branches[branch_id]["alive"]):
		return
	var root_node: int = int(branches[branch_id]["b"])
	var removed_nodes: Dictionary = {}
	var removed_length: float = _prune_node_recursive(root_node, removed_nodes)
	branches[branch_id]["alive"] = false
	removed_length += float(branches[branch_id]["length"])

	for i in range(resources.size()):
		var connected_node: int = int(resources[i]["connected_node"])
		if connected_node >= 0 and removed_nodes.has(connected_node):
			resources[i]["connected_node"] = -1

	var refund: float = removed_length * PRUNE_REFUND_PER_PIXEL
	energy += refund
	status_text = "Pruned %.0f px. Recovered %.0f energy and cut upkeep." % [removed_length, refund]
	queue_redraw()


func _prune_node_recursive(node_id: int, removed_nodes: Dictionary) -> float:
	if not _node_alive(node_id):
		return 0.0
	removed_nodes[node_id] = true
	nodes[node_id]["alive"] = false
	var removed_length: float = 0.0
	for i in range(branches.size()):
		if not bool(branches[i]["alive"]):
			continue
		if int(branches[i]["a"]) == node_id:
			var child: int = int(branches[i]["b"])
			removed_length += _prune_node_recursive(child, removed_nodes)
			branches[i]["alive"] = false
			removed_length += float(branches[i]["length"])
	return removed_length


func _clamped_growth_point(raw: Vector2) -> Vector2:
	var p := Vector2(
		clampf(raw.x, BOARD.position.x + 12.0, BOARD.end.x - 12.0),
		clampf(raw.y, BOARD.position.y + 12.0, BOARD.end.y - 12.0)
	)
	if grow_from_node >= 0 and _node_alive(grow_from_node):
		p = _limit_from_start(Vector2(nodes[grow_from_node]["pos"]), p)
	return p


func _limit_from_start(start: Vector2, target: Vector2) -> Vector2:
	var delta: Vector2 = target - start
	if delta.length() > MAX_BRANCH_LENGTH:
		return start + delta.normalized() * MAX_BRANCH_LENGTH
	return target


func _nearest_unconnected_resource(pos: Vector2, radius: float) -> int:
	var best: int = -1
	var best_distance: float = radius
	for i in range(resources.size()):
		var resource: Dictionary = resources[i]
		if not bool(resource.get("visible", true)) or float(resource["amount"]) <= 0.0:
			continue
		if int(resource["connected_node"]) >= 0:
			continue
		var distance: float = pos.distance_to(Vector2(resource["pos"]))
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _find_node_at(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = NODE_PICK_RADIUS
	for i in range(nodes.size()):
		if not _node_alive(i):
			continue
		var distance: float = pos.distance_to(Vector2(nodes[i]["pos"]))
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _find_branch_at(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = BRANCH_PICK_RADIUS
	for i in range(branches.size()):
		if not bool(branches[i]["alive"]):
			continue
		var a := Vector2(nodes[int(branches[i]["a"])]["pos"])
		var b := Vector2(nodes[int(branches[i]["b"])]["pos"])
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


func _active_resource_count_for_subtree(node_id: int) -> int:
	if not _node_alive(node_id):
		return 0
	var count: int = 0
	for resource in resources:
		if int(resource["connected_node"]) == node_id and float(resource["amount"]) > 0.0:
			count += 1
	for branch in branches:
		if bool(branch["alive"]) and int(branch["a"]) == node_id:
			count += _active_resource_count_for_subtree(int(branch["b"]))
	return count


func _buttons() -> Array[Rect2]:
	return [
		Rect2(1008, 104, 244, 44),
		Rect2(1008, 160, 244, 38),
		Rect2(1008, 214, 72, 34),
		Rect2(1094, 214, 72, 34),
		Rect2(1180, 214, 72, 34)
	]


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#171b18"), true)
	draw_rect(BOARD, Color("#202720"), true)
	_draw_resources()
	_draw_network()
	_draw_flow_pulses()
	_draw_growth_preview()
	draw_rect(BOARD, Color("#465048"), false, 1.0)
	_draw_panel()


func _draw_resources() -> void:
	for i in range(resources.size()):
		var resource: Dictionary = resources[i]
		if not bool(resource.get("visible", true)):
			continue
		var pos := Vector2(resource["pos"])
		var amount: float = float(resource["amount"])
		var max_amount: float = maxf(1.0, float(resource["max_amount"]))
		var ratio: float = amount / max_amount
		if amount <= 0.0:
			draw_circle(pos, 7.0, Color("#39423b"))
			draw_arc(pos, 12.0, 0.0, TAU, 24, Color("#56605a"), 1.5, true)
			continue
		var connected: bool = int(resource["connected_node"]) >= 0
		var glow := Color(0.55, 0.86, 0.43, 0.10 if not connected else 0.19)
		draw_circle(pos, 20.0 + 4.0 * ratio, glow)
		draw_circle(pos, 9.0 + 4.0 * ratio, Color("#89c96f") if connected else Color("#b1c978"))
		draw_arc(pos, 16.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 28, Color("#d8e9b6"), 2.5, true)


func _draw_network() -> void:
	for i in range(branches.size()):
		var branch: Dictionary = branches[i]
		if not bool(branch["alive"]):
			continue
		var a := Vector2(nodes[int(branch["a"])]["pos"])
		var b := Vector2(nodes[int(branch["b"])]["pos"])
		var feeds: int = _active_resource_count_for_subtree(int(branch["b"]))
		var width: float = 3.0 + minf(6.0, float(feeds) * 1.5)
		var color := Color("#d5e6cf") if feeds > 0 else Color("#829085")
		if i == hovered_branch and not growing:
			color = Color("#f0d5a8")
			draw_line(a, b, Color(0.92, 0.64, 0.36, 0.18), width + 8.0, true)
		draw_line(a, b, color, width, true)

	for i in range(nodes.size()):
		if not _node_alive(i):
			continue
		var pos := Vector2(nodes[i]["pos"])
		if bool(nodes[i]["core"]):
			draw_circle(pos, 19.0, Color(0.76, 0.91, 0.71, 0.12))
			draw_circle(pos, 10.0, Color("#e6f2df"))
			draw_arc(pos, 15.0, 0.0, TAU, 30, Color("#8fbd88"), 2.0, true)
		else:
			var r: float = 5.5 if i == hovered_node and not growing else 4.0
			draw_circle(pos, r, Color("#edf2ea"))


func _draw_flow_pulses() -> void:
	if branches.is_empty():
		return
	for resource in resources:
		var node_id: int = int(resource["connected_node"])
		if float(resource["amount"]) <= 0.0 or not _node_alive(node_id):
			continue
		var cursor: int = node_id
		var depth: int = 0
		while cursor > 0 and depth < nodes.size():
			var branch_id: int = int(nodes[cursor]["parent_branch"])
			if branch_id < 0 or branch_id >= branches.size() or not bool(branches[branch_id]["alive"]):
				break
			var branch: Dictionary = branches[branch_id]
			var child_pos := Vector2(nodes[int(branch["b"])]["pos"])
			var parent_pos := Vector2(nodes[int(branch["a"])]["pos"])
			var phase: float = fposmod(elapsed * 0.75 + float(node_id) * 0.17 + float(depth) * 0.23, 1.0)
			var pulse_pos := child_pos.lerp(parent_pos, phase)
			draw_circle(pulse_pos, 2.6, Color("#bff09e"))
			cursor = int(branch["a"])
			depth += 1


func _draw_growth_preview() -> void:
	if not growing or grow_from_node < 0 or not _node_alive(grow_from_node):
		return
	var start := Vector2(nodes[grow_from_node]["pos"])
	var end := grow_preview
	var snap_id: int = _nearest_unconnected_resource(end, SNAP_RADIUS)
	if snap_id >= 0:
		end = _limit_from_start(start, Vector2(resources[snap_id]["pos"]))
	var length: float = start.distance_to(end)
	var cost: float = length * GROW_COST_PER_PIXEL
	var okay: bool = length >= MIN_BRANCH_LENGTH and cost <= energy
	var color := Color("#dff3d6") if okay else Color("#d87b73")
	draw_line(start, end, color, 3.0, true)
	draw_circle(end, 6.0, color)
	draw_string(font, end + Vector2(10, -8), "-%.0f" % cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_panel() -> void:
	draw_rect(PANEL, Color("#e8e6dd"), true)
	draw_line(Vector2(986, 0), Vector2(986, 720), Color("#aba99f"), 1.0)
	draw_string(font, Vector2(1008, 36), "GROW", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#252b27"))
	draw_string(font, Vector2(1008, 60), "living network prototype  v0.1", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#656a66"))

	var buttons: Array[Rect2] = _buttons()
	_button(buttons[0], "NEW MAP" if game_over else ("RESUME" if not running else "PAUSE"), Color("#cbd8c4"))
	_button(buttons[1], "NEW MAP", Color("#d8d5cc"))
	for i in range(3):
		_button(buttons[2 + i], "x%d" % (i + 1), Color("#bfcdb8") if speed == i + 1 else Color("#d8d5cc"))

	draw_string(font, Vector2(1008, 292), "ENERGY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#666b67"))
	draw_string(font, Vector2(1008, 330), "%d" % int(energy), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("#2e3931"))
	var net: float = _net_rate()
	var net_text: String = "%+.1f / sec" % net
	draw_string(font, Vector2(1100, 326), net_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4d7951") if net >= 0.0 else Color("#a4504c"))

	draw_string(font, Vector2(1008, 372), "Income    +%.1f/s" % _income_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#59605b"))
	draw_string(font, Vector2(1008, 394), "Upkeep    -%.1f/s" % _total_upkeep(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#59605b"))
	draw_string(font, Vector2(1008, 416), "Network   %.0f px" % _total_branch_length(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#59605b"))
	draw_string(font, Vector2(1008, 454), "ABSORBED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#666b67"))
	draw_string(font, Vector2(1008, 484), "%d" % int(absorbed), HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("#2e3931"))
	draw_string(font, Vector2(1120, 482), "Time %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#666b67"))

	draw_string(font, Vector2(1008, 532), "LEFT DRAG", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#353b37"))
	draw_string(font, Vector2(1008, 552), "Grow from a white junction.", HORIZONTAL_ALIGNMENT_LEFT, 244, 11, Color("#656a66"))
	draw_string(font, Vector2(1008, 580), "RIGHT CLICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#353b37"))
	draw_string(font, Vector2(1008, 600), "Prune a branch + everything beyond it.", HORIZONTAL_ALIGNMENT_LEFT, 244, 11, Color("#656a66"))

	draw_string(font, Vector2(1008, 638), status_text, HORIZONTAL_ALIGNMENT_LEFT, 244, 11, Color("#474d49"))
	draw_string(font, Vector2(1008, 684), "Space pause   N new   1/2/3 speed", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#777b77"))


func _button(rect: Rect2, label: String, fill: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color("#85837b"), false, 1.0)
	draw_string(font, rect.position + Vector2(6, rect.size.y * 0.66), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12.0, 12, Color("#303632"))
