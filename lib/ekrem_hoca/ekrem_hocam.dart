import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const String _mapTilerKey = 'RUlFyEFNM0RNo0FrC3ch';
  static const String _orsApiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4MGE1MzhlMWIwNTRiOGZiOTE5YTg3M2NmYzQ3MzJjIiwiaCI6Im11cm11cjY0In0=';
  final String _styleUrl =
      'https://api.maptiler.com/maps/openstreetmap/style.json?key=$_mapTilerKey';

  maplibre.MaplibreMapController? _controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _markerSub;
  Timer? locationTimer;

  final Map<String, maplibre.Symbol> _symbols = {};
  maplibre.Symbol? _currentLocationSymbol;
  maplibre.Symbol? _endPointSymbol;
  maplibre.Line? _routeLine;

  LatLng? startPoint;
  LatLng? endPoint;
  List<LatLng> routePoints = [];
  double? routeDistanceKm;
  double? routeDurationMin;
  String selectedFilter = 'hepsi';
  String selectedProfile = 'foot-walking';

  @override
  void initState() {
    super.initState();
    _listenFirestoreMarkers();
    _setInitialLocation();

    locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final pos = await _getCurrentLocation();
      if (pos != null) {
        updateCurrentLocationMarker(pos);
      }
    });
  }

  @override
  void dispose() {
    _markerSub?.cancel();
    locationTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _onMapCreated(maplibre.MaplibreMapController controller) {
    _controller = controller;
  }

  Future<LatLng?> _getCurrentLocation() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showMessage("Konum servisi kapalı");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMessage("Konum izni reddedildi");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showMessage("Konum izni kalıcı olarak reddedildi");
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      _showMessage("Konum alınamadı: $e");
      return null;
    }
  }

  void updateCurrentLocationMarker(LatLng pos) async {
    setState(() {
      startPoint = pos;
    });

    if (_controller == null) return;

    if (_currentLocationSymbol != null) {
      await _controller!.updateSymbol(
        _currentLocationSymbol!,
        maplibre.SymbolOptions(
          geometry: maplibre.LatLng(pos.latitude, pos.longitude),
        ),
      );
    } else {
      final symbol = await _controller!.addSymbol(
        maplibre.SymbolOptions(
          geometry: maplibre.LatLng(pos.latitude, pos.longitude),
          iconImage: 'marker-15',
          iconSize: 1.6,
          textField: 'Konumum',
          textOffset: const Offset(0, 1.5),
          iconColor: '#00FF00',
        ),
      );
      _currentLocationSymbol = symbol;
    }
  }

  void centerOnCurrentLocation(LatLng pos) async {
    setState(() {
      startPoint = pos;
    });

    if (_controller != null) {
      await _controller!.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(pos.latitude, pos.longitude),
          17,
        ),
      );
      updateCurrentLocationMarker(pos);
    }
  }

  Future<void> _setInitialLocation() async {
    final pos = await _getCurrentLocation();
    if (pos != null && _controller != null) {
      setState(() {
        startPoint = pos;
      });
      await _controller!.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(pos.latitude, pos.longitude),
          15,
        ),
      );
      updateCurrentLocationMarker(pos);
    }
  }

  void _listenFirestoreMarkers() {
    final coll = FirebaseFirestore.instance
        .collection('markers')
        .orderBy('createdAt', descending: true)
        .limit(50);

    _markerSub = coll.snapshots().listen((snap) async {
      if (_controller == null) return;

      final currentIds = snap.docs.map((d) => d.id).toSet();
      final knownIds = _symbols.keys.toSet();

      for (final removedId in knownIds.difference(currentIds)) {
        final sym = _symbols.remove(removedId);
        if (sym != null) {
          try {
            await _controller!.removeSymbol(sym);
          } catch (_) {}
        }
      }

      for (final doc in snap.docs) {
        final marker = MarkerModel.fromMap(doc.data());
        if (selectedFilter != 'hepsi' && marker.type != selectedFilter) {
          continue;
        }

        final lat = marker.latitude;
        final lng = marker.longitude;
        final docId = doc.id;

        if (_symbols.containsKey(docId)) {
          await _controller!.updateSymbol(
            _symbols[docId]!,
            maplibre.SymbolOptions(
              geometry: maplibre.LatLng(lat, lng),
              textField: _typeToLabel(marker.type),
            ),
          );
        } else {
          final symbol = await _controller!.addSymbol(
            maplibre.SymbolOptions(
              geometry: maplibre.LatLng(lat, lng),
              iconImage: 'marker-15',
              iconSize: 1.6,
              textField: _typeToLabel(marker.type),
              textOffset: const Offset(0, 1.5),
              iconColor: _getMarkerColor(marker.type).value.toRadixString(16),
            ),
          );
          _symbols[docId] = symbol;

          _controller!.onSymbolTapped.add((symbol) {
            if (symbol == _symbols[docId]) {
              _showMarkerDetails(marker, docId);
            }
          });
        }
      }
    });
  }

  Future<List<LatLng>> _getInitialRoute(LatLng start, LatLng end) async {
    const double cellSizeMeters = 2.0;
    Offset startCell = _latLngToGrid(start, start, cellSizeMeters);
    Offset endCell = _latLngToGrid(end, start, cellSizeMeters);
    Set<Offset> blockedCells = {};

    List<Offset> pathCells = _aStarSearch(startCell, endCell, blockedCells);

    if (pathCells.isEmpty) {
      print('No initial path found between $start and $end');
      return [];
    }

    return pathCells
        .map((cell) => _gridToLatLng(cell, start, cellSizeMeters))
        .toList();
  }

  Future<List<LatLng>> _getAccessibleWaypointsAlongRoute(
    LatLng start,
    LatLng end,
    List<LatLng> initialRoute,
  ) async {
    final accessibilitySnapshot = await FirebaseFirestore.instance
        .collection('markers')
        .get();

    List<MarkerModel> accessibilityPoints = accessibilitySnapshot.docs
        .map((doc) => MarkerModel.fromMap(doc.data()))
        .toList();

    List<LatLng> validPoints = accessibilityPoints
        .where((m) {
          if (selectedProfile == 'wheelchair') {
            return m.type == 'rampa' || m.type == 'asansör';
          }
          return true;
        })
        .map((m) => LatLng(m.latitude, m.longitude))
        .toList();

    const double maxDeviationMeters = 50;
    List<LatLng> waypoints = [];
    for (final point in validPoints) {
      double minDistance = double.infinity;
      for (final routePoint in initialRoute) {
        double distance = Geolocator.distanceBetween(
          point.latitude,
          point.longitude,
          routePoint.latitude,
          routePoint.longitude,
        );
        if (distance < minDistance) {
          minDistance = distance;
        }
      }
      if (minDistance <= maxDeviationMeters) {
        waypoints.add(point);
      }
    }

    waypoints.sort((a, b) {
      double distA = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        a.latitude,
        a.longitude,
      );
      double distB = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        b.latitude,
        b.longitude,
      );
      return distA.compareTo(distB);
    });

    print('Waypoints: $waypoints');
    return waypoints;
  }

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final String url =
        'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

    List<LatLng> initialRoutePoints = await _getInitialRoute(start, end);
    List<LatLng> waypoints = await _getAccessibleWaypointsAlongRoute(
      start,
      end,
      initialRoutePoints,
    );

    if (selectedProfile == 'wheelchair' && waypoints.isEmpty) {
      print('No accessible waypoints for wheelchair profile');
      _showMessage('Rota bulunamadı: Erişilebilir nokta yok');
      return [];
    }

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': _orsApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'coordinates': [
            [start.longitude, start.latitude],
            ...waypoints
                .map((wp) => [wp.longitude, wp.latitude])
                .take(5), // ORS limiti: 5 ara nokta
            [end.longitude, end.latitude],
          ],
          'elevation': false,
          'preference': 'recommended',
        }),
      );

      print('ORS İstek: $url');
      print(
        'ORS Koordinatlar: ${jsonEncode({
          'coordinates': [
            [start.longitude, start.latitude],
            ...waypoints.map((wp) => [wp.longitude, wp.latitude]),
            [end.longitude, end.latitude],
          ],
        })}',
      );
      print('ORS Yanıt Kodu: ${response.statusCode}');
      print('ORS Yanıt Gövdesi: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['features'][0]['geometry']['coordinates'] as List;
        final props = data['features'][0]['properties']['summary'];
        setState(() {
          routeDistanceKm = props['distance'] / 1000;
          routeDurationMin = props['duration'] / 60;
        });
        return coords.map((c) => LatLng(c[1], c[0])).toList();
      } else {
        throw Exception(
          'Rota alınamadı: ${response.statusCode}, ${response.body}',
        );
      }
    } catch (e) {
      print('Rota alınamadı istisna: $e');
      _showMessage('Rota alınamadı: $e');
      return [];
    }
  }

  Offset _latLngToGrid(LatLng point, LatLng origin, double cellSizeMeters) {
    double dx = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      origin.latitude,
      point.longitude,
    );
    double dy = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      point.latitude,
      origin.longitude,
    );

    if (point.longitude < origin.longitude) dx = -dx;
    if (point.latitude < origin.latitude) dy = -dy;

    return Offset(
      (dx / cellSizeMeters).roundToDouble(),
      (dy / cellSizeMeters).roundToDouble(),
    );
  }

  LatLng _gridToLatLng(Offset cell, LatLng origin, double cellSizeMeters) {
    double northMeters = cell.dy * cellSizeMeters;
    double eastMeters = cell.dx * cellSizeMeters;

    double lat = origin.latitude + (northMeters / 111320.0);
    double lng =
        origin.longitude +
        (eastMeters / (111320.0 * cos(origin.latitude * pi / 180.0)));

    return LatLng(lat, lng);
  }

  List<Offset> _aStarSearch(
    Offset start,
    Offset goal,
    Set<Offset> blockedCells,
  ) {
    final openSet = <GridNode>[
      GridNode(
        x: start.dx.toInt(),
        y: start.dy.toInt(),
        gCost: 0,
        hCost: _heuristic(start, goal),
      ),
    ];
    final closedSet = <GridNode>{};

    while (openSet.isNotEmpty) {
      openSet.sort((a, b) => a.fCost.compareTo(b.fCost));
      final current = openSet.removeAt(0);
      closedSet.add(current);

      if (current.x == goal.dx.toInt() && current.y == goal.dy.toInt()) {
        return _reconstructPath(current);
      }

      for (final dir in [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
        Offset(1, 1),
        Offset(-1, 1),
        Offset(1, -1),
        Offset(-1, -1),
      ]) {
        final nx = current.x + dir.dx.toInt();
        final ny = current.y + dir.dy.toInt();
        final neighborCell = Offset(nx.toDouble(), ny.toDouble());

        if (blockedCells.contains(neighborCell)) continue;
        if (closedSet.any((n) => n.x == nx && n.y == ny)) continue;

        final gCost =
            current.gCost + (dir.dx.abs() + dir.dy.abs() > 1 ? 1.414 : 1);
        final hCost = _heuristic(neighborCell, goal);

        final existingIndex = openSet.indexWhere((n) => n.x == nx && n.y == ny);

        if (existingIndex == -1) {
          openSet.add(
            GridNode(x: nx, y: ny, gCost: gCost, hCost: hCost, parent: current),
          );
        } else {
          if (gCost < openSet[existingIndex].gCost) {
            openSet[existingIndex] = GridNode(
              x: nx,
              y: ny,
              gCost: gCost,
              hCost: hCost,
              parent: current,
            );
          }
        }
      }
    }
    return [];
  }

  double _heuristic(Offset a, Offset b) {
    return (a.dx - b.dx).abs() + (a.dy - b.dy).abs();
  }

  List<Offset> _reconstructPath(GridNode node) {
    final path = <Offset>[];
    GridNode? current = node;
    while (current != null) {
      path.add(Offset(current.x.toDouble(), current.y.toDouble()));
      current = current.parent;
    }
    return path.reversed.toList();
  }

  Future<void> drawRoute() async {
    if (startPoint == null || endPoint == null || _controller == null) {
      _showMessage('Başlangıç veya bitiş noktası eksik.');
      return;
    }

    final points = await getRoute(startPoint!, endPoint!);
    if (points.isNotEmpty) {
      setState(() {
        routePoints = points;
      });

      if (_routeLine != null) {
        try {
          await _controller!.removeLine(_routeLine!);
        } catch (_) {}
        _routeLine = null;
      }

      final line = await _controller!.addLine(
        maplibre.LineOptions(
          geometry: points
              .map((p) => maplibre.LatLng(p.latitude, p.longitude))
              .toList(),
          lineWidth: 5.0,
          lineColor: '#800080',
          lineOpacity: 0.9,
        ),
      );

      _routeLine = line;

      final bounds = _boundsFromLatLngList(points);
      if (bounds != null) {
        await _controller!.animateCamera(
          maplibre.CameraUpdate.newLatLngBounds(
            bounds,
            left: 40,
            top: 40,
            right: 40,
            bottom: 40,
          ),
        );
      }
    } else {
      _showMessage(
        'Rota oluşturulamadı. Lütfen başka bir hedef seçin veya erişim noktası ekleyin.',
      );
    }
  }

  void clearRoute() async {
    if (_routeLine != null && _controller != null) {
      try {
        await _controller!.removeLine(_routeLine!);
      } catch (_) {}
      _routeLine = null;
    }
    if (_endPointSymbol != null && _controller != null) {
      try {
        await _controller!.removeSymbol(_endPointSymbol!);
      } catch (_) {}
      _endPointSymbol = null;
    }
    setState(() {
      startPoint = null;
      endPoint = null;
      routePoints.clear();
      routeDistanceKm = null;
      routeDurationMin = null;
    });
  }

  maplibre.LatLngBounds? _boundsFromLatLngList(List<LatLng> coords) {
    if (coords.isEmpty) return null;
    double minLat = coords.first.latitude, maxLat = coords.first.latitude;
    double minLng = coords.first.longitude, maxLng = coords.first.longitude;
    for (final c in coords) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }
    return maplibre.LatLngBounds(
      southwest: maplibre.LatLng(minLat, minLng),
      northeast: maplibre.LatLng(maxLat, maxLng),
    );
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'rampa':
        return Icons.accessible_forward;
      case 'asansör':
        return Icons.elevator;
      case 'yaya_gecidi':
        return Icons.directions_walk;
      case 'trafik_isigi':
        return Icons.traffic;
      case 'ust_gecit':
        return Icons.alt_route;
      default:
        return Icons.location_on;
    }
  }

  Color _getMarkerColor(String type) {
    switch (type) {
      case 'rampa':
        return Colors.green;
      case 'asansör':
        return Colors.orange;
      case 'yaya_gecidi':
        return Colors.blue;
      case 'trafik_isigi':
        return Colors.red;
      case 'ust_gecit':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _typeToLabel(String type) {
    switch (type) {
      case 'rampa':
        return 'Rampa';
      case 'asansör':
        return 'Asansör';
      case 'yaya_gecidi':
        return 'Yaya Geçidi';
      case 'trafik_isigi':
        return 'Trafik Işığı';
      case 'ust_gecit':
        return 'Üst/Alt Geçit';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Harita",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: const Color(0xFF1976D2),
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: clearRoute,
            tooltip: 'Rota Sıfırla',
          ),
        ],
      ),
      body: Stack(
        children: [
          maplibre.MaplibreMap(
            styleString: _styleUrl,
            initialCameraPosition: const maplibre.CameraPosition(
              target: maplibre.LatLng(38.7569, 30.5387),
              zoom: 15.0,
            ),
            onMapCreated: _onMapCreated,
            myLocationEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            onMapLongClick: (point, latLng) async {
              if (_controller == null) return;
              setState(() {
                endPoint = LatLng(latLng.latitude, latLng.longitude);
              });
              if (_endPointSymbol != null) {
                await _controller!.removeSymbol(_endPointSymbol!);
              }
              _endPointSymbol = await _controller!.addSymbol(
                maplibre.SymbolOptions(
                  geometry: latLng,
                  iconImage: 'marker-15',
                  iconSize: 1.6,
                  textField: 'Hedef',
                  textOffset: const Offset(0, 1.5),
                  iconColor: '#FF0000',
                ),
              );
              await drawRoute();
            },
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (routeDistanceKm != null && routeDurationMin != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Card(
                    color: const Color(0xFF1976D2),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.directions, color: Colors.white),
                          const SizedBox(width: 12),
                          Text(
                            "Mesafe: ${routeDistanceKm!.toStringAsFixed(2)} km | Süre: ${routeDurationMin!.toStringAsFixed(0)} dk",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Card(
                        color: const Color(0xFF1976D2),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: detaySecenekleri(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card(
                        color: const Color(0xFF64B5F6),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedProfile,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF64B5F6),
                              iconEnabledColor: Colors.white,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'foot-walking',
                                  child: Text('Yürüyüş'),
                                ),
                                DropdownMenuItem(
                                  value: 'wheelchair',
                                  child: Text('Tekerlekli Sandalye'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() => selectedProfile = value!);
                                if (startPoint != null && endPoint != null) {
                                  drawRoute();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FloatingActionButton.extended(
                        heroTag: 'konum',
                        onPressed: () async {
                          final pos = await _getCurrentLocation();
                          if (pos != null) {
                            centerOnCurrentLocation(pos);
                          }
                        },
                        backgroundColor: const Color(0xFF64B5F6),
                        icon: const Icon(Icons.my_location, size: 28),
                        label: const Text(
                          "Konumuma Git",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        extendedPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FloatingActionButton.extended(
                        heroTag: 'markerEkle',
                        onPressed: () async {
                          String?
                          selectedType = await showModalBottomSheet<String>(
                            context: context,
                            builder: (context) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.accessible_forward,
                                    ),
                                    title: const Text('Rampa'),
                                    onTap: () =>
                                        Navigator.pop(context, 'rampa'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.elevator),
                                    title: const Text('Asansör'),
                                    onTap: () =>
                                        Navigator.pop(context, 'asansör'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.directions_walk),
                                    title: const Text('Yaya Geçidi'),
                                    onTap: () =>
                                        Navigator.pop(context, 'yaya_gecidi'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.traffic),
                                    title: const Text('Trafik Işığı'),
                                    onTap: () =>
                                        Navigator.pop(context, 'trafik_isigi'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.alt_route),
                                    title: const Text('Üst/Alt Geçit'),
                                    onTap: () =>
                                        Navigator.pop(context, 'ust_gecit'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (selectedType != null) {
                            final pos = await _getCurrentLocation();
                            if (pos != null) {
                              String? description = await showDialog<String>(
                                context: context,
                                builder: (context) {
                                  TextEditingController controller =
                                      TextEditingController();
                                  return AlertDialog(
                                    title: const Text("Açıklama Girin"),
                                    content: TextField(
                                      controller: controller,
                                      decoration: const InputDecoration(
                                        hintText: "Kısa açıklama",
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, null),
                                        child: const Text("İptal"),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          context,
                                          controller.text,
                                        ),
                                        child: const Text("Ekle"),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (description != null &&
                                  description.isNotEmpty) {
                                await FirebaseFirestore.instance
                                    .collection('markers')
                                    .add(
                                      MarkerModel(
                                        type: selectedType,
                                        latitude: pos.latitude,
                                        longitude: pos.longitude,
                                        description: description,
                                        likes: 0,
                                        createdAt: DateTime.now(),
                                      ).toMap(),
                                    );
                                _showMessage(
                                  "Erişim noktası başarıyla eklendi!",
                                );
                              }
                            }
                          }
                        },
                        backgroundColor: Colors.green,
                        icon: const Icon(Icons.add_location_alt, size: 28),
                        label: const Text(
                          "Erişim Noktası Ekle",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        extendedPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DropdownButton<String> detaySecenekleri() {
    return DropdownButton<String>(
      value: selectedFilter,
      dropdownColor: const Color(0xFF1976D2),
      iconEnabledColor: Colors.white,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      items: const [
        DropdownMenuItem(value: 'hepsi', child: Text('Hepsi')),
        DropdownMenuItem(value: 'rampa', child: Text('Rampa')),
        DropdownMenuItem(value: 'asansör', child: Text('Asansör')),
        DropdownMenuItem(value: 'yaya_gecidi', child: Text('Yaya Geçidi')),
        DropdownMenuItem(value: 'trafik_isigi', child: Text('Trafik Işığı')),
        DropdownMenuItem(value: 'ust_gecit', child: Text('Üst/Alt Geçit')),
      ],
      onChanged: (value) {
        setState(() {
          selectedFilter = value!;
        });
        _listenFirestoreMarkers();
      },
    );
  }

  void _showMarkerDetails(MarkerModel marker, String docId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: const Color(0xFF1976D2),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white54,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.accessible, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      _typeToLabel(marker.type),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.description, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        marker.description,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      "${marker.latitude.toStringAsFixed(5)}, ${marker.longitude.toStringAsFixed(5)}",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                if (marker.createdAt != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat(
                          'dd.MM.yyyy HH:mm',
                        ).format(marker.createdAt!),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('markers')
                            .doc(docId)
                            .update({'likes': marker.likes + 1});
                        Navigator.pop(context);
                        _listenFirestoreMarkers();
                      },
                      icon: const Icon(Icons.thumb_up),
                      label: const Text('Faydalı'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[400],
                        foregroundColor: Colors.white,
                      ),
                    ),
                    Text(
                      "${marker.likes} kişi faydalı buldu",
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

class MarkerModel {
  final String type;
  final double latitude;
  final double longitude;
  final String description;
  final int likes;
  final DateTime? createdAt;

  MarkerModel({
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.likes,
    this.createdAt,
  });

  factory MarkerModel.fromMap(Map<String, dynamic> map) {
    return MarkerModel(
      type: map['type'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      description: map['description'] as String,
      likes: map['likes'] as int,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'likes': likes,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    };
  }
}

class GridNode {
  final int x;
  final int y;
  final double gCost;
  final double hCost;
  final GridNode? parent;

  double get fCost => gCost + hCost;

  GridNode({
    required this.x,
    required this.y,
    required this.gCost,
    required this.hCost,
    this.parent,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridNode && x == other.x && y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}
