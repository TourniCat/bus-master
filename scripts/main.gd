extends Node2D

const MAX_ROUTES := 3
const MAX_TOTAL_BUSES := 6
const MAX_STOPS_PER_ROUTE := 6
const BUS_CAPACITY := 12
const SIM_MINUTES_PER_SECOND := 6.0
const PASSENGER_SPAWN_INTERVAL := 0.35

var font: Font
var road_points := [
	Vector2(120, 160), Vector2(300, 160), Vector2(500, 160), Vector2(720, 160), Vector2(980, 160),
	Vector2(120, 330), Vector2(300, 330), Vector2(500, 330), Vector2(720, 330), Vector2(980, 330),
	Vector2(120, 510), Vector2(300, 510), Vector2(500, 510), Vector2(720, 510), Vector2(980, 510)
]
var road_edges := [
	[0,1],[1,2],[2,3],[3,4],
	[5,6],[6,7],[7,8],[8,9],
	[10,11],[11,12],[12,13],[13,14],
	[0,5],[5,10],[1,6],[6,11],[2,7],[7,12],[3,8],[8,13],[4,9],[9,14],
	[1,5],[3,9],[7,13]
]
var adjacency := {}

var buildings := [
	Rect2(155, 205, 95, 70), Rect2(335, 205, 110, 70), Rect2(540, 205, 125, 70), Rect2(770, 205, 150, 70),
	Rect2(155, 375, 100, 75), Rect2(340, 375, 115, 75), Rect2(545, 375, 130, 75), Rect2(770, 375, 150, 75),
	Rect2(170, 545, 80, 60), Rect2(350, 545, 95, 60), Rect2(550, 545, 115, 60), Rect2(770, 545, 150, 60)
]

var stops := [
	{"name":"Homes W", "node":0,  "kind":"HOME",     "waiting":{}},
	{"name":"School",  "node":2,  "kind":"SCHOOL",   "waiting":{}},
	{"name":"Offices", "node":4,  "kind":"OFFICE",   "waiting":{}},
	{"name":"Shops",   "node":6,  "kind":"SHOP",     "waiting":{}},
	{"name":"Station", "node":7,  "kind":"STATION",  "waiting":{}},
	{"name":"Hospital","node":8,  "kind":"HOSPITAL", "waiting":{}},
	{"name":"Homes E", "node":14, "kind":"HOME",     "waiting":{}},
	{"name":"Park",    "node":12, "kind":"PARK",     "waiting":{}},
	{"name":"Campus",  "node":10, "kind":"SCHOOL",   "waiting":{}}
]

var route_colors := [Color("#ef6a73"), Color("#5f8fd8"), Color("#62a96b")]
var routes := []
var active_route := 0
var buses := []

var sim_running := false
var sim_minutes := 6.0 * 60.0
var day := 1
var spawn_accumulator := 0.0
var delivered := 0
var total_spawned := 0
var status_text := "Build a route: choose R1/R2/R3, then click stops. Add buses and press Start."

func _ready() -> void:
	font = ThemeDB.fallback_font
	_build_adjacency()
	for i in range(MAX_ROUTES):
		routes.append({"stops": [], "bus_count": 0})
	queue_redraw()

func _build_adjacency() -> void:
	for i in range(road_points.size()):
		adjacency[i] = []
	for edge in road_edges:
		adjacency[edge[0]].append(edge[1])
		adjacency[edge[1]].append(edge[0])

func _process(delta: float) -> void:
	if sim_running:
		sim_minutes += SIM_MINUTES_PER_SECOND * delta
		if sim_minutes >= 24.0 * 60.0:
			sim_minutes = 6.0 * 60.0
			day += 1
		spawn_accumulator += delta
		while spawn_accumulator >= PASSENGER_SPAWN_INTERVAL:
			spawn_accumulator -= PASSENGER_SPAWN_INTERVAL
			_spawn_passengers()
		_update_buses(delta)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _select_route(0)
			KEY_2: _select_route(1)
			KEY_3: _select_route(2)
			KEY_EQUAL, KEY_KP_ADD: _change_bus_count(1)
			KEY_MINUS, KEY_KP_SUBTRACT: _change_bus_count(-1)
			KEY_SPACE: _toggle_simulation()
			KEY_R: _reset_prototype()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_pointer(event.position)
	if event is InputEventScreenTouch and event.pressed:
		_handle_pointer(event.position)

func _handle_pointer(pos: Vector2) -> void:
	var rects := _button_rects()
	for i in range(3):
		if rects[i].has_point(pos):
			_select_route(i)
			return
	if rects[3].has_point(pos):
		_change_bus_count(-1)
		return
	if rects[4].has_point(pos):
		_change_bus_count(1)
		return
	if rects[5].has_point(pos):
		_toggle_simulation()
		return
	if rects[6].has_point(pos):
		_reset_prototype()
		return

	var nearest := -1
	var nearest_dist := 24.0
	for i in range(stops.size()):
		var p: Vector2 = road_points[stops[i]["node"]]
		var d := pos.distance_to(p)
		if d < nearest_dist:
			nearest = i
			nearest_dist = d
	if nearest >= 0:
		_edit_active_route(nearest)

func _button_rects() -> Array:
	return [
		Rect2(20, 662, 96, 40), Rect2(126, 662, 96, 40), Rect2(232, 662, 96, 40),
		Rect2(370, 662, 96, 40), Rect2(476, 662, 96, 40), Rect2(600, 662, 110, 40), Rect2(720, 662, 96, 40)
	]

func _select_route(index: int) -> void:
	active_route = index
	status_text = "Editing Route %d" % (index + 1)

func _edit_active_route(stop_index: int) -> void:
	var route_stops: Array = routes[active_route]["stops"]
	if route_stops.size() > 0 and route_stops[-1] == stop_index:
		route_stops.pop_back()
		status_text = "Removed last stop from Route %d" % (active_route + 1)
	elif route_stops.has(stop_index):
		status_text = "That stop is already on this route. Click the last stop to undo."
		return
	elif route_stops.size() >= MAX_STOPS_PER_ROUTE:
		status_text = "Prototype limit: max %d stops per route." % MAX_STOPS_PER_ROUTE
		return
	else:
		route_stops.append(stop_index)
		status_text = "Added %s to Route %d" % [stops[stop_index]["name"], active_route + 1]
	routes[active_route]["stops"] = route_stops
	_respawn_route_buses(active_route)

func _change_bus_count(delta: int) -> void:
	var current: int = routes[active_route]["bus_count"]
	if delta > 0:
		if routes[active_route]["stops"].size() < 2:
			status_text = "A route needs at least 2 stops before adding a bus."
			return
		if _total_bus_count() >= MAX_TOTAL_BUSES:
			status_text = "Prototype fleet limit: %d buses total." % MAX_TOTAL_BUSES
			return
		current += 1
	else:
		current = max(0, current - 1)
	routes[active_route]["bus_count"] = current
	_respawn_route_buses(active_route)
	status_text = "Route %d now has %d bus(es)." % [active_route + 1, current]

func _total_bus_count() -> int:
	var result := 0
	for route in routes:
		result += route["bus_count"]
	return result

func _toggle_simulation() -> void:
	if not sim_running and _total_bus_count() == 0:
		status_text = "Add at least one bus first."
		return
	sim_running = not sim_running
	status_text = "Simulation running." if sim_running else "Simulation paused."

func _reset_prototype() -> void:
	for i in range(stops.size()):
		stops[i]["waiting"] = {}
	for i in range(routes.size()):
		routes[i]["stops"] = []
		routes[i]["bus_count"] = 0
	buses.clear()
	active_route = 0
	sim_running = false
	sim_minutes = 6.0 * 60.0
	day = 1
	delivered = 0
	total_spawned = 0
	spawn_accumulator = 0.0
	status_text = "Reset. Build routes, add buses, then press Start."

func _spawn_passengers() -> void:
	var hour := sim_minutes / 60.0
	var pairs := []
	var amount := 1
	if hour >= 6.5 and hour < 9.5:
		pairs = [[0,2],[0,4],[0,1],[6,2],[6,4],[6,1],[8,4]]
		amount = 2
	elif hour >= 9.5 and hour < 16.0:
		pairs = [[0,3],[6,3],[2,3],[3,7],[4,5],[4,7],[8,3],[5,4]]
	elif hour >= 16.0 and hour < 20.5:
		pairs = [[2,0],[2,6],[4,0],[4,6],[1,0],[1,6],[3,0],[3,6],[5,4]]
		amount = 2
	else:
		pairs = [[0,4],[6,4],[3,0],[3,6],[4,0],[4,6],[7,4]]
	for n in range(amount):
		var pair: Array = pairs[randi() % pairs.size()]
		_add_waiting_passenger(pair[0], pair[1])

func _add_waiting_passenger(origin: int, destination: int) -> void:
	var waiting: Dictionary = stops[origin]["waiting"]
	waiting[destination] = int(waiting.get(destination, 0)) + 1
	stops[origin]["waiting"] = waiting
	total_spawned += 1

func _respawn_route_buses(route_index: int) -> void:
	for i in range(buses.size() - 1, -1, -1):
		if buses[i]["route"] == route_index:
			buses.remove_at(i)
	var route_stops: Array = routes[route_index]["stops"]
	var count: int = routes[route_index]["bus_count"]
	if route_stops.size() < 2:
		return
	for i in range(count):
		var start_slot := int(floor(float(i) * float(route_stops.size()) / max(1.0, float(count))))
		start_slot = clamp(start_slot, 0, route_stops.size() - 1)
		var direction := 1 if i % 2 == 0 else -1
		if start_slot == 0:
			direction = 1
		elif start_slot == route_stops.size() - 1:
			direction = -1
		var bus := {
			"route": route_index,
			"slot": start_slot,
			"direction": direction,
			"pos": road_points[stops[route_stops[start_slot]]["node"]],
			"path": [],
			"path_cursor": 1,
			"target_slot": start_slot,
			"onboard": [],
			"speed": 85.0
		}
		_setup_next_leg(bus)
		buses.append(bus)

func _setup_next_leg(bus: Dictionary) -> void:
	var route_stops: Array = routes[bus["route"]]["stops"]
	if route_stops.size() < 2:
		bus["path"] = []
		return
	var next_slot: int = bus["slot"] + bus["direction"]
	if next_slot >= route_stops.size():
		bus["direction"] = -1
		next_slot = bus["slot"] - 1
	elif next_slot < 0:
		bus["direction"] = 1
		next_slot = bus["slot"] + 1
	bus["target_slot"] = next_slot
	var from_node: int = stops[route_stops[bus["slot"]]]["node"]
	var to_node: int = stops[route_stops[next_slot]]["node"]
	var node_path := _shortest_path_nodes(from_node, to_node)
	var positions := []
	for node_id in node_path:
		positions.append(road_points[node_id])
	bus["path"] = positions
	bus["path_cursor"] = 1

func _update_buses(delta: float) -> void:
	for bus in buses:
		var path: Array = bus["path"]
		if path.size() < 2:
			continue
		var cursor: int = bus["path_cursor"]
		if cursor >= path.size():
			_arrive_at_route_stop(bus)
			continue
		var target: Vector2 = path[cursor]
		var pos: Vector2 = bus["pos"]
		var step: float = bus["speed"] * delta
		if pos.distance_to(target) <= step:
			bus["pos"] = target
			bus["path_cursor"] = cursor + 1
			if bus["path_cursor"] >= path.size():
				_arrive_at_route_stop(bus)
		else:
			bus["pos"] = pos.move_toward(target, step)

func _arrive_at_route_stop(bus: Dictionary) -> void:
	bus["slot"] = bus["target_slot"]
	var route_stops: Array = routes[bus["route"]]["stops"]
	var stop_index: int = route_stops[bus["slot"]]
	_service_stop(bus, stop_index)
	_setup_next_leg(bus)

func _service_stop(bus: Dictionary, stop_index: int) -> void:
	var onboard: Array = bus["onboard"]
	for i in range(onboard.size() - 1, -1, -1):
		if onboard[i] == stop_index:
			onboard.remove_at(i)
			delivered += 1

	var route_stops: Array = routes[bus["route"]]["stops"]
	var waiting: Dictionary = stops[stop_index]["waiting"]
	var destinations := waiting.keys()
	for destination in destinations:
		if onboard.size() >= BUS_CAPACITY:
			break
		if not route_stops.has(destination):
			continue
		var count: int = waiting[destination]
		while count > 0 and onboard.size() < BUS_CAPACITY:
			onboard.append(destination)
			count -= 1
		waiting[destination] = count
	stops[stop_index]["waiting"] = waiting
	bus["onboard"] = onboard

func _shortest_path_nodes(start_node: int, end_node: int) -> Array:
	if start_node == end_node:
		return [start_node]
	var dist := {}
	var prev := {}
	var unvisited := []
	for i in range(road_points.size()):
		dist[i] = INF
		prev[i] = -1
		unvisited.append(i)
	dist[start_node] = 0.0
	while not unvisited.is_empty():
		var best_index := 0
		var current: int = unvisited[0]
		for i in range(1, unvisited.size()):
			if dist[unvisited[i]] < dist[current]:
				current = unvisited[i]
				best_index = i
		unvisited.remove_at(best_index)
		if current == end_node:
			break
		for neighbor in adjacency[current]:
			if not unvisited.has(neighbor):
				continue
			var alt: float = dist[current] + road_points[current].distance_to(road_points[neighbor])
			if alt < dist[neighbor]:
				dist[neighbor] = alt
				prev[neighbor] = current
	var path := []
	var cursor := end_node
	while cursor != -1:
		path.push_front(cursor)
		if cursor == start_node:
			break
		cursor = prev[cursor]
	if path.is_empty() or path[0] != start_node:
		return [start_node, end_node]
	return path

func _waiting_at_stop(stop_index: int) -> int:
	var total := 0
	for count in stops[stop_index]["waiting"].values():
		total += int(count)
	return total

func _total_waiting() -> int:
	var total := 0
	for i in range(stops.size()):
		total += _waiting_at_stop(i)
	return total

func _rating() -> int:
	return clamp(100 - int(_total_waiting() * 0.55), 0, 100)

func _draw() -> void:
	_draw_background()
	_draw_routes()
	_draw_buses()
	_draw_stops()
	_draw_hud()

func _draw_background() -> void:
	for rect in buildings:
		draw_rect(rect, Color("#d8cdb9"), true)
		draw_rect(rect, Color("#b8ad9b"), false, 2.0)
	for edge in road_edges:
		var a: Vector2 = road_points[edge[0]]
		var b: Vector2 = road_points[edge[1]]
		draw_line(a, b, Color("#d2d2cf"), 22.0, true)
		draw_line(a, b, Color("#f4f1e9"), 15.0, true)

func _draw_routes() -> void:
	for route_index in range(routes.size()):
		var route_stops: Array = routes[route_index]["stops"]
		if route_stops.size() < 2:
			continue
		for i in range(route_stops.size() - 1):
			var from_node: int = stops[route_stops[i]]["node"]
			var to_node: int = stops[route_stops[i + 1]]["node"]
			var node_path := _shortest_path_nodes(from_node, to_node)
			var points := PackedVector2Array()
			for node_id in node_path:
				points.append(road_points[node_id])
			if points.size() >= 2:
				draw_polyline(points, route_colors[route_index], 7.0, true)

func _draw_buses() -> void:
	for bus in buses:
		var pos: Vector2 = bus["pos"]
		var color: Color = route_colors[bus["route"]]
		draw_rect(Rect2(pos - Vector2(8, 5), Vector2(16, 10)), color, true)
		draw_rect(Rect2(pos - Vector2(8, 5), Vector2(16, 10)), Color("#343434"), false, 1.5)
		var load_text := "%d" % bus["onboard"].size()
		draw_string(font, pos + Vector2(-5, -9), load_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#343434"))

func _draw_stops() -> void:
	for i in range(stops.size()):
		var pos: Vector2 = road_points[stops[i]["node"]]
		var waiting := _waiting_at_stop(i)
		if waiting > 0:
			var halo_radius := 17.0 + min(18.0, waiting * 0.35)
			draw_circle(pos, halo_radius, Color(0.88, 0.32, 0.30, 0.16))
		draw_circle(pos, 11.0, Color("#fffdf7"))
		draw_arc(pos, 11.0, 0, TAU, 32, Color("#383838"), 2.0, true)
		draw_string(font, pos + Vector2(-30, -18), stops[i]["name"], HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color("#343434"))
		if waiting > 0:
			draw_string(font, pos + Vector2(-12, 30), "%d" % waiting, HORIZONTAL_ALIGNMENT_CENTER, 24, 13, Color("#b54545"))

func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, 1280, 78), Color(0.96, 0.95, 0.91, 0.96), true)
	draw_line(Vector2(0,78), Vector2(1280,78), Color("#c9c2b6"), 1.0)
	var hour := int(sim_minutes / 60.0) % 24
	var minute := int(sim_minutes) % 60
	var time_text := "Day %d   %02d:%02d" % [day, hour, minute]
	draw_string(font, Vector2(22, 31), "BUS MASTER — ROUTE TEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#2f3437"))
	draw_string(font, Vector2(22, 58), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#555b60"))
	draw_string(font, Vector2(285, 33), "Waiting  %d" % _total_waiting(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#555b60"))
	draw_string(font, Vector2(440, 33), "Delivered  %d" % delivered, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#555b60"))
	draw_string(font, Vector2(610, 33), "Rating  %d" % _rating(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#555b60"))
	draw_string(font, Vector2(755, 33), "Fleet  %d/%d" % [_total_bus_count(), MAX_TOTAL_BUSES], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#555b60"))
	draw_string(font, Vector2(22, 640), status_text, HORIZONTAL_ALIGNMENT_LEFT, 1200, 14, Color("#4b5054"))

	var rects := _button_rects()
	for i in range(3):
		var fill := route_colors[i] if active_route == i else Color("#e4e0d8")
		draw_rect(rects[i], fill, true)
		draw_rect(rects[i], Color("#595959"), false, 1.5)
		draw_string(font, rects[i].position + Vector2(12, 26), "Route %d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#303030"))

	_draw_button(rects[3], "- Bus")
	_draw_button(rects[4], "+ Bus")
	_draw_button(rects[5], "Pause" if sim_running else "Start")
	_draw_button(rects[6], "Reset")
	var route_info := "R%d: %d stops / %d buses" % [active_route + 1, routes[active_route]["stops"].size(), routes[active_route]["bus_count"]]
	draw_string(font, Vector2(850, 688), route_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#4b5054"))

func _draw_button(rect: Rect2, label: String) -> void:
	draw_rect(rect, Color("#e8e4dc"), true)
	draw_rect(rect, Color("#595959"), false, 1.5)
	draw_string(font, rect.position + Vector2(13, 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#303030"))
