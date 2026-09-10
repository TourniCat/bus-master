extends Node2D

const BUILD: String = "0.2.0-osm-map"
const OVERPASS_URL: String = "https://overpass-api.de/api/interpreter"
const CACHE_PATH: String = "user://bus_master_gangnam_osm.json"

const MAP_RECT := Rect2(20, 80, 980, 600)
const PANEL_X: float = 1020.0

# Gangnam Station test area. About 2 km scale.
const SOUTH: float = 37.4890
const WEST: float = 127.0150
const NORTH: float = 37.5070
const EAST: float = 127.0400
const AREA_NAME: String = "Gangnam Station"

const MAX_STOPS: int = 12
const MAX_ROUTES: int = 3

var font: Font
var http: HTTPRequest
var graph := AStar2D.new()

var loading: bool = true
var error_text: String = ""
var loaded_from_cache: bool = false

var road_lines: Array[Dictionary] = []
var buildings: Array[PackedVector2Array] = []
var parks: Array[PackedVector2Array] = []
var waters: Array[PackedVector2Array] = []
var pois: Array[Dictionary] = []

var graph_positions: Array[Vector2] = []
var osm_node_to_local: Dictionary = {}

var stops: Array[Dictionary] = []
var routes: Array[Array] = [[], [], []]
var active_route: int = 0
var place_mode: bool = true
var status_text: String = "Loading OpenStreetMap..."

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
	http = HTTPRequest.new()
	http.timeout = 40.0
	add_child(http)
	http.request_completed.connect(_on_request_completed)
	_log("START build=%s godot=%s" % [
		BUILD, String(Engine.get_version_info().get("string", "unknown"))
	])
	_load_map(false)


func _log(message: String) -> void:
	print("[BUS_MASTER] %s" % message)


func _load_map(force_network: bool) -> void:
	loading = true
	error_text = ""
	loaded_from_cache = false
	status_text = "Loading OpenStreetMap..."
	_clear_map()

	if not force_network and FileAccess.file_exists(CACHE_PATH):
		var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
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
  node["amenity"](%s);
  node["shop"](%s);
  node["tourism"](%s);
  node["railway"="station"](%s);
);
out geom;
""" % [bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox]

	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"User-Agent: BusMasterPrototype/0.2"
	])
	var body: String = "data=" + query.uri_encode()
	var request_error: Error = http.request(
		OVERPASS_URL, headers, HTTPClient.METHOD_POST, body
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

	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

	_log("OSM download bytes=%d" % body.size())
	_parse_osm(parsed)


func _clear_map() -> void:
	road_lines.clear()
	buildings.clear()
	parks.clear()
	waters.clear()
	pois.clear()
	graph_positions.clear()
	osm_node_to_local.clear()
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
				_parse_polygon(element, buildings)
			elif String(tags.get("leisure", "")) == "park":
				_parse_polygon(element, parks)
			elif String(tags.get("natural", "")) == "water":
				_parse_polygon(element, waters)
		elif type_name == "node":
			_parse_poi(element, tags)

	loading = false
	if graph_positions.is_empty():
		_fail_parse("No drivable roads found in this area.")
		return

	status_text = "Map ready. Place stops on roads."
	_log("OSM ready roads=%d nodes=%d buildings=%d parks=%d water=%d poi=%d cache=%s" % [
		road_lines.size(), graph_positions.size(), buildings.size(),
		parks.size(), waters.size(), pois.size(), str(loaded_from_cache)
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
	if line.size() >= 2:
		road_lines.append({
			"points": line,
			"width": _road_width(road_class),
			"class": road_class
		})

	var count: int = mini(geom.size(), ids.size())
	for i in range(count):
		if not (geom[i] is Dictionary):
			continue
		var point: Dictionary = geom[i]
		if not point.has("lat") or not point.has("lon"):
			continue
		var osm_id: int = int(ids[i])
		var local_id: int = _graph_node(osm_id, _project(
			float(point["lat"]), float(point["lon"])
		))
		if i > 0:
			var previous_osm_id: int = int(ids[i - 1])
			if osm_node_to_local.has(previous_osm_id):
				var previous_local: int = int(osm_node_to_local[previous_osm_id])
				if previous_local != local_id and not graph.are_points_connected(previous_local, local_id):
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
			return 4.5
		"secondary":
			return 4.0
		"tertiary":
			return 3.2
		"residential", "living_street":
			return 2.4
		"service":
			return 1.5
		_:
			return 2.0


func _parse_polygon(element: Dictionary, target: Array) -> void:
	var geom_variant: Variant = element.get("geometry", [])
	if not (geom_variant is Array):
		return
	var geom: Array = geom_variant
	if geom.size() < 3:
		return
	var polygon := PackedVector2Array()
	for point_value in geom:
		if point_value is Dictionary:
			var point: Dictionary = point_value
			if point.has("lat") and point.has("lon"):
				polygon.append(_project(float(point["lat"]), float(point["lon"])))
	if polygon.size() >= 3:
		target.append(polygon)


func _parse_poi(element: Dictionary, tags: Dictionary) -> void:
	if not element.has("lat") or not element.has("lon"):
		return

	var amenity: String = String(tags.get("amenity", ""))
	var shop: String = String(tags.get("shop", ""))
	var tourism: String = String(tags.get("tourism", ""))
	var railway: String = String(tags.get("railway", ""))
	var kind: String = ""

	if railway == "station":
		kind = "station"
	elif amenity in ["school", "college", "university", "kindergarten"]:
		kind = "education"
	elif amenity in ["hospital", "clinic", "doctors"]:
		kind = "medical"
	elif amenity in ["bus_station", "ferry_terminal"]:
		kind = "transport"
	elif not shop.is_empty():
		kind = "shop"
	elif not tourism.is_empty():
		kind = "tourism"
	elif amenity in ["marketplace", "cinema", "theatre", "restaurant", "cafe", "fast_food"]:
		kind = "leisure"
	else:
		return

	pois.append({
		"pos": _project(float(element["lat"]), float(element["lon"])),
		"kind": kind,
		"name": String(tags.get("name", kind))
	})


func _project(lat: float, lon: float) -> Vector2:
	var x: float = (lon - WEST) / (EAST - WEST)
	var y: float = 1.0 - ((lat - SOUTH) / (NORTH - SOUTH))
	return MAP_RECT.position + Vector2(x * MAP_RECT.size.x, y * MAP_RECT.size.y)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S:
				place_mode = true
				status_text = "Stop mode: click a road."
			KEY_1:
				_choose_route(0)
			KEY_2:
				_choose_route(1)
			KEY_3:
				_choose_route(2)
			KEY_R:
				_clear_gameplay()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pointer(event.position)
	if event is InputEventScreenTouch and event.pressed:
		_pointer(event.position)


func _pointer(pos: Vector2) -> void:
	var buttons: Array[Rect2] = _buttons()
	for i in range(3):
		if buttons[i].has_point(pos):
			_choose_route(i)
			return
	if buttons[3].has_point(pos):
		place_mode = true
		status_text = "Stop mode: click a road."
		return
	if buttons[4].has_point(pos):
		_clear_gameplay()
		return
	if buttons[5].has_point(pos):
		_reload_osm()
		return

	if loading or not error_text.is_empty() or not MAP_RECT.has_point(pos):
		return

	if place_mode:
		_place_stop(pos)
	else:
		var stop_id: int = _find_stop(pos)
		if stop_id >= 0:
			_edit_route(stop_id)


func _buttons() -> Array[Rect2]:
	return [
		Rect2(PANEL_X, 126, 72, 34),
		Rect2(PANEL_X + 82, 126, 72, 34),
		Rect2(PANEL_X + 164, 126, 72, 34),
		Rect2(PANEL_X, 182, 236, 38),
		Rect2(PANEL_X, 240, 236, 38),
		Rect2(PANEL_X, 298, 236, 38)
	]


func _choose_route(index: int) -> void:
	active_route = index
	place_mode = false
	status_text = "Route %d: click stops in order." % (index + 1)
	_log("ACTION route=%d" % (index + 1))


func _place_stop(pos: Vector2) -> void:
	if stops.size() >= MAX_STOPS:
		status_text = "Stop limit reached (%d)." % MAX_STOPS
		return
	var graph_id: int = _nearest_graph_node(pos)
	if graph_id < 0:
		status_text = "No road close enough."
		return

	var snapped: Vector2 = graph_positions[graph_id]
	for stop in stops:
		var old_pos: Vector2 = stop["pos"]
		if old_pos.distance_to(snapped) < 22.0:
			status_text = "Too close to another stop."
			return

	stops.append({
		"graph_id": graph_id,
		"pos": snapped,
		"name": "Stop %d" % (stops.size() + 1)
	})
	status_text = "Placed Stop %d. Pick R1/R2/R3 to connect." % stops.size()
	_log("ACTION place_stop=%d graph=%d" % [stops.size(), graph_id])
	queue_redraw()


func _nearest_graph_node(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = 34.0
	for i in range(graph_positions.size()):
		var distance: float = pos.distance_to(graph_positions[i])
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _find_stop(pos: Vector2) -> int:
	var best: int = -1
	var best_distance: float = 18.0
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
	else:
		route.append(stop_id)
		status_text = "Route %d now has %d stops." % [active_route + 1, route.size()]
	routes[active_route] = route
	_log("ACTION route=%d stops=%d" % [active_route + 1, route.size()])
	queue_redraw()


func _clear_gameplay() -> void:
	stops.clear()
	routes = [[], [], []]
	active_route = 0
	place_mode = true
	status_text = "Cleared. Place stops on roads."
	_log("ACTION clear_gameplay")
	queue_redraw()


func _reload_osm() -> void:
	_clear_gameplay()
	if FileAccess.file_exists(CACHE_PATH):
		var absolute_path: String = ProjectSettings.globalize_path(CACHE_PATH)
		DirAccess.remove_absolute(absolute_path)
	_load_map(true)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#f4f2ec"), true)
	_draw_map()
	_draw_routes()
	_draw_stops()
	_draw_panel()

	if loading:
		_draw_message("Loading OpenStreetMap...", Color("#34383b"))
	elif not error_text.is_empty():
		_draw_message(error_text, Color("#a83f3f"))


func _draw_map() -> void:
	draw_rect(MAP_RECT, Color("#faf9f5"), true)

	for polygon in waters:
		draw_colored_polygon(polygon, Color("#d7e8ef"))
	for polygon in parks:
		draw_colored_polygon(polygon, Color("#dfead8"))
	for polygon in buildings:
		draw_colored_polygon(polygon, Color("#e5e1d9"))

	for road in road_lines:
		var line: PackedVector2Array = road["points"]
		var width: float = float(road["width"])
		if line.size() >= 2:
			draw_polyline(line, Color("#cbc8c1"), width + 2.0, true)
			draw_polyline(line, Color("#fffefa"), width, true)

	for poi in pois:
		draw_circle(poi["pos"], 2.8, _poi_color(String(poi["kind"])))

	draw_rect(MAP_RECT, Color("#aaa69d"), false, 1.0)


func _draw_routes() -> void:
	for route_index in range(routes.size()):
		var route: Array = routes[route_index]
		if route.size() < 2:
			continue
		for i in range(route.size() - 1):
			var a_stop: int = int(route[i])
			var b_stop: int = int(route[i + 1])
			var a_graph: int = int(stops[a_stop]["graph_id"])
			var b_graph: int = int(stops[b_stop]["graph_id"])
			var path: PackedVector2Array = graph.get_point_path(a_graph, b_graph)
			if path.size() >= 2:
				draw_polyline(path, Color("#fffdf8"), 9.0, true)
				draw_polyline(path, route_colors[route_index], 5.0, true)


func _draw_stops() -> void:
	for i in range(stops.size()):
		var pos: Vector2 = stops[i]["pos"]
		draw_circle(pos, 9.0, Color("#fffdf8"))
		draw_arc(pos, 9.0, 0.0, TAU, 24, Color("#303437"), 1.7, true)
		draw_string(
			font, pos + Vector2(-10, 26), "%d" % (i + 1),
			HORIZONTAL_ALIGNMENT_CENTER, 20, 11, Color("#34383b")
		)


func _draw_panel() -> void:
	draw_rect(Rect2(1000, 0, 280, 720), Color("#ede9e0"), true)
	draw_line(Vector2(1000, 0), Vector2(1000, 720), Color("#c7c1b6"), 1.0)

	draw_string(font, Vector2(PANEL_X, 34), "BUS MASTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#292e31"))
	draw_string(font, Vector2(PANEL_X, 58), "OSM MAP TEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#656a6d"))
	draw_string(font, Vector2(PANEL_X, 88), AREA_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#3f4548"))

	var buttons: Array[Rect2] = _buttons()
	for i in range(3):
		var fill: Color = route_colors[i] if (not place_mode and active_route == i) else Color("#dcd7ce")
		_button(buttons[i], "R%d" % (i + 1), fill)
	_button(buttons[3], "Place Stop", Color("#d6e2d3") if place_mode else Color("#dcd7ce"))
	_button(buttons[4], "Clear Stops / Routes", Color("#dcd7ce"))
	_button(buttons[5], "Reload OSM", Color("#dcd7ce"))

	draw_string(font, Vector2(PANEL_X, 382), "Stops: %d / %d" % [stops.size(), MAX_STOPS], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#464b4e"))
	draw_string(font, Vector2(PANEL_X, 410), "Road nodes: %d" % graph_positions.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#666b6e"))
	draw_string(font, Vector2(PANEL_X, 432), "Buildings: %d" % buildings.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#666b6e"))
	draw_string(font, Vector2(PANEL_X, 454), "POIs: %d" % pois.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#666b6e"))

	draw_string(font, Vector2(PANEL_X, 510), status_text, HORIZONTAL_ALIGNMENT_LEFT, 236, 13, Color("#53595c"))

	var source: String = "Source: cache" if loaded_from_cache else "Source: live OSM"
	draw_string(font, Vector2(PANEL_X, 635), source, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#74787a"))
	draw_string(font, Vector2(PANEL_X, 658), "© OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#74787a"))
	draw_string(font, Vector2(PANEL_X, 684), "S: place   1/2/3: route   R: clear", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#74787a"))


func _button(rect: Rect2, label: String, fill: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color("#77736b"), false, 1.0)
	draw_string(
		font, rect.position + Vector2(8, 23), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16.0, 13, Color("#303437")
	)


func _draw_message(message: String, color: Color) -> void:
	draw_rect(MAP_RECT, Color(1.0, 1.0, 1.0, 0.78), true)
	draw_string(
		font, MAP_RECT.get_center() + Vector2(-240, 0), message,
		HORIZONTAL_ALIGNMENT_CENTER, 480, 20, color
	)


func _poi_color(kind: String) -> Color:
	match kind:
		"station", "transport":
			return Color("#745f9d")
		"education":
			return Color("#d59b49")
		"medical":
			return Color("#cc6666")
		"shop":
			return Color("#bd79a5")
		"tourism", "leisure":
			return Color("#6ca17f")
		_:
			return Color("#777777")
