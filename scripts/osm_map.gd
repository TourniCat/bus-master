extends Node2D

const BUILD: String = "0.4.0-topology-puzzle"
const OVERPASS_URL: String = "https://overpass-api.de/api/interpreter"
const CACHE_PATH: String = "user://bus_master_gangnam_topology_v4.json"

const MAP_RECT := Rect2(24, 72, 952, 624)
const PANEL_X: float = 1000.0
const BG_COLOR := Color("#f3f1ea")

const SOUTH: float = 37.4938
const WEST: float = 127.0225
const NORTH: float = 37.5019
const EAST: float = 127.0328
const AREA_NAME: String = "Gangnam Station"

const PUZZLE_NODE_COUNT: int = 10
const INITIAL_ACTIVE_NODES: int = 3
const MAX_ROUTES: int = 3
const MAX_STOPS_PER_ROUTE: int = 5
const ROUTE_SERVICE_PER_TICK: int = 2
const FAIL_WAITING: int = 16
const TICK_SECONDS: float = 0.75

const MIN_ZOOM: float = 0.9
const MAX_ZOOM: float = 2.5
const DEFAULT_ZOOM: float = 1.0
const ZOOM_STEP: float = 1.15

var font: Font
var http: HTTPRequest
var road_graph := AStar2D.new()
var puzzle_graph := AStar2D.new()

var loading: bool = true
var error_text: String = ""
var loaded_from_cache: bool = false

var road_positions: Array[Vector2] = []
var osm_node_to_local: Dictionary = {}
var building_samples: Array[Dictionary] = []
var pois: Array[Dictionary] = []

var puzzle_nodes: Array[Dictionary] = []
var puzzle_edges: Array[Dictionary] = []
var routes: Array[Array] = []
var active_route: int = 0

var game_started: bool = false
var game_paused: bool = false
var game_over: bool = false
var delivered: int = 0
var elapsed_ticks: int = 0
var tick_accumulator: float = 0.0
var animation_time: float = 0.0
var status_text: String = "Loading city topology..."

var view_zoom: float = DEFAULT_ZOOM
var view_offset: Vector2 = Vector2.ZERO
var panning: bool = false

var route_colors: Array[Color] = [
	Color("#df626a"),
	Color("#4f82ce"),
	Color("#58a16c")
]


func _ready() -> void:
	font = ThemeDB.fallback_font
	_reset_routes()
	http = HTTPRequest.new()
	http.timeout = 40.0
	add_child(http)
	http.request_completed.connect(_on_request_completed)
	_log("START build=%s godot=%s" % [
		BUILD, String(Engine.get_version_info().get("string", "unknown"))
	])
	_load_map(false)


func _process(delta: float) -> void:
	animation_time += delta
	if game_started and not game_paused and not game_over and not loading:
		tick_accumulator += delta
		while tick_accumulator >= TICK_SECONDS:
			tick_accumulator -= TICK_SECONDS
			_simulation_tick()
	queue_redraw()


func _log(message: String) -> void:
	print("[BUS_MASTER] %s" % message)


func _load_map(force_network: bool) -> void:
	loading = true
	error_text = ""
	loaded_from_cache = false
	status_text = "Reading OpenStreetMap behind the scenes..."
	_clear_source_data()

	if not force_network and FileAccess.file_exists(CACHE_PATH):
		var file: FileAccess = FileAccess.open(CACHE_PATH, FileAccess.READ)
		if file != null:
			var text: String = file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary:
				loaded_from_cache = true
				_log("OSM cache hit")
				_parse_osm(parsed)
				return

	_request_osm()


func _request_osm() -> void:
	var bbox: String = "%f,%f,%f,%f" % [SOUTH, WEST, NORTH, EAST]
	var query: String = """
[out:json][timeout:25];
(
  way["highway"](%s);
  way["building"](%s);
  way["amenity"](%s);
  way["shop"](%s);
  way["tourism"](%s);
  way["railway"="station"](%s);
  node["amenity"](%s);
  node["shop"](%s);
  node["tourism"](%s);
  node["railway"="station"](%s);
);
out geom;
""" % [bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox]

	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"User-Agent: BusMasterPrototype/0.4"
	])
	var body_text: String = "data=" + query.uri_encode()
	var request_error: Error = http.request(
		OVERPASS_URL, headers, HTTPClient.METHOD_POST, body_text
	)
	if request_error != OK:
		loading = false
		error_text = "Could not start OSM request: %d" % int(request_error)
		status_text = error_text
		_log("OSM request start error=%d" % int(request_error))
	else:
		_log("OSM request bbox=%s" % bbox)


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		loading = false
		error_text = "OSM request failed: result=%d HTTP=%d" % [result, response_code]
		status_text = error_text
		_log("OSM request failed result=%d http=%d" % [result, response_code])
		queue_redraw()
		return

	var text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		loading = false
		error_text = "OSM returned invalid JSON."
		status_text = error_text
		queue_redraw()
		return

	var file: FileAccess = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

	_log("OSM download bytes=%d" % body.size())
	_parse_osm(parsed)


func _clear_source_data() -> void:
	road_positions.clear()
	osm_node_to_local.clear()
	building_samples.clear()
	pois.clear()
	puzzle_nodes.clear()
	puzzle_edges.clear()
	road_graph.clear()
	puzzle_graph.clear()


func _parse_osm(root_variant: Variant) -> void:
	if not (root_variant is Dictionary):
		_fail_parse("Invalid OSM root.")
		return

	var root: Dictionary = root_variant
	var elements_variant: Variant = root.get("elements", [])
	if not (elements_variant is Array):
		_fail_parse("OSM has no elements array.")
		return

	var elements: Array = elements_variant
	for value in elements:
		if not (value is Dictionary):
			continue
		var element: Dictionary = value
		var type_name: String = String(element.get("type", ""))
		var tags_variant: Variant = element.get("tags", {})
		var tags: Dictionary = {}
		if tags_variant is Dictionary:
			tags = tags_variant

		if type_name == "way":
			if tags.has("highway"):
				_parse_road(element)
			elif tags.has("building"):
				_parse_building(element, tags)
			else:
				_parse_way_poi(element, tags)
		elif type_name == "node":
			_parse_node_poi(element, tags)

	if road_positions.size() < 2:
		_fail_parse("Not enough drivable roads in this area.")
		return

	_generate_puzzle_graph()
	if puzzle_nodes.size() < 5:
		_fail_parse("Could not extract enough puzzle nodes.")
		return

	loading = false
	_reset_run()
	status_text = "Route 1 selected — connect the 3 active stops, then press START."
	_log("TOPOLOGY ready road_nodes=%d buildings=%d poi=%d puzzle_nodes=%d edges=%d cache=%s" % [
		road_positions.size(), building_samples.size(), pois.size(),
		puzzle_nodes.size(), puzzle_edges.size(), str(loaded_from_cache)
	])
	queue_redraw()


func _fail_parse(message: String) -> void:
	loading = false
	error_text = message
	status_text = message
	_log("PARSE ERROR: %s" % message)
	queue_redraw()


func _parse_road(element: Dictionary) -> void:
	var geom_variant: Variant = element.get("geometry", [])
	var ids_variant: Variant = element.get("nodes", [])
	if not (geom_variant is Array) or not (ids_variant is Array):
		return

	var geom: Array = geom_variant
	var ids: Array = ids_variant
	var count: int = mini(geom.size(), ids.size())
	if count < 2:
		return

	var local_ids: Array[int] = []
	for i in range(count):
		if not (geom[i] is Dictionary):
			local_ids.append(-1)
			continue
		var point: Dictionary = geom[i]
		if not point.has("lat") or not point.has("lon"):
			local_ids.append(-1)
			continue
		var osm_id: int = int(ids[i])
		var local_id: int = _road_node(
			osm_id,
			_project(float(point["lat"]), float(point["lon"]))
		)
		local_ids.append(local_id)

	for i in range(1, local_ids.size()):
		var a: int = local_ids[i - 1]
		var b: int = local_ids[i]
		if a < 0 or b < 0 or a == b:
			continue
		if not road_graph.are_points_connected(a, b):
			road_graph.connect_points(a, b, true)


func _road_node(osm_id: int, pos: Vector2) -> int:
	if osm_node_to_local.has(osm_id):
		return int(osm_node_to_local[osm_id])
	var id: int = road_positions.size()
	osm_node_to_local[osm_id] = id
	road_positions.append(pos)
	road_graph.add_point(id, pos)
	return id


func _parse_building(element: Dictionary, tags: Dictionary) -> void:
	var polygon: PackedVector2Array = _geometry_polygon(element)
	if polygon.size() < 3:
		return
	var center: Vector2 = _polygon_center(polygon)
	var building_type: String = String(tags.get("building", ""))
	var kind: String = "generic"
	if building_type in ["apartments", "residential", "house", "detached", "terrace", "dormitory", "semidetached_house"]:
		kind = "residential"
	elif building_type in ["office", "commercial", "retail", "hotel"]:
		kind = "work"
	building_samples.append({"pos": center, "kind": kind})
	_append_poi_from_tags(center, tags)


func _parse_way_poi(element: Dictionary, tags: Dictionary) -> void:
	var polygon: PackedVector2Array = _geometry_polygon(element)
	if polygon.is_empty():
		return
	_append_poi_from_tags(_polygon_center(polygon), tags)


func _parse_node_poi(element: Dictionary, tags: Dictionary) -> void:
	if not element.has("lat") or not element.has("lon"):
		return
	var pos: Vector2 = _project(float(element["lat"]), float(element["lon"]))
	_append_poi_from_tags(pos, tags)


func _append_poi_from_tags(pos: Vector2, tags: Dictionary) -> void:
	var amenity: String = String(tags.get("amenity", ""))
	var shop: String = String(tags.get("shop", ""))
	var tourism: String = String(tags.get("tourism", ""))
	var railway: String = String(tags.get("railway", ""))
	var kind: String = ""

	if railway == "station" or amenity in ["bus_station", "ferry_terminal"]:
		kind = "hub"
	elif amenity in ["school", "college", "university", "kindergarten"]:
		kind = "education"
	elif not shop.is_empty() or amenity in ["marketplace", "cinema", "theatre", "restaurant", "cafe", "fast_food"]:
		kind = "commercial"
	elif not tourism.is_empty():
		kind = "leisure"
	elif amenity in ["hospital", "clinic", "doctors"]:
		kind = "service"
	else:
		return

	pois.append({
		"pos": pos,
		"kind": kind,
		"name": String(tags.get("name", kind))
	})


func _geometry_polygon(element: Dictionary) -> PackedVector2Array:
	var geom_variant: Variant = element.get("geometry", [])
	if not (geom_variant is Array):
		return PackedVector2Array()
	var polygon := PackedVector2Array()
	for point_value in geom_variant:
		if point_value is Dictionary:
			var point: Dictionary = point_value
			if point.has("lat") and point.has("lon"):
				polygon.append(_project(float(point["lat"]), float(point["lon"])))
	return polygon


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return MAP_RECT.get_center()
	var total := Vector2.ZERO
	for point in polygon:
		total += point
	return total / float(polygon.size())


func _project(lat: float, lon: float) -> Vector2:
	var x: float = (lon - WEST) / (EAST - WEST)
	var y: float = 1.0 - ((lat - SOUTH) / (NORTH - SOUTH))
	return MAP_RECT.position + Vector2(x * MAP_RECT.size.x, y * MAP_RECT.size.y)


func _generate_puzzle_graph() -> void:
	puzzle_nodes.clear()
	puzzle_edges.clear()
	puzzle_graph.clear()

	var selected_graph_ids: Array[int] = []
	var hub_id: int = _best_poi_graph_id(["hub"], selected_graph_ids)
	if hub_id < 0:
		hub_id = _nearest_road_node(MAP_RECT.get_center())
	_add_puzzle_node(hub_id, "hub", _best_poi_label_near(hub_id, "Transit Hub"))
	selected_graph_ids.append(hub_id)

	var home_id: int = _best_building_graph_id("residential", selected_graph_ids)
	if home_id < 0:
		home_id = _farthest_road_node(selected_graph_ids)
	_add_puzzle_node(home_id, "residential", "Home")
	selected_graph_ids.append(home_id)

	var commercial_id: int = _best_poi_graph_id(["commercial", "leisure"], selected_graph_ids)
	if commercial_id < 0:
		commercial_id = _farthest_road_node(selected_graph_ids)
	_add_puzzle_node(commercial_id, "commercial", "Shops")
	selected_graph_ids.append(commercial_id)

	var education_id: int = _best_poi_graph_id(["education"], selected_graph_ids)
	if education_id < 0:
		education_id = _farthest_road_node(selected_graph_ids)
	_add_puzzle_node(education_id, "education", "School")
	selected_graph_ids.append(education_id)

	var work_id: int = _best_building_graph_id("work", selected_graph_ids)
	if work_id < 0:
		work_id = _farthest_road_node(selected_graph_ids)
	_add_puzzle_node(work_id, "work", "Work")
	selected_graph_ids.append(work_id)

	var extra_kinds: Array[String] = ["residential", "service", "commercial", "work", "leisure"]
	var extras_needed: int = PUZZLE_NODE_COUNT - puzzle_nodes.size()
	for i in range(extras_needed):
		var graph_id: int = _farthest_road_node(selected_graph_ids)
		if graph_id < 0:
			break
		var kind: String = extra_kinds[i % extra_kinds.size()]
		_add_puzzle_node(graph_id, kind, _default_label(kind, i + 2))
		selected_graph_ids.append(graph_id)

	_relax_puzzle_layout()
	_build_puzzle_edges()


func _add_puzzle_node(graph_id: int, kind: String, label: String) -> void:
	if graph_id < 0 or graph_id >= road_positions.size():
		return
	puzzle_nodes.append({
		"graph_id": graph_id,
		"source_pos": road_positions[graph_id],
		"pos": road_positions[graph_id],
		"kind": kind,
		"label": label,
		"active": false,
		"waiting": {},
		"threshold": 0
	})


func _best_poi_graph_id(kinds: Array[String], avoid: Array[int]) -> int:
	var best_id: int = -1
	var best_score: float = -INF
	for poi in pois:
		if not kinds.has(String(poi.get("kind", ""))):
			continue
		var graph_id: int = _nearest_road_node(poi["pos"])
		if graph_id < 0 or avoid.has(graph_id):
			continue
		var separation: float = _graph_separation_score(graph_id, avoid)
		if separation > best_score:
			best_score = separation
			best_id = graph_id
	return best_id


func _best_building_graph_id(kind: String, avoid: Array[int]) -> int:
	var best_id: int = -1
	var best_score: float = -INF
	for sample in building_samples:
		if String(sample.get("kind", "")) != kind:
			continue
		var pos: Vector2 = sample["pos"]
		var graph_id: int = _nearest_road_node(pos)
		if graph_id < 0 or avoid.has(graph_id):
			continue
		var density: float = 0.0
		for other in building_samples:
			if String(other.get("kind", "")) == kind:
				var other_pos: Vector2 = other["pos"]
				if pos.distance_to(other_pos) < 120.0:
					density += 1.0
		var score: float = density + _graph_separation_score(graph_id, avoid) * 0.02
		if score > best_score:
			best_score = score
			best_id = graph_id
	return best_id


func _farthest_road_node(avoid: Array[int]) -> int:
	var best_id: int = -1
	var best_score: float = -INF
	var stride: int = maxi(1, int(road_positions.size() / 450))
	for i in range(0, road_positions.size(), stride):
		if avoid.has(i):
			continue
		var pos: Vector2 = road_positions[i]
		if not MAP_RECT.grow(-42.0).has_point(pos):
			continue
		var min_distance: float = INF
		for blocked in avoid:
			if blocked >= 0 and blocked < road_positions.size():
				min_distance = minf(min_distance, pos.distance_to(road_positions[blocked]))
		if avoid.is_empty():
			min_distance = pos.distance_to(MAP_RECT.get_center())
		if min_distance > best_score:
			best_score = min_distance
			best_id = i
	return best_id


func _graph_separation_score(graph_id: int, avoid: Array[int]) -> float:
	if avoid.is_empty():
		return 200.0
	var pos: Vector2 = road_positions[graph_id]
	var min_distance: float = INF
	for blocked in avoid:
		if blocked >= 0 and blocked < road_positions.size():
			min_distance = minf(min_distance, pos.distance_to(road_positions[blocked]))
	return min_distance


func _nearest_road_node(pos: Vector2) -> int:
	var best_id: int = -1
	var best_distance: float = INF
	for i in range(road_positions.size()):
		var distance: float = pos.distance_to(road_positions[i])
		if distance < best_distance:
			best_distance = distance
			best_id = i
	return best_id


func _best_poi_label_near(graph_id: int, fallback: String) -> String:
	if graph_id < 0:
		return fallback
	var pos: Vector2 = road_positions[graph_id]
	var best_name: String = fallback
	var best_distance: float = INF
	for poi in pois:
		if String(poi.get("kind", "")) != "hub":
			continue
		var distance: float = pos.distance_to(poi["pos"])
		if distance < best_distance:
			best_distance = distance
			var candidate: String = String(poi.get("name", fallback))
			if not candidate.is_empty() and candidate != "hub":
				best_name = candidate
	return best_name


func _default_label(kind: String, index: int) -> String:
	match kind:
		"residential":
			return "Home %d" % index
		"commercial":
			return "Shops %d" % index
		"work":
			return "Work %d" % index
		"education":
			return "School %d" % index
		"service":
			return "Service %d" % index
		"leisure":
			return "Leisure %d" % index
		_:
			return "Stop %d" % index


func _relax_puzzle_layout() -> void:
	if puzzle_nodes.size() < 2:
		return
	var bounds: Rect2 = MAP_RECT.grow(-70.0)
	for _iteration in range(28):
		var deltas: Array[Vector2] = []
		for _i in range(puzzle_nodes.size()):
			deltas.append(Vector2.ZERO)

		for i in range(puzzle_nodes.size()):
			for j in range(i + 1, puzzle_nodes.size()):
				var a: Vector2 = puzzle_nodes[i]["pos"]
				var b: Vector2 = puzzle_nodes[j]["pos"]
				var diff: Vector2 = a - b
				var distance: float = maxf(diff.length(), 0.01)
				if distance < 105.0:
					var push: Vector2 = diff.normalized() * ((105.0 - distance) * 0.12)
					deltas[i] += push
					deltas[j] -= push

		for i in range(puzzle_nodes.size()):
			var current: Vector2 = puzzle_nodes[i]["pos"]
			var source: Vector2 = puzzle_nodes[i]["source_pos"]
			var next_pos: Vector2 = current + deltas[i] + (source - current) * 0.035
			next_pos.x = clampf(next_pos.x, bounds.position.x, bounds.end.x)
			next_pos.y = clampf(next_pos.y, bounds.position.y, bounds.end.y)
			puzzle_nodes[i]["pos"] = next_pos


func _build_puzzle_edges() -> void:
	puzzle_edges.clear()
	puzzle_graph.clear()
	for i in range(puzzle_nodes.size()):
		puzzle_graph.add_point(i, puzzle_nodes[i]["pos"])

	if puzzle_nodes.size() < 2:
		return

	var visited: Dictionary = {0: true}
	while visited.size() < puzzle_nodes.size():
		var best_a: int = -1
		var best_b: int = -1
		var best_distance: float = INF
		for a in range(puzzle_nodes.size()):
			if not visited.has(a):
				continue
			for b in range(puzzle_nodes.size()):
				if visited.has(b) or a == b:
					continue
				var distance: float = _road_distance_between_puzzle_nodes(a, b)
				if distance < best_distance:
					best_distance = distance
					best_a = a
					best_b = b
		if best_a < 0 or best_b < 0:
			break
		_add_puzzle_edge(best_a, best_b, best_distance)
		visited[best_b] = true

	var target_edges: int = mini(puzzle_nodes.size() + 4, int(puzzle_nodes.size() * (puzzle_nodes.size() - 1) / 2))
	while puzzle_edges.size() < target_edges:
		var best_a: int = -1
		var best_b: int = -1
		var best_distance: float = INF
		for a in range(puzzle_nodes.size()):
			for b in range(a + 1, puzzle_nodes.size()):
				if _edge_exists(a, b):
					continue
				var distance: float = _road_distance_between_puzzle_nodes(a, b)
				if distance < best_distance:
					best_distance = distance
					best_a = a
					best_b = b
		if best_a < 0 or best_b < 0 or best_distance == INF:
			break
		_add_puzzle_edge(best_a, best_b, best_distance)

	while puzzle_edges.size() < puzzle_nodes.size() - 1:
		var best_a: int = -1
		var best_b: int = -1
		var best_distance: float = INF
		for a in range(puzzle_nodes.size()):
			for b in range(a + 1, puzzle_nodes.size()):
				if _edge_exists(a, b):
					continue
				var pa: Vector2 = puzzle_nodes[a]["pos"]
				var pb: Vector2 = puzzle_nodes[b]["pos"]
				var distance: float = pa.distance_to(pb)
				if distance < best_distance:
					best_distance = distance
					best_a = a
					best_b = b
		if best_a < 0:
			break
		_add_puzzle_edge(best_a, best_b, best_distance)


func _road_distance_between_puzzle_nodes(a: int, b: int) -> float:
	var ga: int = int(puzzle_nodes[a]["graph_id"])
	var gb: int = int(puzzle_nodes[b]["graph_id"])
	var path: PackedVector2Array = road_graph.get_point_path(ga, gb)
	if path.size() < 2:
		return INF
	var total: float = 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


func _add_puzzle_edge(a: int, b: int, distance: float) -> void:
	if a < 0 or b < 0 or a == b or _edge_exists(a, b):
		return
	puzzle_edges.append({"a": a, "b": b, "distance": distance})
	if not puzzle_graph.are_points_connected(a, b):
		puzzle_graph.connect_points(a, b, true)


func _edge_exists(a: int, b: int) -> bool:
	for edge in puzzle_edges:
		var ea: int = int(edge["a"])
		var eb: int = int(edge["b"])
		if (ea == a and eb == b) or (ea == b and eb == a):
			return true
	return false


func _reset_routes() -> void:
	routes.clear()
	for _i in range(MAX_ROUTES):
		routes.append([])


func _reset_run() -> void:
	_reset_routes()
	active_route = 0
	game_started = false
	game_paused = false
	game_over = false
	delivered = 0
	elapsed_ticks = 0
	tick_accumulator = 0.0

	var thresholds: Array[int] = [0, 0, 0, 18, 40, 70, 110, 160, 220, 300]
	for i in range(puzzle_nodes.size()):
		puzzle_nodes[i]["active"] = i < INITIAL_ACTIVE_NODES
		puzzle_nodes[i]["waiting"] = {}
		puzzle_nodes[i]["threshold"] = thresholds[mini(i, thresholds.size() - 1)]

	status_text = "Route 1 selected — connect the 3 active stops, then press START."
	queue_redraw()


func _simulation_tick() -> void:
	elapsed_ticks += 1
	_spawn_demand()
	_service_routes()
	_reveal_nodes()
	_check_game_over()


func _spawn_demand() -> void:
	var active_ids: Array[int] = _active_node_ids()
	if active_ids.size() < 2:
		return

	var spawn_count: int = 1
	if elapsed_ticks > 30:
		spawn_count = 2
	if elapsed_ticks > 90:
		spawn_count = 3
	if elapsed_ticks > 180:
		spawn_count = 4

	for _n in range(spawn_count):
		var origin: int = active_ids[int(randi() % active_ids.size())]
		var destination: int = origin
		var guard: int = 0
		while destination == origin and guard < 12:
			destination = active_ids[int(randi() % active_ids.size())]
			guard += 1
		if destination == origin:
			continue

		var waiting: Dictionary = puzzle_nodes[origin]["waiting"]
		waiting[destination] = int(waiting.get(destination, 0)) + 1
		puzzle_nodes[origin]["waiting"] = waiting


func _service_routes() -> void:
	for route_index in range(routes.size()):
		if not _route_unlocked(route_index):
			continue
		var route: Array = routes[route_index]
		if route.size() < 2:
			continue

		var capacity: int = ROUTE_SERVICE_PER_TICK
		for origin_value in route:
			if capacity <= 0:
				break
			var origin: int = int(origin_value)
			var waiting: Dictionary = puzzle_nodes[origin]["waiting"]
			var destinations: Array = waiting.keys()
			for destination_value in destinations:
				if capacity <= 0:
					break
				var destination: int = int(destination_value)
				if not route.has(destination):
					continue
				var count: int = int(waiting.get(destination, 0))
				if count <= 0:
					continue
				var moved: int = mini(count, capacity)
				count -= moved
				capacity -= moved
				delivered += moved
				if count <= 0:
					waiting.erase(destination)
				else:
					waiting[destination] = count
			puzzle_nodes[origin]["waiting"] = waiting


func _reveal_nodes() -> void:
	for i in range(INITIAL_ACTIVE_NODES, puzzle_nodes.size()):
		if bool(puzzle_nodes[i]["active"]):
			continue
		var threshold: int = int(puzzle_nodes[i]["threshold"])
		if delivered >= threshold:
			puzzle_nodes[i]["active"] = true
			status_text = "NEW STOP — %s. Extend or create a route." % String(puzzle_nodes[i]["label"])
			_log("REVEAL node=%d label=%s delivered=%d" % [i, String(puzzle_nodes[i]["label"]), delivered])


func _check_game_over() -> void:
	for i in range(puzzle_nodes.size()):
		if not bool(puzzle_nodes[i]["active"]):
			continue
		var total_waiting: int = _node_waiting_total(i)
		if total_waiting >= FAIL_WAITING:
			game_over = true
			game_paused = false
			status_text = "OVERLOAD — %s collapsed. Try a different network." % String(puzzle_nodes[i]["label"])
			_log("GAME_OVER delivered=%d node=%s waiting=%d" % [delivered, String(puzzle_nodes[i]["label"]), total_waiting])
			return


func _active_node_ids() -> Array[int]:
	var result: Array[int] = []
	for i in range(puzzle_nodes.size()):
		if bool(puzzle_nodes[i]["active"]):
			result.append(i)
	return result


func _node_waiting_total(node_id: int) -> int:
	var total: int = 0
	var waiting: Dictionary = puzzle_nodes[node_id]["waiting"]
	for value in waiting.values():
		total += int(value)
	return total


func _route_unlocked(route_index: int) -> bool:
	match route_index:
		0:
			return true
		1:
			return delivered >= 28
		2:
			return delivered >= 95
		_:
			return false


func _can_start() -> bool:
	if routes.is_empty():
		return false
	var route: Array = routes[0]
	if route.size() < 2:
		return false
	var connected_active: int = 0
	for node_id in range(mini(INITIAL_ACTIVE_NODES, puzzle_nodes.size())):
		if route.has(node_id):
			connected_active += 1
	return connected_active >= 2


func _toggle_start_pause() -> void:
	if game_over:
		_reset_run()
		return
	if not game_started:
		if not _can_start():
			status_text = "Route 1 must connect at least 2 of the 3 starting stops."
			return
		game_started = true
		game_paused = false
		status_text = "RUNNING — watch queues and redraw routes before a stop overloads."
		_log("START_RUN")
	else:
		game_paused = not game_paused
		status_text = "PAUSED — edit freely." if game_paused else "RUNNING — keep the queues under control."


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_choose_route(0)
			KEY_2:
				_choose_route(1)
			KEY_3:
				_choose_route(2)
			KEY_SPACE:
				_toggle_start_pause()
			KEY_R:
				_reset_run()
			KEY_0:
				_reset_view()

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			if MAP_RECT.has_point(mouse_event.position):
				_zoom_at(mouse_event.position, ZOOM_STEP)
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			if MAP_RECT.has_point(mouse_event.position):
				_zoom_at(mouse_event.position, 1.0 / ZOOM_STEP)
			return
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mouse_event.pressed and MAP_RECT.has_point(mouse_event.position)
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_pointer(mouse_event.position)
			return

	if event is InputEventMouseMotion and panning:
		var motion: InputEventMouseMotion = event
		view_offset += motion.relative
		queue_redraw()


func _pointer(screen_pos: Vector2) -> void:
	var buttons: Array[Rect2] = _buttons()
	if buttons[0].has_point(screen_pos):
		_toggle_start_pause()
		return
	for i in range(MAX_ROUTES):
		if buttons[i + 1].has_point(screen_pos):
			_choose_route(i)
			return
	if buttons[4].has_point(screen_pos):
		_reset_run()
		return
	if buttons[5].has_point(screen_pos):
		_reload_osm()
		return
	if buttons[6].has_point(screen_pos):
		_zoom_at(MAP_RECT.get_center(), 1.0 / ZOOM_STEP)
		return
	if buttons[7].has_point(screen_pos):
		_zoom_at(MAP_RECT.get_center(), ZOOM_STEP)
		return
	if buttons[8].has_point(screen_pos):
		_reset_view()
		return

	if loading or game_over or not error_text.is_empty() or not MAP_RECT.has_point(screen_pos):
		return

	var map_pos: Vector2 = _screen_to_map(screen_pos)
	var node_id: int = _find_active_node(map_pos)
	if node_id >= 0:
		_edit_route(node_id)


func _buttons() -> Array[Rect2]:
	return [
		Rect2(PANEL_X, 112, 250, 48),
		Rect2(PANEL_X, 180, 76, 36),
		Rect2(PANEL_X + 87, 180, 76, 36),
		Rect2(PANEL_X + 174, 180, 76, 36),
		Rect2(PANEL_X, 238, 250, 38),
		Rect2(PANEL_X, 286, 250, 38),
		Rect2(PANEL_X, 344, 120, 34),
		Rect2(PANEL_X + 130, 344, 120, 34),
		Rect2(PANEL_X, 388, 250, 34)
	]


func _choose_route(index: int) -> void:
	if not _route_unlocked(index):
		status_text = "Route %d unlocks later." % (index + 1)
		return
	active_route = index
	status_text = "Route %d selected — click active stops in order." % (index + 1)
	queue_redraw()


func _edit_route(node_id: int) -> void:
	if node_id < 0 or node_id >= puzzle_nodes.size():
		return
	var route: Array = routes[active_route]

	if not route.is_empty() and int(route[-1]) == node_id:
		route.pop_back()
		status_text = "Removed the last stop from Route %d." % (active_route + 1)
	elif route.has(node_id):
		status_text = "That stop is already on Route %d." % (active_route + 1)
		return
	elif route.size() >= MAX_STOPS_PER_ROUTE:
		status_text = "Route %d is limited to %d stops." % [active_route + 1, MAX_STOPS_PER_ROUTE]
		return
	else:
		route.append(node_id)
		status_text = "Route %d: %d stop(s)." % [active_route + 1, route.size()]

	routes[active_route] = route
	if not game_started and _can_start():
		status_text = "Ready. Press START."
	queue_redraw()


func _find_active_node(pos: Vector2) -> int:
	var best_id: int = -1
	var best_distance: float = 26.0 / view_zoom
	for i in range(puzzle_nodes.size()):
		if not bool(puzzle_nodes[i]["active"]):
			continue
		var node_pos: Vector2 = puzzle_nodes[i]["pos"]
		var distance: float = pos.distance_to(node_pos)
		if distance < best_distance:
			best_distance = distance
			best_id = i
	return best_id


func _reload_osm() -> void:
	if FileAccess.file_exists(CACHE_PATH):
		var absolute_path: String = ProjectSettings.globalize_path(CACHE_PATH)
		DirAccess.remove_absolute(absolute_path)
	_load_map(true)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old_zoom: float = view_zoom
	var new_zoom: float = clampf(old_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var map_pos: Vector2 = _screen_to_map(screen_pos)
	view_zoom = new_zoom
	var center: Vector2 = MAP_RECT.get_center()
	view_offset = screen_pos - center - (map_pos - center) * view_zoom
	queue_redraw()


func _reset_view() -> void:
	view_zoom = DEFAULT_ZOOM
	view_offset = Vector2.ZERO
	queue_redraw()


func _screen_to_map(screen_pos: Vector2) -> Vector2:
	var center: Vector2 = MAP_RECT.get_center()
	return center + (screen_pos - center - view_offset) / view_zoom


func _view_translation() -> Vector2:
	var center: Vector2 = MAP_RECT.get_center()
	return center + view_offset - center * view_zoom


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), BG_COLOR, true)
	draw_rect(MAP_RECT, Color("#fbfaf6"), true)

	draw_set_transform(_view_translation(), 0.0, Vector2(view_zoom, view_zoom))
	_draw_topology()
	_draw_routes()
	_draw_nodes()
	_draw_buses()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_rect(Rect2(0, 0, 1000, 72), BG_COLOR, true)
	draw_rect(Rect2(0, 696, 1000, 24), BG_COLOR, true)
	draw_rect(Rect2(0, 72, 24, 624), BG_COLOR, true)
	draw_rect(MAP_RECT, Color("#aaa69d"), false, 1.0)

	_draw_panel()

	if loading:
		_draw_message("Extracting a puzzle from OpenStreetMap...", Color("#34383b"))
	elif not error_text.is_empty():
		_draw_message(error_text, Color("#a83f3f"))
	elif game_over:
		_draw_game_over()


func _draw_topology() -> void:
	for edge in puzzle_edges:
		var a: int = int(edge["a"])
		var b: int = int(edge["b"])
		var a_active: bool = bool(puzzle_nodes[a]["active"])
		var b_active: bool = bool(puzzle_nodes[b]["active"])
		if not a_active and not b_active:
			continue
		var pa: Vector2 = puzzle_nodes[a]["pos"]
		var pb: Vector2 = puzzle_nodes[b]["pos"]
		var color: Color = Color("#d8d4cb") if a_active and b_active else Color("#e9e5dd")
		var width: float = 3.0 / view_zoom if a_active and b_active else 1.5 / view_zoom
		draw_line(pa, pb, color, width, true)


func _draw_routes() -> void:
	for route_index in range(routes.size()):
		if not _route_unlocked(route_index):
			continue
		var route: Array = routes[route_index]
		if route.size() < 2:
			continue
		for i in range(route.size() - 1):
			var a: int = int(route[i])
			var b: int = int(route[i + 1])
			var path: PackedVector2Array = puzzle_graph.get_point_path(a, b)
			if path.size() >= 2:
				draw_polyline(path, Color("#fffdf8"), 10.0 / view_zoom, true)
				draw_polyline(path, route_colors[route_index], 5.5 / view_zoom, true)


func _draw_nodes() -> void:
	for i in range(puzzle_nodes.size()):
		var node: Dictionary = puzzle_nodes[i]
		if not bool(node["active"]):
			continue

		var pos: Vector2 = node["pos"]
		var kind: String = String(node["kind"])
		var color: Color = _kind_color(kind)
		var waiting_total: int = _node_waiting_total(i)

		if waiting_total > 0:
			var ratio: float = clampf(float(waiting_total) / float(FAIL_WAITING), 0.0, 1.0)
			draw_circle(pos, (26.0 + ratio * 14.0) / view_zoom, Color(0.82, 0.25, 0.25, 0.10 + ratio * 0.20))

		var pulse: float = 2.0 + sin(animation_time * 2.7 + float(i)) * 1.5
		if not _node_used_by_any_route(i):
			draw_circle(pos, (23.0 + pulse) / view_zoom, Color(color.r, color.g, color.b, 0.13))

		draw_circle(pos, 19.0 / view_zoom, Color("#fffdf8"))
		draw_arc(pos, 19.0 / view_zoom, 0.0, TAU, 32, color, 3.0 / view_zoom, true)

		draw_string(font, pos + Vector2(-10, 5) / view_zoom, _kind_letter(kind), HORIZONTAL_ALIGNMENT_CENTER, 20.0 / view_zoom, maxi(10, int(round(14.0 / view_zoom))), color)
		draw_string(font, pos + Vector2(-58, -29) / view_zoom, String(node["label"]), HORIZONTAL_ALIGNMENT_CENTER, 116.0 / view_zoom, maxi(8, int(round(11.0 / view_zoom))), Color("#3b4144"))
		_draw_waiting_tokens(i, pos)


func _draw_waiting_tokens(node_id: int, pos: Vector2) -> void:
	var waiting: Dictionary = puzzle_nodes[node_id]["waiting"]
	if waiting.is_empty():
		return
	var tokens: Array[String] = []
	for destination_value in waiting.keys():
		var destination: int = int(destination_value)
		var count: int = int(waiting[destination])
		for _n in range(mini(count, 3)):
			tokens.append(_kind_letter(String(puzzle_nodes[destination]["kind"])))
			if tokens.size() >= 6:
				break
		if tokens.size() >= 6:
			break
	var token_text: String = " ".join(tokens)
	draw_string(font, pos + Vector2(-60, 41) / view_zoom, token_text, HORIZONTAL_ALIGNMENT_CENTER, 120.0 / view_zoom, maxi(8, int(round(10.0 / view_zoom))), Color("#a44848"))


func _node_used_by_any_route(node_id: int) -> bool:
	for route in routes:
		if route.has(node_id):
			return true
	return false


func _draw_buses() -> void:
	if not game_started or game_paused or game_over:
		return
	for route_index in range(routes.size()):
		if not _route_unlocked(route_index):
			continue
		var route: Array = routes[route_index]
		if route.size() < 2:
			continue
		var path: PackedVector2Array = _full_route_path(route_index)
		if path.size() < 2:
			continue
		var phase: float = fmod(animation_time * (0.075 + float(route_index) * 0.012), 1.0)
		var pos: Vector2 = _point_along_path(path, phase)
		var size: Vector2 = Vector2(14, 8) / view_zoom
		draw_rect(Rect2(pos - size * 0.5, size), route_colors[route_index], true)


func _full_route_path(route_index: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var route: Array = routes[route_index]
	for i in range(route.size() - 1):
		var a: int = int(route[i])
		var b: int = int(route[i + 1])
		var leg: PackedVector2Array = puzzle_graph.get_point_path(a, b)
		for point in leg:
			if result.is_empty() or result[result.size() - 1].distance_to(point) > 0.1:
				result.append(point)
	return result


func _point_along_path(path: PackedVector2Array, phase: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if path.size() == 1:
		return path[0]

	var total_length: float = 0.0
	for i in range(path.size() - 1):
		total_length += path[i].distance_to(path[i + 1])
	if total_length <= 0.0:
		return path[0]

	var target: float = clampf(phase, 0.0, 1.0) * total_length
	var walked: float = 0.0
	for i in range(path.size() - 1):
		var segment: float = path[i].distance_to(path[i + 1])
		if walked + segment >= target:
			var local_t: float = (target - walked) / maxf(segment, 0.001)
			return path[i].lerp(path[i + 1], local_t)
		walked += segment
	return path[path.size() - 1]


func _draw_panel() -> void:
	draw_rect(Rect2(976, 0, 304, 720), Color("#ece8df"), true)
	draw_line(Vector2(976, 0), Vector2(976, 720), Color("#c8c2b7"), 1.0)

	draw_string(font, Vector2(PANEL_X, 31), "BUS MASTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("#292e31"))
	draw_string(font, Vector2(PANEL_X, 54), "TOPOLOGY PUZZLE  v0.4.0", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#656a6d"))
	draw_string(font, Vector2(PANEL_X, 79), AREA_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#3f4548"))
	draw_string(font, Vector2(PANEL_X, 98), "OSM shapes the puzzle; raw map is hidden.", HORIZONTAL_ALIGNMENT_LEFT, 250, 10, Color("#777a7c"))

	var buttons: Array[Rect2] = _buttons()
	var start_fill: Color = Color("#b9d6b1") if _can_start() or game_started or game_over else Color("#d5d1c8")
	_button(buttons[0], _start_label(), start_fill)

	for i in range(MAX_ROUTES):
		var unlocked: bool = _route_unlocked(i)
		var fill: Color = route_colors[i] if active_route == i and unlocked else Color("#dad6ce")
		if not unlocked:
			fill = Color("#e4e1da")
		_button(buttons[i + 1], "R%d%s" % [i + 1, "" if unlocked else " LOCK"], fill)

	_button(buttons[4], "Reset Run", Color("#dad6ce"))
	_button(buttons[5], "Reload OSM", Color("#dad6ce"))
	_button(buttons[6], "Zoom -", Color("#dad6ce"))
	_button(buttons[7], "Zoom +", Color("#dad6ce"))
	_button(buttons[8], "Reset View", Color("#dad6ce"))

	draw_string(font, Vector2(PANEL_X, 447), "Delivered: %d" % delivered, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#32373a"))
	draw_string(font, Vector2(PANEL_X, 472), "Active stops: %d / %d" % [_active_node_ids().size(), puzzle_nodes.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5f6467"))
	draw_string(font, Vector2(PANEL_X, 494), "Route 2: %s" % ("open" if _route_unlocked(1) else "28 delivered"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#666b6e"))
	draw_string(font, Vector2(PANEL_X, 514), "Route 3: %s" % ("open" if _route_unlocked(2) else "95 delivered"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#666b6e"))

	draw_string(font, Vector2(PANEL_X, 552), status_text, HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Color("#494f52"))
	draw_string(font, Vector2(PANEL_X, 612), _next_reveal_text(), HORIZONTAL_ALIGNMENT_LEFT, 250, 11, Color("#686d70"))

	var source: String = "OSM source: cache" if loaded_from_cache else "OSM source: live"
	draw_string(font, Vector2(PANEL_X, 655), source, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#767a7c"))
	draw_string(font, Vector2(PANEL_X, 674), "© OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#767a7c"))
	draw_string(font, Vector2(PANEL_X, 696), "Wheel zoom · MMB pan · Space start/pause", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#767a7c"))


func _next_reveal_text() -> String:
	for i in range(INITIAL_ACTIVE_NODES, puzzle_nodes.size()):
		if not bool(puzzle_nodes[i]["active"]):
			return "Next stop at %d delivered" % int(puzzle_nodes[i]["threshold"])
	return "All extracted stops are active"


func _start_label() -> String:
	if game_over:
		return "TRY AGAIN"
	if not game_started:
		return "START"
	if game_paused:
		return "RESUME"
	return "PAUSE"


func _button(rect: Rect2, label: String, fill: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color("#77736b"), false, 1.0)
	draw_string(font, rect.position + Vector2(6, 25), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12.0, 12, Color("#303437"))


func _draw_message(message: String, color: Color) -> void:
	draw_rect(MAP_RECT, Color(1.0, 1.0, 1.0, 0.86), true)
	draw_string(font, MAP_RECT.get_center() + Vector2(-270, 0), message, HORIZONTAL_ALIGNMENT_CENTER, 540, 19, color)


func _draw_game_over() -> void:
	draw_rect(MAP_RECT, Color(0.98, 0.97, 0.94, 0.72), true)
	draw_string(font, MAP_RECT.get_center() + Vector2(-220, -18), "NETWORK OVERLOADED", HORIZONTAL_ALIGNMENT_CENTER, 440, 24, Color("#943f3f"))
	draw_string(font, MAP_RECT.get_center() + Vector2(-220, 18), "%d passengers delivered" % delivered, HORIZONTAL_ALIGNMENT_CENTER, 440, 14, Color("#4d5255"))


func _kind_color(kind: String) -> Color:
	match kind:
		"residential":
			return Color("#c98662")
		"hub":
			return Color("#7663a3")
		"commercial":
			return Color("#b96c94")
		"work":
			return Color("#587f9f")
		"education":
			return Color("#cf9840")
		"service":
			return Color("#6d9a8c")
		"leisure":
			return Color("#6e9b68")
		_:
			return Color("#6f7476")


func _kind_letter(kind: String) -> String:
	match kind:
		"residential":
			return "H"
		"hub":
			return "T"
		"commercial":
			return "C"
		"work":
			return "W"
		"education":
			return "E"
		"service":
			return "S"
		"leisure":
			return "L"
		_:
			return "•"
