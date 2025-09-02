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
  
  // Rota çizgilerini takip etmek için
  final List<maplibre.Line> _routeLines = [];
  
  // Erişilebilir nokta sayısını takip etmek için
  int _totalAccessiblePoints = 0;

  LatLng? startPoint;
  LatLng? endPoint;
  List<LatLng> routePoints = [];
  double? routeDistanceKm;
  double? routeDurationMin;
  String selectedFilter = 'hepsi';
  String selectedProfile = 'wheelchair'; // Sadece tekerlekli sandalye

  @override
  void initState() {
    super.initState();
    _listenFirestoreMarkers();
    
    // Konumu hemen göster
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setInitialLocation();
    });

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
    
    // Harita hazır olduğunda konumu hemen göster
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCurrentLocationVisible();
    });
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

    // Eğer konum marker'ı yoksa oluştur, varsa güncelle
    if (_currentLocationSymbol == null) {
      final symbol = await _controller!.addSymbol(
        maplibre.SymbolOptions(
          geometry: maplibre.LatLng(pos.latitude, pos.longitude),
          textField: 'Konumum', // Simge yerine "Konumum" yazısı
          textSize: 14.0, // Yazı boyutu
          textColor: '#00FF00', // Yeşil yazı
          textHaloColor: '#FFFFFF', // Beyaz halo
          textHaloWidth: 2.0, // Halo genişliği
          iconImage: null, // Simge yok
        ),
      );
      _currentLocationSymbol = symbol;
    } else {
      // Mevcut marker'ı güncelle
      try {
        await _controller!.updateSymbol(
          _currentLocationSymbol!,
          maplibre.SymbolOptions(
            geometry: maplibre.LatLng(pos.latitude, pos.longitude),
          ),
        );
      } catch (e) {
        // Eğer güncelleme başarısız olursa, yeni marker oluştur
        try {
          await _controller!.removeSymbol(_currentLocationSymbol!);
        } catch (_) {}
        _currentLocationSymbol = null;
        updateCurrentLocationMarker(pos);
      }
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
    if (pos != null) {
      setState(() {
        startPoint = pos;
      });
      
      if (_controller != null) {
        await _controller!.animateCamera(
          maplibre.CameraUpdate.newLatLngZoom(
            maplibre.LatLng(pos.latitude, pos.longitude),
            15,
          ),
        );
        updateCurrentLocationMarker(pos);
      }
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
              textColor: _getMarkerTextColor(marker.type), // Her tür için farklı renk
            ),
          );
        } else {
          // Mevcut konumdan uzaklığı hesapla
          String? distanceText;
          if (startPoint != null) {
            final distance = Geolocator.distanceBetween(
              startPoint!.latitude, startPoint!.longitude,
              lat, lng
            );
            if (distance < 1000) {
              distanceText = '${distance.toInt()}m';
            } else {
              distanceText = '${(distance / 1000).toStringAsFixed(1)}km';
            }
          }

          final symbol = await _controller!.addSymbol(
            maplibre.SymbolOptions(
              geometry: maplibre.LatLng(lat, lng),
              iconImage: _getMapLibreIcon(marker.type),
              iconSize: _getMarkerSize(marker.type),
              iconColor: _getMarkerColor(marker.type).value.toRadixString(16),
              iconHaloColor: '#FFFFFF', // Beyaz halo ekle
              iconHaloWidth: 2.0, // Daha kalın halo
              textField: distanceText != null 
                ? '${_typeToLabel(marker.type)}\n$distanceText'
                : _typeToLabel(marker.type), // Tür etiketi ve mesafe ekle
              textSize: 11.0, // Biraz daha büyük metin
              textColor: _getMarkerTextColor(marker.type), // Her tür için farklı renk
              textHaloColor: '#FFFFFF', // Beyaz metin halo
              textHaloWidth: 2.0, // Daha kalın metin halo
              textOffset: const Offset(0, 1.5), // Metni icon'un altına yerleştir
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
      
      // Toplam erişilebilir nokta sayısını güncelle
      setState(() {
        _totalAccessiblePoints = snap.docs.length;
      });
    });
    
    // Konum marker'ını her zaman göster
    _ensureCurrentLocationVisible();
  }

  // Konum marker'ının her zaman görünür olmasını sağla
  void _ensureCurrentLocationVisible() async {
    if (_controller == null) return;
    
    // Eğer konum henüz alınmadıysa, al
    if (startPoint == null) {
      final pos = await _getCurrentLocation();
      if (pos != null) {
        setState(() {
          startPoint = pos;
        });
        updateCurrentLocationMarker(pos);
      }
    } else {
      // Konum zaten varsa, marker'ı güncelle
      updateCurrentLocationMarker(startPoint!);
    }
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
    
    // Kesikli çizgileri temizle
    for (final line in _routeLines) {
      try {
        await _controller!.removeLine(line);
      } catch (_) {}
    }
    _routeLines.clear();
  }

  // Ana rotayı kesikli çizgiler ile çiz
  Future<void> _drawMainRoute(List<LatLng> points) async {
    if (points.length < 2) return;

    // Ana rotayı kesikli çizgiler halinde çiz
    final coordinates = points.map((p) => maplibre.LatLng(p.latitude, p.longitude)).toList();
    
    // Kesikli çizgi efekti için rotayı parçalara böl
    final dashLength = 15.0; // Çizgi uzunluğu
    final gapLength = 8.0;   // Boşluk uzunluğu
    
    List<maplibre.Line> dashLines = [];
    
    for (int i = 0; i < coordinates.length - 1; i++) {
      final start = coordinates[i];
      final end = coordinates[i + 1];
      
      // İki nokta arasındaki mesafeyi hesapla
      final distance = _calculateDistance(start, end);
      final segments = (distance / (dashLength + gapLength)).ceil();
      
      for (int j = 0; j < segments; j++) {
        final progress = j / segments;
        final nextProgress = (j + 1) / segments;
        
        // Çizgi parçasının başlangıç ve bitiş noktalarını hesapla
        final dashStart = _interpolatePoint(start, end, progress);
        final dashEnd = _interpolatePoint(start, end, nextProgress);
        
        // Çizgi parçasını çiz
        final dashLine = await _controller!.addLine(
          maplibre.LineOptions(
            geometry: [dashStart, dashEnd],
            lineWidth: 6.0,
            lineColor: '#FF8C00', // Turuncu renk
            lineOpacity: 0.9,
          ),
        );
        
        dashLines.add(dashLine);
      }
    }
    
    // Ana rota çizgisini temizle ve kesikli çizgileri sakla
    _routeLine = null;
    _routeLines.addAll(dashLines);

    // Başlangıç ve bitiş noktalarını belirgin şekilde işaretle
    await _addStartEndMarkers();
  }

  // İki nokta arasındaki mesafeyi hesapla
  double _calculateDistance(maplibre.LatLng start, maplibre.LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude, start.longitude,
      end.latitude, end.longitude
    );
  }

  // İki nokta arasında interpolasyon yap
  maplibre.LatLng _interpolatePoint(maplibre.LatLng start, maplibre.LatLng end, double progress) {
    final lat = start.latitude + (end.latitude - start.latitude) * progress;
    final lng = start.longitude + (end.longitude - start.longitude) * progress;
    return maplibre.LatLng(lat, lng);
  }

  // Başlangıç ve bitiş noktalarını belirgin şekilde işaretle
  Future<void> _addStartEndMarkers() async {
    if (startPoint == null || endPoint == null || _controller == null) return;

    // Başlangıç noktası - Yeşil (Konumum)
    final startSymbol = await _controller!.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(startPoint!.latitude, startPoint!.longitude),
        iconImage: 'marker-15',
        iconSize: 3.0, // Daha büyük boyut
        iconColor: '#4CAF50', // Yeşil
        iconHaloColor: '#FFFFFF', // Beyaz halo
        iconHaloWidth: 2.0, // Halo genişliği
        textField: 'Konumum', // Etiket ekle
        textSize: 12.0,
        textColor: '#FFFFFF',
        textHaloColor: '#000000',
        textHaloWidth: 1.0,
      ),
    );
    _routeSymbols.add(startSymbol);

    // Bitiş noktası - Kırmızı (Hedef)
    final endSymbol = await _controller!.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(endPoint!.latitude, endPoint!.longitude),
        iconImage: 'marker-15',
        iconSize: 3.0, // Daha büyük boyut
        iconColor: '#F44336', // Kırmızı
        iconHaloColor: '#FFFFFF', // Beyaz halo
        iconHaloWidth: 2.0, // Halo genişliği
        textField: 'Hedef', // Etiket ekle
        textSize: 12.0,
        textColor: '#FFFFFF',
        textHaloColor: '#000000',
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

      // Kesikli çizgileri temizle
      for (final line in _routeLines) {
        try {
          await _controller!.removeLine(line);
        } catch (_) {}
      }
      _routeLines.clear();

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

      // Kesikli çizgileri temizle
      for (final line in _routeLines) {
        try {
          await _controller!.removeLine(line);
        } catch (_) {}
      }
      _routeLines.clear();

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

  // MapLibre için uygun icon'ları döndür
  String _getMapLibreIcon(String type) {
    switch (type) {
      case 'rampa':
        return 'marker-15'; // Ramp için standart marker
      case 'asansör':
        return 'marker-15'; // Asansör için standart marker
      case 'yaya_gecidi':
        return 'marker-15'; // Yaya geçidi için standart marker
      case 'trafik_isigi':
        return 'marker-15'; // Trafik ışığı için standart marker
      case 'ust_gecit':
        return 'marker-15'; // Üst/alt geçit için standart marker
      default:
        return 'marker-15'; // Varsayılan marker
    }
  }

  // Marker boyutlarını type'a göre ayarla
  double _getMarkerSize(String type) {
    switch (type) {
      case 'rampa':
        return 2.5; // Ramp için daha büyük
      case 'asansör':
        return 2.2; // Asansör için daha büyük
      case 'yaya_gecidi':
        return 2.0; // Yaya geçidi için daha büyük
      case 'trafik_isigi':
        return 2.0; // Trafik ışığı için daha büyük
      case 'ust_gecit':
        return 2.2; // Üst/alt geçit için daha büyük
      default:
        return 2.0; // Varsayılan boyut
    }
  }

  Color _getMarkerColor(String type) {
    switch (type) {
      case 'rampa':
        return Colors.green.shade700; // Daha koyu yeşil
      case 'asansör':
        return Colors.orange.shade700; // Daha koyu turuncu
      case 'yaya_gecidi':
        return Colors.blue.shade700; // Daha koyu mavi
      case 'trafik_isigi':
        return Colors.red.shade700; // Daha koyu kırmızı
      case 'ust_gecit':
        return Colors.purple.shade700; // Daha koyu mor
      default:
        return Colors.grey.shade700; // Daha koyu gri
    }
  }

  // Her nokta türü için farklı metin rengi
  String _getMarkerTextColor(String type) {
    switch (type) {
      case 'rampa':
        return '#006400'; // Koyu yeşil metin
      case 'asansör':
        return '#CC6600'; // Koyu turuncu metin
      case 'yaya_gecidi':
        return '#0033CC'; // Koyu mavi metin
      case 'trafik_isigi':
        return '#CC0000'; // Koyu kırmızı metin
      case 'ust_gecit':
        return '#660066'; // Koyu mor metin
      default:
        return '#333333'; // Koyu gri metin
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

  // En yakın erişilebilir noktaları vurgula
  Future<void> _highlightNearestAccessiblePoints() async {
    if (startPoint == null || _controller == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance.collection('markers').get();
      
      List<MapEntry<MarkerModel, double>> accessiblePoints = [];
      
      for (final doc in snapshot.docs) {
        final marker = MarkerModel.fromMap(doc.data());
        final point = LatLng(marker.latitude, marker.longitude);
        
        // Sadece rampa ve asansör türündeki noktaları al
        if (marker.type != 'rampa' && marker.type != 'asansör') continue;
        
        // Mevcut konumdan uzaklığı hesapla
        final distance = Geolocator.distanceBetween(
          startPoint!.latitude, startPoint!.longitude,
          point.latitude, point.longitude
        );
        
        accessiblePoints.add(MapEntry(marker, distance));
      }
      
      // Uzaklığa göre sırala
      accessiblePoints.sort((a, b) => a.value.compareTo(b.value));
      
      // En yakın 3 noktayı al
      final nearestPoints = accessiblePoints.take(3).toList();
      
      if (nearestPoints.isNotEmpty) {
        // En yakın noktaları vurgula
        for (final entry in nearestPoints) {
          final marker = entry.key;
          final distance = entry.value;
          
          // Marker'ı daha büyük ve parlak yap
          if (_symbols.containsKey(marker.type + marker.latitude.toString() + marker.longitude.toString())) {
            // Mevcut marker'ı güncelle
            await _controller!.updateSymbol(
              _symbols[marker.type + marker.latitude.toString() + marker.longitude.toString()]!,
              maplibre.SymbolOptions(
                iconSize: _getMarkerSize(marker.type) * 1.5, // %50 daha büyük
                iconHaloColor: '#FFFF00', // Sarı halo
                iconHaloWidth: 3.0, // Daha kalın halo
              ),
            );
          }
        }
        
        // En yakın noktayı haritada göster
        final nearestPoint = nearestPoints.first;
        final marker = nearestPoint.key;
        final distance = nearestPoint.value;
        
        await _controller!.animateCamera(
          maplibre.CameraUpdate.newLatLngZoom(
            maplibre.LatLng(marker.latitude, marker.longitude),
            18,
          ),
        );
        
        _showMessage('En yakın ${_typeToLabel(marker.type)}: ${distance < 1000 ? '${distance.toInt()}m' : '${(distance / 1000).toStringAsFixed(1)}km'} uzaklıkta');
      } else {
        _showMessage('Yakınınızda erişilebilir nokta bulunamadı');
      }
    } catch (e) {
      _showMessage('En yakın noktalar bulunamadı: $e');
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
          iconSize: 3.0, // Daha büyük boyut
          iconColor: '#FF0000', // Parlak kırmızı
          iconHaloColor: '#FFFFFF', // Beyaz halo
          iconHaloWidth: 2.0, // Halo genişliği
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
                          Expanded(
                            child: Text(
                              "Mesafe: ${routeDistanceKm!.toStringAsFixed(2)} km | Süre: ${routeDurationMin!.toStringAsFixed(0)} dk",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Dropdown Butonları
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedProfile,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF64B5F6),
                              iconEnabledColor: Colors.white,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              items: const [
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
              // Ana Butonlar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Konumuma Git Butonu
                    Expanded(
                      flex: 1,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: InkWell(
                          onTap: () async {
                            final pos = await _getCurrentLocation();
                            if (pos != null) {
                              centerOnCurrentLocation(pos);
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF64B5F6), Color(0xFF1976D2)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.my_location, color: Colors.white, size: 28),
                                SizedBox(height: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Erişim Noktası Ekle Butonu
                    Expanded(
                      flex: 1,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: InkWell(
                          onTap: () async {
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
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.green, Color(0xFF388E3C)], // green.shade700 yerine hex kodu
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_location_alt, color: Colors.white, size: 28),
                                SizedBox(height: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // En Yakın Noktalar Butonu
                    Expanded(
                      flex: 1,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: InkWell(
                          onTap: () async {
                            if (startPoint != null) {
                              await _highlightNearestAccessiblePoints();
                            } else {
                              _showMessage('Önce konumunuzu alın');
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.near_me, color: Colors.white, size: 24),
                                SizedBox(height: 4),
                              ],
                            ),
                          ),
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
                    Icon(
                      _getIcon(marker.type),
                      color: _getMarkerColor(marker.type),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _typeToLabel(marker.type),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getMarkerColor(marker.type).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getMarkerColor(marker.type),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        marker.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getMarkerColor(marker.type),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.description, color: Colors.white70),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          marker.description,
                          style: const TextStyle(fontSize: 16, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white70),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Koordinatlar: ${marker.latitude.toStringAsFixed(5)}, ${marker.longitude.toStringAsFixed(5)}",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                if (marker.createdAt != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.white70),
                      const SizedBox(width: 12),
                      Text(
                        "Eklenme: ${DateFormat('dd.MM.yyyy HH:mm').format(marker.createdAt!)}",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "${marker.likes} kişi faydalı buldu",
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
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