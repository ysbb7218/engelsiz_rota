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
  
  // Rota sembollerini takip etmek için
  final List<maplibre.Symbol> _routeSymbols = [];

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

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    print('=== TEKERLEKLİ SANDALYE İÇİN BASİT ROTA ALGORİTMASI ===');
    print('📍 Başlangıç: ${start.latitude}, ${start.longitude}');
    print('🎯 Bitiş: ${end.latitude}, ${end.longitude}');
    print('♿ Profil: $selectedProfile');

    try {
      // 1. Erişilebilir noktaları bul (sadece rampa ve asansör)
      List<LatLng> accessiblePoints = await _findAccessiblePoints(start, end);
      print('♿ ${accessiblePoints.length} erişilebilir nokta bulundu');

      // 2. En iyi 1-2 noktayı seç (dallanmayı önlemek için)
      List<LatLng> selectedWaypoints = _selectBestWaypoints(start, end, accessiblePoints);
      print('🔄 ${selectedWaypoints.length} waypoint seçildi');

      // 3. Basit rota oluştur
      List<LatLng> route = await _createSimpleRoute(start, end, selectedWaypoints);
      
      if (route.isNotEmpty) {
        print('✅ Rota başarıyla oluşturuldu: ${route.length} nokta');
        return route;
      } else {
        print('⚠️ Rota oluşturulamadı, düz rota deneniyor');
        return await _createDirectRoute(start, end);
      }
    } catch (e) {
      print('❌ Rota oluşturma hatası: $e');
      return await _createDirectRoute(start, end);
    }
  }

  // Erişilebilir noktaları bul (sadece rampa ve asansör)
  Future<List<LatLng>> _findAccessiblePoints(LatLng start, LatLng end) async {
    final snapshot = await FirebaseFirestore.instance.collection('markers').get();
    
    List<LatLng> accessiblePoints = [];
    final totalDistance = Geolocator.distanceBetween(
      start.latitude, start.longitude,
      end.latitude, end.longitude
    );

    for (final doc in snapshot.docs) {
      final marker = MarkerModel.fromMap(doc.data());
      final point = LatLng(marker.latitude, marker.longitude);
      
      // Sadece rampa ve asansör türündeki noktaları al
      if (marker.type != 'rampa' && marker.type != 'asansör') continue;
      
      // Başlangıç ve bitiş noktalarını hariç tut
      if (Geolocator.distanceBetween(start.latitude, start.longitude, point.latitude, point.longitude) < 50 || 
          Geolocator.distanceBetween(end.latitude, end.longitude, point.latitude, point.longitude) < 50) continue;
      
      // Sapma kontrolü - %20'den fazla sapma yok
      final distanceFromStart = Geolocator.distanceBetween(start.latitude, start.longitude, point.latitude, point.longitude);
      final distanceToEnd = Geolocator.distanceBetween(point.latitude, point.longitude, end.latitude, end.longitude);
      final detour = (distanceFromStart + distanceToEnd) - totalDistance;
      
      if (detour <= totalDistance * 0.2) { // %20'den az sapma
        accessiblePoints.add(point);
      }
    }

    return accessiblePoints;
  }

  // En iyi waypoint'leri seç (basit yaklaşım)
  List<LatLng> _selectBestWaypoints(LatLng start, LatLng end, List<LatLng> points) {
    if (points.isEmpty) return [];
    
    // Her nokta için basit puan hesapla
    List<MapEntry<LatLng, double>> scoredPoints = [];
    
    for (final point in points) {
      double score = _calculateSimpleScore(start, end, point);
      scoredPoints.add(MapEntry(point, score));
    }
    
    // Puana göre sırala
    scoredPoints.sort((a, b) => b.value.compareTo(a.value));
    
    // Sadece en iyi 1-2 noktayı al (dallanmayı önlemek için)
    final topPoints = scoredPoints.take(2).map((e) => e.key).toList();
    
    // Başlangıçtan bitişe doğru sırala
    topPoints.sort((a, b) {
      final distA = Geolocator.distanceBetween(start.latitude, start.longitude, a.latitude, a.longitude);
      final distB = Geolocator.distanceBetween(start.latitude, start.longitude, b.latitude, b.longitude);
      return distA.compareTo(distB);
    });
    
    return topPoints;
  }

  // Basit puan hesaplama
  double _calculateSimpleScore(LatLng start, LatLng end, LatLng point) {
        double score = 0.0;
        
    final totalDistance = Geolocator.distanceBetween(start.latitude, start.longitude, end.latitude, end.longitude);
    final distanceFromStart = Geolocator.distanceBetween(start.latitude, start.longitude, point.latitude, point.longitude);
    final distanceToEnd = Geolocator.distanceBetween(point.latitude, point.longitude, end.latitude, end.longitude);
    final detour = (distanceFromStart + distanceToEnd) - totalDistance;
    
    // Sapma kontrolü (0-50 puan)
    if (detour <= totalDistance * 0.1) score += 50; // %10'dan az sapma
    else if (detour <= totalDistance * 0.2) score += 30; // %20'den az sapma
    else score += 10; // Diğer durumlar
    
    // Rota ortasına yakınlık (0-30 puan)
    final routeProgress = distanceFromStart / (distanceFromStart + distanceToEnd);
    if (routeProgress >= 0.3 && routeProgress <= 0.7) score += 30; // Rota ortası
    else if (routeProgress >= 0.2 && routeProgress <= 0.8) score += 20; // Rota kenarları
    else score += 5; // Başlangıç/bitiş yakını
    
    // Yön tutarlılığı (0-20 puan)
    final bearing1 = _getBearing(start, point);
    final bearing2 = _getBearing(point, end);
    final bearingDiff = _getBearingDifference(bearing1, bearing2).abs();
    
    if (bearingDiff <= 45) score += 20; // İyi yön
    else if (bearingDiff <= 90) score += 10; // Kabul edilebilir
    else score += 0; // Kötü yön
    
    return score;
  }

  // Basit rota oluştur
  Future<List<LatLng>> _createSimpleRoute(LatLng start, LatLng end, List<LatLng> waypoints) async {
    if (waypoints.isEmpty) return await _createDirectRoute(start, end);
    
    final String url = 'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';
    
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
            ...waypoints.map((wp) => [wp.longitude, wp.latitude]),
            [end.longitude, end.latitude],
          ],
          'elevation': false,
          'preference': 'fastest', // En hızlı rota
          'continue_straight': true, // Düz git
        }),
      );

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
        print('⚠️ ORS API hatası: ${response.statusCode}');
        return await _createDirectRoute(start, end);
      }
    } catch (e) {
      print('❌ Rota oluşturma hatası: $e');
      return await _createDirectRoute(start, end);
    }
  }

  // Düz rota oluştur (waypoint olmadan)
  Future<List<LatLng>> _createDirectRoute(LatLng start, LatLng end) async {
      final String url = 'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';
      
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
            [end.longitude, end.latitude],
          ],
          'elevation': false,
          'preference': 'fastest',
          'continue_straight': true,
        }),
      );

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
        throw Exception('Düz rota alınamadı: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Düz rota hatası: $e');
      return [];
    }
  }

  // Yardımcı fonksiyonlar
  double _getBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final deltaLng = (to.longitude - from.longitude) * pi / 180;
    
    final y = sin(deltaLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng);
    
    double bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
  }

  double _getBearingDifference(double bearing1, double bearing2) {
    double diff = bearing2 - bearing1;
    
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    
    return diff;
  }

  // Eski A* ve grid fonksiyonları kaldırıldı - basit yaklaşım kullanılıyor

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

      // Eski rotaları temizle
      await _clearAllRoutes();

      // Ana rotayı ok işaretleri ile çiz
      await _drawMainRoute(points);

      // Başlangıç ve bitiş noktalarını belirgin şekilde işaretle
      await _addStartEndMarkers();

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

  // Tüm rotaları temizle
  Future<void> _clearAllRoutes() async {
    if (_routeLine != null) {
      try {
        await _controller!.removeLine(_routeLine!);
      } catch (_) {}
      _routeLine = null;
    }
  }

  // Ana rotayı ok işaretleri ile çiz
  Future<void> _drawMainRoute(List<LatLng> points) async {
    if (points.length < 2) return;

    // Ana rotayı çiz
    final coordinates = points.map((p) => maplibre.LatLng(p.latitude, p.longitude)).toList();
    
    final line = await _controller!.addLine(
      maplibre.LineOptions(
        geometry: coordinates,
        lineWidth: 6.0,
        lineColor: '#1976D2', // Mavi
        lineOpacity: 0.9,
      ),
    );
    _routeLine = line;

    // Başlangıç ve bitiş noktalarını belirgin şekilde işaretle
    await _addStartEndMarkers();
  }



  // Başlangıç ve bitiş noktalarını belirgin şekilde işaretle
  Future<void> _addStartEndMarkers() async {
    if (startPoint == null || endPoint == null || _controller == null) return;

    // Başlangıç noktası - Yeşil
    final startSymbol = await _controller!.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(startPoint!.latitude, startPoint!.longitude),
        iconImage: 'marker-15',
        iconSize: 2.0,
        iconColor: '#4CAF50', // Yeşil
        textField: 'BAŞLANGIÇ',
        textOffset: const Offset(0, 2),
        textColor: '#4CAF50',
        textSize: 14,
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.0,
      ),
    );
    _routeSymbols.add(startSymbol);

    // Bitiş noktası - Kırmızı
    final endSymbol = await _controller!.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(endPoint!.latitude, endPoint!.longitude),
        iconImage: 'marker-15',
        iconSize: 2.0,
        iconColor: '#F44336', // Kırmızı
        textField: 'HEDEF',
        textOffset: const Offset(0, 2),
        textColor: '#F44336',
        textSize: 14,
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.0,
      ),
    );
    _routeSymbols.add(endSymbol);
  }

  // Önceki rota işaretlerini temizle (yeni hedef seçildiğinde)
  Future<void> _clearPreviousRouteIndicators() async {
    if (_controller != null) {
      // Ana rota çizgisini temizle
      if (_routeLine != null) {
        try {
          await _controller!.removeLine(_routeLine!);
        } catch (_) {}
        _routeLine = null;
      }

      // Bitiş noktası sembolünü temizle
      if (_endPointSymbol != null) {
        try {
          await _controller!.removeSymbol(_endPointSymbol!);
        } catch (_) {}
        _endPointSymbol = null;
      }

      // Rota sembollerini güvenli şekilde temizle
      for (final symbol in _routeSymbols) {
        try {
          await _controller!.removeSymbol(symbol);
        } catch (_) {}
      }
      _routeSymbols.clear();

      // Sadece marker'ları yeniden yükle (erişilebilir noktalar)
      _listenFirestoreMarkers();
    }

    setState(() {
      routePoints.clear();
      routeDistanceKm = null;
      routeDurationMin = null;
    });
  }

  void clearRoute() async {
    if (_controller != null) {
      // Ana rota çizgisini temizle
      if (_routeLine != null) {
        try {
          await _controller!.removeLine(_routeLine!);
        } catch (_) {}
        _routeLine = null;
      }

      // Bitiş noktası sembolünü temizle
      if (_endPointSymbol != null) {
        try {
          await _controller!.removeSymbol(_endPointSymbol!);
        } catch (_) {}
        _endPointSymbol = null;
      }

      // Rota sembollerini güvenli şekilde temizle
      for (final symbol in _routeSymbols) {
        try {
          await _controller!.removeSymbol(symbol);
        } catch (_) {}
      }
      _routeSymbols.clear();

      // Sadece marker'ları yeniden yükle (erişilebilir noktalar)
      _listenFirestoreMarkers();
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
              
              String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                        leading: const Icon(Icons.directions),
                        title: const Text('Hedef Nokta Ekle'),
                        onTap: () => Navigator.pop(context, 'target'),
            ),
            ListTile(
                        leading: const Icon(Icons.add_location_alt),
                        title: const Text('Erişim Noktası Ekle'),
                        onTap: () => Navigator.pop(context, 'marker'),
                      ),
          ],
        );
      },
    );

              if (action == 'target') {
      setState(() {
        endPoint = LatLng(latLng.latitude, latLng.longitude);
      });
      await _clearPreviousRouteIndicators(); // Yeni hedef seçildiğinde önceki rotayı temizle
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
              } else if (action == 'marker') {
                String? selectedType = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.accessible_forward),
                          title: const Text('Rampa'),
                          onTap: () => Navigator.pop(context, 'rampa'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.elevator),
                          title: const Text('Asansör'),
                          onTap: () => Navigator.pop(context, 'asansör'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.directions_walk),
                          title: const Text('Yaya Geçidi'),
                          onTap: () => Navigator.pop(context, 'yaya_gecidi'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.traffic),
                          title: const Text('Trafik Işığı'),
                          onTap: () => Navigator.pop(context, 'trafik_isigi'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.alt_route),
                          title: const Text('Üst/Alt Geçit'),
                          onTap: () => Navigator.pop(context, 'ust_gecit'),
                        ),
                      ],
                    );
                  },
                );

                if (selectedType != null) {
                  String? description = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      TextEditingController controller = TextEditingController();
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
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text("İptal"),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, controller.text),
                            child: const Text("Ekle"),
                          ),
                        ],
                      );
                    },
                  );

                  if (description != null && description.isNotEmpty) {
                    await FirebaseFirestore.instance.collection('markers').add(
                          MarkerModel(
                            type: selectedType,
                            latitude: latLng.latitude,
                            longitude: latLng.longitude,
                            description: description,
                            likes: 0,
                            createdAt: DateTime.now(),
                          ).toMap(),
                        );
                    _showMessage("Erişim noktası başarıyla eklendi!");
                  }
                }
    }
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
                          String? selectedType = await showModalBottomSheet<String>(
                            context: context,
                            builder: (context) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.accessible_forward),
                                    title: const Text('Rampa'),
                                    onTap: () => Navigator.pop(context, 'rampa'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.elevator),
                                    title: const Text('Asansör'),
                                    onTap: () => Navigator.pop(context, 'asansör'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.directions_walk),
                                    title: const Text('Yaya Geçidi'),
                                    onTap: () => Navigator.pop(context, 'yaya_gecidi'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.traffic),
                                    title: const Text('Trafik Işığı'),
                                    onTap: () => Navigator.pop(context, 'trafik_isigi'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.alt_route),
                                    title: const Text('Üst/Alt Geçit'),
                                    onTap: () => Navigator.pop(context, 'ust_gecit'),
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
                                        onPressed: () => Navigator.pop(context, null),
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
                              if (description != null && description.isNotEmpty) {
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
                                _showMessage("Erişim noktası başarıyla eklendi!");
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
                        DateFormat('dd.MM.yyyy HH:mm').format(marker.createdAt!),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
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
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                      onPressed: () async {
                            bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
            return AlertDialog(
                                  title: const Text("Marker'ı Sil"),
            content: const Text(
                                    "Bu erişim noktasını silmek istediğinize emin misiniz?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("İptal"),
              ),
                                    TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Sil"),
              ),
            ],
        );
      },
    );

                            if (confirm == true) {
        await FirebaseFirestore.instance
            .collection('markers')
            .doc(docId)
            .delete();
                              _showMessage("Erişim noktası başarıyla silindi!");
                              Navigator.pop(context);
      _listenFirestoreMarkers();
                            }
                          },
                          icon: const Icon(Icons.delete),
                          label: const Text('Sil'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[400],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
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

