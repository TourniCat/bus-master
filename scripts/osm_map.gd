extends Node2D

const BUILD: String = "0.3.1-puzzle-map-fix"
const OVERPASS_URL: String = "https://overpass-api.de/api/interpreter"
const CACHE_PATH: String = "user://bus_master_gangnam_osm_v3.json"

const MAP_RECT := Rect2(20, 80, 980, 600)
const PANEL_X: float = 1020.0
const BG_COLOR := Color("#f4f2ec")

# Compact Gangnam Station test area: roughly 0.9 km x 0.9 km.
const SOUTH: float = 37.4938
const WEST: float = 127.0225
const NORTH: float = 37.5019
const EAST: float = 127.0328
const AREA_NAME: String = "Gangnam Station"

const MAX_STOPS: int = 8
const MAX_ROUTES: int = 3
const MAX_STOPS_PER_ROUTE: int = 4
const FAIL_WAITING: int = 18
const TICK_SECONDS: float = 0.8

const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 4.0
const DEFAULT_ZOOM: float = 1.25
const ZOOM_STEP: float = 1.18

var font: Font
var http: HTTPRequest
var graph := AStar2D.new()

var loading: bool = true
var error_text: String = ""
var loaded_from_cache: bool = false

var road_lines: Array[Dictionary] = []
var buildings: Array[PackedVector2Array] = []
var building_samples: Array[Dictionary] = []
var parks: Array[PackedVector2Array] = []
var waters: Array[PackedVector2Array] = []
var pois: Array[Dictionary] = []

var graph_positions: Array[Vector2] = []
var osm_node_to_local: Dictionary = {}

var districts: Array[Dictionary] = []
var stops: Array[Dictionary] = []
var routes: Array[Array] = []
var active_route: int = 0
var place_mode: bool = true

var game_started: bool = false
var game_paused: bool = false
var game_over: bool = false
var delivered: int = 0
var tick_accumulator: float = 0.0
var animation_time: float = 0.0

var status_text: String = "Loading OpenStreetMap..."

var view_zoom: float = DEFAULT_ZOOM
var view_offset: Vector2 = Vector2.ZERO
var panning: bool = false

var route_colors: Array[Color] = [
	Color("#e25d68"),
	Color("#4d82d5"),
	Color("#56a36b")
]

var excluded_roads: Array[String] = [
	"footway", "path", "steps", "cycleway", "bridleway",
	"corridor", "construction", "proposed"
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
	status_text = "Loading OpenStreetMap..."
	_clear_map()

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
  way["leisure"="park"](%s);
  way["natural"="water"](%s);
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
""" % [bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox]

	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"User-Agent: BusMasterPrototype/0.3"
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
		_log("OSM invalid JSON bytes=%d" % body.size())
		queue_redraw()
		return

	var file: FileAccess = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

	_log("OSM download bytes=%d" % body.size())
	_parse_osm(parsed)


func _clear_map() -> void:
	road_lines.clear()
	buildings.clear()
	building_samples.clear()
	parks.clear()
	waters.clear()
	pois.clear()
	graph_positions.clear()
	osm_node_to_local.clear()
	districts.clear()
	graph.clear()


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
				_parse_road(element, tags)
			elif tags.has("building"):
				_parse_building(element, tags)
			elif String(tags.get("leisure", "")) == "park":
				_parse_polygon_into(element, parks)
			elif String(tags.get("natural", "")) == "water":
				_parse_polygon_into(element, waters)
			else:
				_parse_way_poi(element, tags)
		elif type_name == "node":
			_parse_node_poi(element, tags)

	loading = false
	if graph_positions.is_empty():
		_fail_parse("No drivable roads found in this area.")
		return

	_generate_districts()
	_reset_run()
	status_text = "STEP 1 — Click the two highlighted districts to place stops."
	_log("OSM ready roads=%d nodes=%d buildings=%d poi=%d districts=%d cache=%s" % [
		road_lines.size(), graph_positions.size(), buildings.size(),
		pois.size(), districts.size(), str(loaded_from_cache)
	])
	queue_redraw()


func _fail_parse(message: String) -> void:
	loading = false
	error_text = message
	status_text = message
	_log("OSM parse error: %s" % message)
	queue_redraw()


func _parse_road(element: Dictionary, tags: Dictionary) -> void:
	var road_class: String = String(tags.get("highway", ""))
	if excluded_roads.has(road_class):
		return

	var geom_variant: Variant = element.get("geometry", [])
	var ids_variant: Variant = element.get("nodes", [])
	if not (geom_variant is Array) or not (ids_variant is Array):
		return

	var geom: Array = geom_variant
	var ids: Array = ids_variant
	if geom.size() < 2:
		return

	var line := PackedVector2Array()
	for point_value in geom:
		if point_value is Dictionary:
			var point: Dictionary = point_value
			if point.has("lat") and point.has("lon"):
				line.append(_project(float(point["lat"]), float(point["lon"])))

	var oneway_text: String = String(tags.get("oneway", ""))
	var oneway_dir: int = 0
	if oneway_text in ["yes", "true", "1"] or String(tags.get("junction", "")) == "roundabout":
		oneway_dir = 1
	elif oneway_text == "-1":
		oneway_dir = -1

	if line.size() >= 2:
		road_lines.append({
			"points": line,
			"width": _road_width(road_class),
			"class": road_class,
			"level": _road_display_level(road_class),
			"oneway": oneway_dir
		})

	var count: int = mini(geom.size(), ids.size())
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
		var local_id: int = _graph_node(
			osm_id,
			_project(float(point["lat"]), float(point["lon"]))
		)
		local_ids.append(local_id)

	for i in range(1, local_ids.size()):
		var previous_local: int = local_ids[i - 1]
		var local_id: int = local_ids[i]
		if previous_local < 0 or local_id < 0 or previous_local == local_id:
			continue

		if oneway_dir == 1:
			if not graph.are_points_connected(previous_local, local_id, false):
				graph.connect_points(previous_local, local_id, false)
		elif oneway_dir == -1:
			if not graph.are_points_connected(local_id, previous_local, false):
				graph.connect_points(local_id, previous_local, false)
		else:
			if not graph.are_points_connected(previous_local, local_id):
				graph.connect_points(previous_local, local_id, true)


func _graph_node(osm_id: int, pos: Vector2) -> int:
	if osm_node_to_local.has(osm_id):
		return int(osm_node_to_local[osm_id])
	var id: int = graph_positions.size()
	osm_node_to_local[osm_id] = id
	graph_positions.append(pos)
	graph.add_point(id, pos)
	return id


func _road_width(kind: String) -> float:
	match kind:
		"motorway", "trunk":
			return 5.0
		"primary":
			return 4.6
		"secondary":
			return 4.0
		"tertiary":
			return 3.2
		"residential", "living_street":
			return 2.2
		_:
			return 1.6


func _road_display_level(kind: String) -> int:
	match kind:
		"motorway", "trunk", "primary", "secondary":
			return 2
		"tertiary", "residential", "living_street", "unclassified":
			return 1
		_:
			return 0


func _project(lat: float, lon: float) -> Vector2:
	var x: float = (lon - WEST) / (EAST - WEST)
	var y: float = 1.0 - ((lat - SOUTH) / (NORTH - SOUTH))
	return MAP_RECT.position + Vector2(x * MAP_RECT.size.x, y * MAP_RECT.size.y)


func _parse_building(element: Dictionary, tags: Dictionary) -> void:
	var polygon: PackedVector2Array = _geometry_polygon(element)
	if polygon.size() < 3:
		return
	buildings.append(polygon)

	var center: Vector2 = _polygon_center(polygon)
	building_samples.append({
		"pos": center,
		"kind": _building_kind(String(tags.get("building", "")))
	})
	_append_poi_from_tags(center, tags)


func _building_kind(kind: String) -> String:
	if kind in [
		"apartments", "residential", "house", "detached", "terrace",
		"dormitory", "semidetached_house"
	]:
		return "residential"
	if kind in ["office", "commercial", "retail", "hotel"]:
		return "work"
	return "generic"


func _parse_polygon_into(element: Dictionary, target: Array) -> void:
	var polygon: PackedVector2Array = _geometry_polygon(element)
	if polygon.size() >= 3:
		target.append(polygon)


func _geometry_polygon(element: Dictionary) -> PackedVector2Array:
	var geom_variant: Variant = element.get("geometry", [])
	if not (geom_variant is Array):
		return PackedVector2Array()
	var geom: Array = geom_variant
	var polygon := PackedVector2Array()
	for point_value in geom:
		if point_value is Dictionary:
			var point: Dictionary = point_value
			if point.has("lat") and point.has("lon"):
				polygon.append(_project(float(point["lat"]), float(point["lon"])))
	return polygon


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return MAP_RECT.get_center()
	var sum := Vector2.ZERO
	for point in polygon:
		sum += point
	return sum / float(polygon.size())


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

	if railway == "station":
		kind = "hub"
	elif amenity in ["bus_station", "ferry_terminal"]:
		kind = "hub"
	elif amenity in ["school", "college", "university", "kindergarten"]:
		kind = "education"
	elif amenity in ["hospital", "clinic", "doctors"]:
		kind = "medical"
	elif not shop.is_empty():
		kind = "commercial"
	elif not tourism.is_empty():
		kind = "leisure"
	elif amenity in ["marketplace", "cinema", "theatre", "restaurant", "cafe", "fast_food"]:
		kind = "commercial"
	else:
		return

	pois.append({
		"pos": pos,
		"kind": kind,
		"name": String(tags.get("name", kind))
	})


func _generate_districts() -> void:
	districts.clear()

	var hub_pos: Vector2 = _best_poi_position(
		["hub"], [], MAP_RECT.get_center()
	)
	if hub_pos.x < 0.0:
		hub_pos = _fallback_position(Vector2(0.50, 0.52))

	var avoid: Array[Vector2] = [hub_pos]
	var residential_candidates: Array[Vector2] = _building_positions("residential")
	if residential_candidates.is_empty():
		residential_candidates = _building_positions("generic")
	var residential_pos: Vector2 = _best_dense_position(residential_candidates, avoid)
	if residential_pos.x < 0.0:
		residential_pos = _fallback_position(Vector2(0.22, 0.68))
	avoid.append(residential_pos)

	var commercial_pos: Vector2 = _best_poi_position(
		["commercial", "leisure"], avoid, MAP_RECT.get_center()
	)
	if commercial_pos.x < 0.0:
		commercial_pos = _fallback_position(Vector2(0.74, 0.38))
	avoid.append(commercial_pos)

	var work_candidates: Array[Vector2] = _building_positions("work")
	if work_candidates.is_empty():
		work_candidates = _building_positions("generic")
	var work_pos: Vector2 = _best_dense_position(work_candidates, avoid)
	if work_pos.x < 0.0:
		work_pos = _fallback_position(Vector2(0.70, 0.72))
	avoid.append(work_pos)

	var education_pos: Vector2 = _best_poi_position(
		["education"], avoid, MAP_RECT.get_center()
	)
	if education_pos.x < 0.0:
		education_pos = _fallback_position(Vector2(0.28, 0.28))

	_add_district("residential", "Residential", residential_pos, 0)
	_add_district("hub", _hub_label_near(hub_pos), hub_pos, 0)
	_add_district("commercial", "Commercial", commercial_pos, 20)
	_add_district("work", "Office District", work_pos, 50)
	_add_district("education", "Education", education_pos, 90)

	_log("DISTRICTS " + _district_debug_summary())


func _building_positions(kind: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for sample in building_samples:
		if String(sample.get("kind", "")) == kind:
			result.append(sample["pos"])
	return result


func _best_dense_position(candidates: Array[Vector2], avoid: Array[Vector2]) -> Vector2:
	if candidates.is_empty():
		return Vector2(-1, -1)

	var best_pos: Vector2 = candidates[0]
	var best_score: float = -INF
	for candidate in candidates:
		var density: float = 0.0
		for other in candidates:
			if candidate.distance_to(other) < 125.0:
				density += 1.0

		var separation: float = 180.0
		for blocked in avoid:
			separation = minf(separation, candidate.distance_to(blocked))
		var score: float = density + separation * 0.035
		if score > best_score:
			best_score = score
			best_pos = candidate
	return best_pos


func _best_poi_position(
	kinds: Array[String],
	avoid: Array[Vector2],
	reference: Vector2
) -> Vector2:
	var best: Vector2 = Vector2(-1, -1)
	var best_score: float = -INF
	for poi in pois:
		if not kinds.has(String(poi.get("kind", ""))):
			continue
		var pos: Vector2 = poi["pos"]
		var separation: float = 220.0
		for blocked in avoid:
			separation = minf(separation, pos.distance_to(blocked))
		var centrality: float = 1.0 / maxf(1.0, pos.distance_to(reference))
		var score: float = separation + centrality * 500.0
		if score > best_score:
			best_score = score
			best = pos
	return best


func _fallback_position(normalized: Vector2) -> Vector2:
	var target: Vector2 = MAP_RECT.position + Vector2(
		normalized.x * MAP_RECT.size.x,
		normalized.y * MAP_RECT.size.y
	)
	var graph_id: int = _nearest_graph_node_unlimited(target)
	if graph_id >= 0:
		return graph_positions[graph_id]
	return target


func _add_district(kind: String, label: String, source_pos: Vector2, threshold: int) -> void:
	var graph_id: int = _nearest_graph_node_unlimited(source_pos)
	if graph_id < 0:
		return
	districts.append({
		"kind": kind,
		"label": label,
		"pos": graph_positions[graph_id],
		"graph_id": graph_id,
		"threshold": threshold,
		"active": false,
		"waiting": 0,
		"stop_id": -1
	})


func _hub_label_near(pos: Vector2) -> String:
	var best_name: String = "Transit Hub"
	var best_distance: float = 999999.0
	for poi in pois:
		if String(poi.get("kind", "")) != "hub":
			continue
		var distance: float = pos.distance_to(poi["pos"])
		if distance < best_distance:
			best_distance = distance
			var candidate: String = String(poi.get("name", "Transit Hub"))
			if not candidate.is_empty() and candidate != "hub":
				best_name = candidate
	return best_name


func _district_debug_summary() -> String:
	var parts := PackedStringArray()
	for district in districts:
		parts.append("%s@%s" % [
			String(district["kind"]),
			str(district["pos"])
		])
	return " | ".join(parts)


func _reset_routes() -> void:
	routes.clear()
	for _i in range(MAX_ROUTES):
		routes.append([])


func _reset_run() -> void:
	stops.clear()
	_reset_routes()
	active_route = 0
	place_mode = true
	game_started = false
	game_paused = false
	game_over = false
	delivered = 0
	tick_accumulator = 0.0

	for i in range(districts.size()):
		districts[i]["active"] = i < 2
		districts[i]["waiting"] = 0
		districts[i]["stop_id"] = -1

	status_text = "STEP 1 — Click the two highlighted districts to place stops."
	queue_redraw()


func _simulation_tick() -> void:
	var active_ids: Array[int] = []
	for i in range(districts.size()):
		if bool(districts[i]["active"]):
			active_ids.append(i)
	if active_ids.size() < 2:
		return

	var demand_count: int = 1 + int(delivered / 45)
	demand_count = mini(demand_count, 4)

	for _n in range(demand_count):
		var origin_id: int = active_ids[int(randi() % active_ids.size())]
		var destination_id: int = origin_id
		var safety: int = 0
		while destination_id == origin_id and safety < 10:
			destination_id = active_ids[int(randi() % active_ids.size())]
			safety += 1

		if _districts_connected(origin_id, destination_id):
			delivered += 1
			var waiting: int = int(districts[origin_id]["waiting"])
			if waiting > 0:
				districts[origin_id]["waiting"] = waiting - 1
		else:
			districts[origin_id]["waiting"] = int(districts[origin_id]["waiting"]) + 1

	_reveal_districts()

	for district in districts:
		if bool(district["active"]) and int(district["waiting"]) >= FAIL_WAITING:
			game_over = true
			game_paused = false
			status_text = "NETWORK OVERLOADED — Reset and try another layout."
			_log("GAME_OVER delivered=%d district=%s" % [
				delivered, String(district["label"])
			])
			break


func _districts_connected(a_id: int, b_id: int) -> bool:
	if a_id < 0 or b_id < 0 or a_id >= districts.size() or b_id >= districts.size():
		return false
	var a_stop: int = int(districts[a_id]["stop_id"])
	var b_stop: int = int(districts[b_id]["stop_id"])
	if a_stop < 0 or b_stop < 0:
		return false
	return _stops_connected_by_network(a_stop, b_stop)


func _stops_connected_by_network(start_stop: int, target_stop: int) -> bool:
	if start_stop == target_stop:
		return true

	var frontier: Array[int] = [start_stop]
	var visited: Dictionary = {start_stop: true}
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		for route_index in range(routes.size()):
			if not _route_unlocked(route_index):
				continue
			var route: Array = routes[route_index]
			if not route.has(current):
				continue
			for stop_value in route:
				var stop_id: int = int(stop_value)
				if stop_id == target_stop:
					return true
				if not visited.has(stop_id):
					visited[stop_id] = true
					frontier.append(stop_id)
	return false


func _reveal_districts() -> void:
	for i in range(2, districts.size()):
		if bool(districts[i]["active"]):
			continue
		var threshold: int = int(districts[i]["threshold"])
		if delivered >= threshold:
			districts[i]["active"] = true
			status_text = "NEW DISTRICT — %s. Add a stop before demand piles up." % String(districts[i]["label"])
			_log("REVEAL district=%s delivered=%d" % [
				String(districts[i]["label"]), delivered
			])


func _route_unlocked(route_index: int) -> bool:
	match route_index:
		0:
			return true
		1:
			return delivered >= 20
		2:
			return delivered >= 60
		_:
			return false


func _can_start() -> bool:
	if districts.size() < 2:
		return false
	var first_stop: int = int(districts[0]["stop_id"])
	var second_stop: int = int(districts[1]["stop_id"])
	if first_stop < 0 or second_stop < 0:
		return false
	return routes[0].has(first_stop) and routes[0].has(second_stop)


func _toggle_start_pause() -> void:
	if game_over:
		_reset_run()
		return
	if not game_started:
		if not _can_start():
			status_text = "Connect the two starting districts with Route 1 first."
			return
		game_started = true
		game_paused = false
		status_text = "RUNNING — Keep every active district connected."
		_log("START_RUN")
	else:
		game_paused = not game_paused
		status_text = "PAUSED — Edit the network, then resume." if game_paused else "RUNNING — Keep every active district connected."
		_log("PAUSE=%s" % str(game_paused))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S:
				place_mode = true
				status_text = "Stop mode — click an active district."
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
		return

	if event is InputEventScreenTouch and event.pressed:
		_pointer(event.position)


func _pointer(screen_pos: Vector2) -> void:
	var buttons: Array[Rect2] = _buttons()

	if buttons[0].has_point(screen_pos):
		_toggle_start_pause()
		return

	for i in range(3):
		if buttons[i + 1].has_point(screen_pos):
			_choose_route(i)
			return

	if buttons[4].has_point(screen_pos):
		place_mode = true
		status_text = "Stop mode — click an active district."
		return
	if buttons[5].has_point(screen_pos):
		_reset_run()
		return
	if buttons[6].has_point(screen_pos):
		_reload_osm()
		return
	if buttons[7].has_point(screen_pos):
		_zoom_at(MAP_RECT.get_center(), 1.0 / ZOOM_STEP)
		return
	if buttons[8].has_point(screen_pos):
		_zoom_at(MAP_RECT.get_center(), ZOOM_STEP)
		return
	if buttons[9].has_point(screen_pos):
		_reset_view()
		return

	if loading or not error_text.is_empty() or not MAP_RECT.has_point(screen_pos):
		return

	var map_pos: Vector2 = _screen_to_map(screen_pos)
	if place_mode:
		_place_stop_for_district(map_pos)
	else:
		var stop_id: int = _find_stop(map_pos)
		if stop_id >= 0:
			_edit_route(stop_id)


func _buttons() -> Array[Rect2]:
	return [
		Rect2(PANEL_X, 116, 236, 46),
		Rect2(PANEL_X, 184, 72, 34),
		Rect2(PANEL_X + 82, 184, 72, 34),
		Rect2(PANEL_X + 164, 184, 72, 34),
		Rect2(PANEL_X, 236, 236, 36),
		Rect2(PANEL_X, 282, 236, 36),
		Rect2(PANEL_X, 328, 236, 36),
		Rect2(PANEL_X, 384, 112, 34),
		Rect2(PANEL_X + 124, 384, 112, 34),
		Rect2(PANEL_X, 428, 236, 34)
	]


func _choose_route(index: int) -> void:
	if not _route_unlocked(index):
		status_text = "Route %d is not unlocked yet." % (index + 1)
		return
	active_route = index
	place_mode = false
	status_text = "Route %d — click stops in order." % (index + 1)
	_log("ACTION route=%d" % (index + 1))


func _place_stop_for_district(pos: Vector2) -> void:
	if stops.size() >= MAX_STOPS:
		status_text = "Stop limit reached (%d)." % MAX_STOPS
		return

	var district_id: int = _find_active_district(pos)
	if district_id < 0:
		status_text = "Stops attach to highlighted districts in this prototype."
		return
	if int(districts[district_id]["stop_id"]) >= 0:
		status_text = "%s already has a stop." % String(districts[district_id]["label"])
		return

	var graph_id: int = int(districts[district_id]["graph_id"])
	var stop_id: int = stops.size()
	stops.append({
		"graph_id": graph_id,
		"pos": graph_positions[graph_id],
		"district_id": district_id
	})
	districts[district_id]["stop_id"] = stop_id

	if not game_started and _starting_stops_ready():
		place_mode = false
		active_route = 0
		status_text = "STEP 2 — Route 1 selected. Click both stops to connect them."
	else:
		status_text = "Stop added at %s. Select a route to connect it." % String(districts[district_id]["label"])

	_log("ACTION stop district=%s stop=%d" % [
		String(districts[district_id]["label"]), stop_id
	])
	queue_redraw()


func _starting_stops_ready() -> bool:
	if districts.size() < 2:
		return false
	return int(districts[0]["stop_id"]) >= 0 and int(districts[1]["stop_id"]) >= 0


func _find_active_district(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = 48.0 / view_zoom
	for i in range(districts.size()):
		if not bool(districts[i]["active"]):
			continue
		var distance: float = pos.distance_to(districts[i]["pos"])
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _nearest_graph_node_unlimited(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = INF
	for i in range(graph_positions.size()):
		var distance: float = pos.distance_to(graph_positions[i])
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _find_stop(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = 20.0 / view_zoom
	for i in range(stops.size()):
		var stop_pos: Vector2 = stops[i]["pos"]
		var distance: float = pos.distance_to(stop_pos)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _edit_route(stop_id: int) -> void:
	var route: Array = routes[active_route]
	if not route.is_empty() and int(route[-1]) == stop_id:
		route.pop_back()
		status_text = "Removed last stop from Route %d." % (active_route + 1)
	elif route.has(stop_id):
		status_text = "Stop already belongs to Route %d." % (active_route + 1)
		return
	elif route.size() >= MAX_STOPS_PER_ROUTE:
		status_text = "Route %d can use at most %d stops." % [
			active_route + 1, MAX_STOPS_PER_ROUTE
		]
		return
	else:
		route.append(stop_id)
		status_text = "Route %d now has %d stops." % [active_route + 1, route.size()]

	routes[active_route] = route
	if not game_started and _can_start():
		status_text = "STEP 3 — Route ready. Press START."
	_log("ACTION route=%d stops=%d" % [active_route + 1, route.size()])
	queue_redraw()


func _reload_osm() -> void:
	_reset_run()
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
	_draw_map_content()
	_draw_routes()
	_draw_districts()
	_draw_stops()
	_draw_buses()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Mask transformed content outside the map viewport.
	draw_rect(Rect2(0, 0, 1000, 80), BG_COLOR, true)
	draw_rect(Rect2(0, 680, 1000, 40), BG_COLOR, true)
	draw_rect(Rect2(0, 80, 20, 600), BG_COLOR, true)
	draw_rect(MAP_RECT, Color("#aaa69d"), false, 1.0)

	_draw_panel()

	if loading:
		_draw_message("Building puzzle map from OpenStreetMap...", Color("#34383b"))
	elif not error_text.is_empty():
		_draw_message(error_text, Color("#a83f3f"))


func _draw_map_content() -> void:
	for polygon in waters:
		draw_colored_polygon(polygon, Color("#dcebf0"))
	for polygon in parks:
		draw_colored_polygon(polygon, Color("#e5eddf"))

	# Buildings are context, not gameplay. Reveal them only when zoomed in.
	if view_zoom >= 1.7:
		for polygon in buildings:
			draw_colored_polygon(polygon, Color("#ebe8e1"))

	for road in road_lines:
		var level: int = int(road["level"])
		if level == 0:
			continue
		if level == 1 and view_zoom < 1.55:
			continue

		var line: PackedVector2Array = road["points"]
		if line.size() < 2:
			continue
		var width: float = float(road["width"])
		var base_color: Color = Color("#c7c4bd") if level == 2 else Color("#d8d5cf")
		var inner_color: Color = Color("#fffefa")
		draw_polyline(line, base_color, width + 2.0, true)
		draw_polyline(line, inner_color, width, true)

		var oneway: int = int(road["oneway"])
		if oneway != 0 and view_zoom >= 1.45:
			_draw_path_arrow(line, oneway, Color("#9c9992"), 0.9)


func _draw_routes() -> void:
	for route_index in range(routes.size()):
		if not _route_unlocked(route_index):
			continue
		var route: Array = routes[route_index]
		if route.size() < 2:
			continue

		for i in range(route.size() - 1):
			var a_stop: int = int(route[i])
			var b_stop: int = int(route[i + 1])
			var a_graph: int = int(stops[a_stop]["graph_id"])
			var b_graph: int = int(stops[b_stop]["graph_id"])

			var forward: PackedVector2Array = graph.get_point_path(a_graph, b_graph)
			var reverse: PackedVector2Array = graph.get_point_path(b_graph, a_graph)

			if forward.size() >= 2:
				_draw_route_path(forward, route_colors[route_index], 1)
			if reverse.size() >= 2 and not _paths_visually_same(forward, reverse):
				_draw_route_path(reverse, route_colors[route_index], 1)


func _draw_route_path(path: PackedVector2Array, color: Color, direction: int) -> void:
	draw_polyline(path, Color("#fffdf8"), 8.5 / view_zoom, true)
	draw_polyline(path, color, 4.5 / view_zoom, true)
	_draw_path_arrow(path, direction, color.darkened(0.18), 1.2)


func _paths_visually_same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return a[0].distance_to(b[b.size() - 1]) < 2.0 and a[a.size() - 1].distance_to(b[0]) < 2.0 and abs(a.size() - b.size()) <= 2


func _draw_path_arrow(
	path: PackedVector2Array,
	direction: int,
	color: Color,
	width: float
) -> void:
	if path.size() < 2:
		return
	var mid: int = clampi(int(path.size() / 2), 0, path.size() - 2)
	var a: Vector2 = path[mid]
	var b: Vector2 = path[mid + 1]
	if direction < 0:
		var swap: Vector2 = a
		a = b
		b = swap

	var vector: Vector2 = b - a
	if vector.length() < 0.1:
		return
	var unit: Vector2 = vector.normalized()
	var normal: Vector2 = Vector2(-unit.y, unit.x)
	var tip: Vector2 = (a + b) * 0.5 + unit * (5.0 / view_zoom)
	var base: Vector2 = tip - unit * (10.0 / view_zoom)
	var wing: float = 4.0 / view_zoom
	var arrow := PackedVector2Array([
		base + normal * wing,
		tip,
		base - normal * wing
	])
	draw_polyline(arrow, color, width / view_zoom, true)


func _draw_districts() -> void:
	for i in range(districts.size()):
		var district: Dictionary = districts[i]
		if not bool(district["active"]):
			continue

		var pos: Vector2 = district["pos"]
		var kind: String = String(district["kind"])
		var color: Color = _district_color(kind)
		var has_stop: bool = int(district["stop_id"]) >= 0
		var waiting: int = int(district["waiting"])

		var radius: float = (26.0 if has_stop else 30.0) / view_zoom
		if not has_stop:
			var pulse: float = 4.0 + sin(animation_time * 3.0 + float(i)) * 2.0
			draw_circle(pos, radius + pulse / view_zoom, Color(color.r, color.g, color.b, 0.12))
		if waiting > 0:
			var danger_ratio: float = clampf(float(waiting) / float(FAIL_WAITING), 0.0, 1.0)
			draw_circle(pos, radius + 7.0 / view_zoom, Color(0.82, 0.25, 0.25, 0.10 + danger_ratio * 0.20))

		draw_circle(pos, radius, Color("#fffdf8"))
		draw_arc(pos, radius, 0.0, TAU, 32, color, 3.0 / view_zoom, true)

		var letter: String = _district_letter(kind)
		draw_string(
			font,
			pos + Vector2(-12, 6) / view_zoom,
			letter,
			HORIZONTAL_ALIGNMENT_CENTER,
			24.0 / view_zoom,
			maxi(10, int(round(15.0 / view_zoom))),
			color
		)

		var label: String = String(district["label"])
		draw_string(
			font,
			pos + Vector2(-70, -38) / view_zoom,
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			140.0 / view_zoom,
			maxi(9, int(round(12.0 / view_zoom))),
			Color("#3e4447")
		)
		if waiting > 0:
			draw_string(
				font,
				pos + Vector2(-22, 49) / view_zoom,
				"%d waiting" % waiting,
				HORIZONTAL_ALIGNMENT_CENTER,
				44.0 / view_zoom,
				maxi(8, int(round(10.0 / view_zoom))),
				Color("#b44b4b")
			)


func _draw_stops() -> void:
	for i in range(stops.size()):
		var pos: Vector2 = stops[i]["pos"]
		var radius: float = 9.0 / view_zoom
		draw_circle(pos, radius, Color("#2f3437"))
		draw_circle(pos, 4.5 / view_zoom, Color("#fffdf8"))


func _draw_buses() -> void:
	if not game_started or game_paused or game_over:
		return
	for route_index in range(routes.size()):
		if not _route_unlocked(route_index):
			continue
		var path: PackedVector2Array = _full_route_path(route_index)
		if path.size() < 2:
			continue
		var phase: float = fmod(animation_time * (0.08 + route_index * 0.015), 1.0)
		var pos: Vector2 = _point_along_path(path, phase)
		var size: Vector2 = Vector2(12, 7) / view_zoom
		draw_rect(Rect2(pos - size * 0.5, size), route_colors[route_index], true)


func _full_route_path(route_index: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var route: Array = routes[route_index]
	if route.size() < 2:
		return result

	for i in range(route.size() - 1):
		var a_stop: int = int(route[i])
		var b_stop: int = int(route[i + 1])
		var a_graph: int = int(stops[a_stop]["graph_id"])
		var b_graph: int = int(stops[b_stop]["graph_id"])
		var leg: PackedVector2Array = graph.get_point_path(a_graph, b_graph)
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
	draw_rect(Rect2(1000, 0, 280, 720), Color("#ede9e0"), true)
	draw_line(Vector2(1000, 0), Vector2(1000, 720), Color("#c7c1b6"), 1.0)

	draw_string(font, Vector2(PANEL_X, 32), "BUS MASTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("#292e31"))
	draw_string(font, Vector2(PANEL_X, 55), "PUZZLE MAP TEST  v0.3.1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#656a6d"))
	draw_string(font, Vector2(PANEL_X, 82), AREA_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#3f4548"))

	var buttons: Array[Rect2] = _buttons()
	var start_fill: Color = Color("#b7d3ae") if _can_start() or game_started or game_over else Color("#d5d1c8")
	_button(buttons[0], _start_button_label(), start_fill)

	for i in range(3):
		var unlocked: bool = _route_unlocked(i)
		var selected: bool = not place_mode and active_route == i and unlocked
		var fill: Color = route_colors[i] if selected else Color("#dcd7ce")
		if not unlocked:
			fill = Color("#e4e1da")
		_button(buttons[i + 1], "R%d%s" % [i + 1, "" if unlocked else " LOCK"], fill)

	_button(buttons[4], "Add District Stop", Color("#d6e2d3") if place_mode else Color("#dcd7ce"))
	_button(buttons[5], "Reset Run", Color("#dcd7ce"))
	_button(buttons[6], "Reload OSM", Color("#dcd7ce"))
	_button(buttons[7], "Zoom -", Color("#dcd7ce"))
	_button(buttons[8], "Zoom +", Color("#dcd7ce"))
	_button(buttons[9], "Reset View", Color("#dcd7ce"))

	draw_string(font, Vector2(PANEL_X, 486), "Delivered: %d" % delivered, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#33383b"))
	draw_string(font, Vector2(PANEL_X, 510), "Active districts: %d / %d" % [_active_district_count(), districts.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5f6467"))
	draw_string(font, Vector2(PANEL_X, 531), "Zoom: %d%%" % int(round(view_zoom * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5f6467"))

	draw_string(font, Vector2(PANEL_X, 568), status_text, HORIZONTAL_ALIGNMENT_LEFT, 236, 12, Color("#494f52"))

	var next_text: String = _next_reveal_text()
	draw_string(font, Vector2(PANEL_X, 612), next_text, HORIZONTAL_ALIGNMENT_LEFT, 236, 11, Color("#686d70"))

	var source: String = "OSM: cached" if loaded_from_cache else "OSM: live"
	draw_string(font, Vector2(PANEL_X, 652), source, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#767a7c"))
	draw_string(font, Vector2(PANEL_X, 671), "© OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#767a7c"))
	draw_string(font, Vector2(PANEL_X, 695), "Wheel zoom · MMB pan · Space start/pause", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#767a7c"))


func _start_button_label() -> String:
	if game_over:
		return "TRY AGAIN"
	if not game_started:
		return "START"
	if game_paused:
		return "RESUME"
	return "PAUSE"


func _active_district_count() -> int:
	var count: int = 0
	for district in districts:
		if bool(district["active"]):
			count += 1
	return count


func _next_reveal_text() -> String:
	for i in range(2, districts.size()):
		if not bool(districts[i]["active"]):
			return "Next district at %d delivered" % int(districts[i]["threshold"])
	return "All puzzle districts revealed"


func _button(rect: Rect2, label: String, fill: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color("#77736b"), false, 1.0)
	draw_string(
		font,
		rect.position + Vector2(7, 25),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 14.0,
		12,
		Color("#303437")
	)


func _draw_message(message: String, color: Color) -> void:
	draw_rect(MAP_RECT, Color(1.0, 1.0, 1.0, 0.82), true)
	draw_string(
		font,
		MAP_RECT.get_center() + Vector2(-260, 0),
		message,
		HORIZONTAL_ALIGNMENT_CENTER,
		520,
		19,
		color
	)


func _district_color(kind: String) -> Color:
	match kind:
		"residential":
			return Color("#ca8b64")
		"hub":
			return Color("#7664a7")
		"commercial":
			return Color("#bd6f98")
		"work":
			return Color("#5e819f")
		"education":
			return Color("#d29b43")
		_:
			return Color("#6f7476")


func _district_letter(kind: String) -> String:
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
		_:
			return "•"
