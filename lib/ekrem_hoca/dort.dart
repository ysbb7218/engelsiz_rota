import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
              iconImage: _getMarkerIcon(marker.type),
              iconSize: 1.8,
              iconColor: _getMarkerColor(marker.type).value.toRadixString(16),
            ),
          );
        } else {
          final symbol = await _controller!.addSymbol(
            maplibre.SymbolOptions(
              geometry: maplibre.LatLng(lat, lng),
              iconImage: _getMarkerIcon(marker.type),
              iconSize: 1.8,
              textField: _typeToLabel(marker.type),
              textOffset: const Offset(0, 2.0),
              iconColor: _getMarkerColor(marker.type).value.toRadixString(16),
              textColor: '#FFFFFF',
              textHaloColor: '#000000',
              textHaloWidth: 1.0,
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

  // Marker türüne göre icon seç
  String _getMarkerIcon(String type) {
    switch (type) {
      case 'rampa':
        return 'marker-15'; // Yeşil marker
      case 'asansör':
        return 'marker-15'; // Turuncu marker
      case 'yaya_gecidi':
        return 'marker-15'; // Mavi marker
      case 'trafik_isigi':
        return 'marker-15'; // Kırmızı marker
      case 'ust_gecit':
        return 'marker-15'; // Mor marker
      default:
        return 'marker-15';
    }
  }

  // Gereksiz initial route fonksiyonu kaldırıldı - ORS API kullanılıyor

  // Gereksiz erişilebilir nokta bulma fonksiyonu kaldırıldı - basit sistem kullanılıyor

  // Gereksiz waypoint optimizasyon fonksiyonları kaldırıldı - basit sistem kullanılıyor

  // Gereksiz grid fonksiyonları kaldırıldı - ORS API kullanılıyor

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final String url =
        'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

    print('=== ROTA OLUŞTURMA BAŞLADI ===');
    print('📍 Başlangıç: ${start.latitude}, ${start.longitude}');
    print('🎯 Bitiş: ${end.latitude}, ${end.longitude}');
    print('🚶 Profil: $selectedProfile');

    try {
      // 1. Önce ORS API'den temel rotayı al
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
          'preference': 'fastest', // Daha hızlı rotalar için
          'continue_straight': false, // Daha esnek rotalar için
        }),
      );

      print('🌐 ORS İstek: $url');
      print('📡 ORS Yanıt Kodu: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['features'][0]['geometry']['coordinates'] as List;
        final props = data['features'][0]['properties']['summary'];
        
        // Temel rota noktalarını al
        List<LatLng> baseRoute = coords.map((c) => LatLng(c[1], c[0])).toList();
        
        // Mesafe ve süre bilgilerini güncelle
        setState(() {
          routeDistanceKm = props['distance'] / 1000;
          routeDurationMin = props['duration'] / 60;
        });
        
        print('✅ Temel rota alındı: ${baseRoute.length} nokta');
        print('📏 Mesafe: ${routeDistanceKm?.toStringAsFixed(2)} km, ⏱️ Süre: ${routeDurationMin?.toStringAsFixed(0)} dk');
        
        // 2. Temel rota üzerinde erişilebilir noktaları bul
        List<LatLng> accessibleWaypoints = await _findAccessibleWaypointsOnRoute(
          start, end, baseRoute
        );
        
        if (accessibleWaypoints.isNotEmpty) {
          print('🎯 ${accessibleWaypoints.length} erişilebilir nokta bulundu, rota optimize ediliyor...');
          
          // 3. Rota optimizasyonu yap
          List<LatLng> optimizedRoute = await _optimizeRouteWithWaypoints(
            start, end, baseRoute, accessibleWaypoints
          );
          
          print('🚀 Optimize edilmiş rota hazır: ${optimizedRoute.length} nokta');
          return optimizedRoute;
        } else {
          print('ℹ️ Erişilebilir nokta bulunamadı, temel rota kullanılıyor');
          // Temel rotayı da yumuşat
          return _smoothRoute(baseRoute);
        }
      } else {
        print('❌ ORS API hatası: ${response.statusCode}');
        print('📋 Response Body: ${response.body}');
        throw Exception('Rota alınamadı: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('💥 Rota oluşturma hatası: $e');
      _showMessage('Rota alınamadı: $e');
      return [];
    }
  }

  // Rota üzerinde erişilebilir noktaları bul - BASİTLEŞTİRİLMİŞ VERSİYON
  Future<List<LatLng>> _findAccessibleWaypointsOnRoute(
    LatLng start,
    LatLng end,
    List<LatLng> baseRoute,
  ) async {
    try {
      print('=== ERİŞİLEBİLİR NOKTA ARAMA (GELİŞTİRİLMİŞ) ===');
      
      // Firestore'dan tüm erişilebilir noktaları al
      final querySnapshot = await FirebaseFirestore.instance
          .collection('markers')
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('❌ Erişilebilir nokta bulunamadı');
        return [];
      }

      print('📊 Toplam ${querySnapshot.docs.length} erişilebilir nokta bulundu');
      
      List<MapEntry<MarkerModel, double>> scoredPoints = [];

      for (final doc in querySnapshot.docs) {
        final marker = MarkerModel.fromMap(doc.data());
        final markerLatLng = LatLng(marker.latitude, marker.longitude);

        // Başlangıç ve bitiş noktalarını hariç tut (daha geniş alan)
        if (_calculateDistance(start, markerLatLng) < 100 ||
            _calculateDistance(end, markerLatLng) < 100) {
          continue;
        }
        
        // Rota üzerindeki en yakın noktaya olan mesafeyi hesapla
        double minDistanceToRoute = double.infinity;
        
        for (final routePoint in baseRoute) {
          final distance = _calculateDistance(routePoint, markerLatLng);
          if (distance < minDistanceToRoute) {
            minDistanceToRoute = distance;
          }
        }

        // Rota üzerinde çok uzak noktaları filtrele (200m - daha sıkı filtre)
        if (minDistanceToRoute > 200) {
          continue;
        }

        // Yön tutarlılığı kontrolü - ters istikameti önle
        final startToMarker = _getBearing(start, markerLatLng);
        final markerToEnd = _getBearing(markerLatLng, end);
        final startToEnd = _getBearing(start, end);
        
        final bearingDiff1 = _getBearingDifference(startToMarker, startToEnd).abs();
        final bearingDiff2 = _getBearingDifference(markerToEnd, startToEnd).abs();
        
        // Çok büyük yön sapması varsa filtrele
        if (bearingDiff1 > 90 || bearingDiff2 > 90) {
          continue; // Ters istikamet - bu noktayı kullanma
        }

        // Basit puanlama sistemi - sadece 4 kriter
        double score = 0.0;

        // 1. Rota yakınlığı (0-100 puan)
        score += (200 - minDistanceToRoute) / 200 * 100;

        // 2. Erişilebilirlik türü puanı (0-100 puan)
        if (selectedProfile == 'wheelchair') {
          if (marker.type == 'rampa') score += 100;
          else if (marker.type == 'asansör') score += 80;
          else score += 40;
        } else {
          if (marker.type == 'yaya_gecidi') score += 100;
          else if (marker.type == 'trafik_isigi') score += 80;
          else score += 40;
        }

        // 3. Sapma kontrolü (0-100 puan) - çok önemli
        final distanceFromStart = _calculateDistance(start, markerLatLng);
        final distanceToEnd = _calculateDistance(markerLatLng, end);
        final totalRouteDistance = _calculateDistance(start, end);
        final detourDistance = (distanceFromStart + distanceToEnd) - totalRouteDistance;
        
        if (detourDistance <= 100) {
          score += 100; // Çok az sapma
        } else if (detourDistance <= 300) {
          score += 50; // Orta sapma
        } else {
          score -= 50; // Çok fazla sapma için ceza
        }

        // 4. Yön tutarlılığı puanı (0-100 puan) - yeni eklenen
        final avgBearingDiff = (bearingDiff1 + bearingDiff2) / 2;
        if (avgBearingDiff <= 30) {
          score += 100; // Mükemmel yön tutarlılığı
        } else if (avgBearingDiff <= 60) {
          score += 70; // İyi yön tutarlılığı
        } else if (avgBearingDiff <= 90) {
          score += 30; // Kabul edilebilir yön tutarlılığı
        } else {
          score -= 30; // Kötü yön tutarlılığı için ceza
        }

        scoredPoints.add(MapEntry(marker, score));
        
        print('   📊 ${marker.type}: Puan: ${score.toStringAsFixed(1)} - Rota mesafesi: ${minDistanceToRoute.toStringAsFixed(0)}m, Sapma: ${detourDistance.toStringAsFixed(0)}m, Yön farkı: ${avgBearingDiff.toStringAsFixed(1)}°');
      }

      if (scoredPoints.isEmpty) {
        print('⚠️ Uygun erişilebilir nokta bulunamadı!');
        return [];
      }

      // Puana göre sırala (yüksek puan önce)
      scoredPoints.sort((a, b) => b.value.compareTo(a.value));

      // SADECE EN YÜKSEK PUANLI 2 NOKTAYI AL (daha az nokta = daha tutarlı rota)
      final topPoints = scoredPoints.take(2).map((e) => LatLng(e.key.latitude, e.key.longitude)).toList();

      print('🎯 Seçilen ${topPoints.length} nokta (maksimum 2):');
      for (int i = 0; i < topPoints.length; i++) {
        final point = topPoints[i];
        final marker = scoredPoints.firstWhere((e) => 
          e.key.latitude == point.latitude && e.key.longitude == point.longitude
        );
        final distance = _calculateDistance(start, point);
        final bearing = _getBearing(start, point);
        print('   ${i + 1}. ${marker.key.type} - Puan: ${marker.value.toStringAsFixed(1)} - Mesafe: ${distance.toStringAsFixed(0)}m, Yön: ${bearing.toStringAsFixed(1)}°');
      }

      return topPoints;
    } catch (e) {
      print('❌ Erişilebilir nokta arama hatası: $e');
      return [];
    }
  }

  // Waypoint'lerle rotayı optimize et - BASİTLEŞTİRİLMİŞ VERSİYON
  Future<List<LatLng>> _optimizeRouteWithWaypoints(
    LatLng start, LatLng end, List<LatLng> baseRoute, List<LatLng> waypoints
  ) async {
    if (waypoints.isEmpty) return baseRoute;
    
    print('=== ROTA OPTİMİZASYONU (BASİTLEŞTİRİLMİŞ) ===');
    
    try {
      // Waypoint'leri basit mesafe sıralaması ile düzenle
      List<LatLng> orderedWaypoints = _simpleWaypointOrdering(start, end, waypoints);
      
      print('🔄 Sıralanmış waypoint\'ler:');
      for (int i = 0; i < orderedWaypoints.length; i++) {
        final wp = orderedWaypoints[i];
        final distance = _calculateDistance(start, wp);
        print('   ${i + 1}. ${wp.latitude.toStringAsFixed(6)}, ${wp.longitude.toStringAsFixed(6)} - Mesafe: ${distance.toStringAsFixed(0)}m');
      }
      
      // ORS API'ye waypoint'lerle birlikte istek gönder
      final String url = 'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': _orsApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'coordinates': [
            [start.longitude, start.latitude],
            ...orderedWaypoints.map((wp) => [wp.longitude, wp.latitude]),
            [end.longitude, end.latitude],
          ],
          'elevation': false,
          'preference': 'fastest', // Daha hızlı rotalar için
          'continue_straight': false, // Daha esnek rotalar için
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['features'][0]['geometry']['coordinates'] as List;
        final props = data['features'][0]['properties']['summary'];
        
        // Optimize edilmiş rota noktalarını al
        List<LatLng> optimizedRoute = coords.map((c) => LatLng(c[1], c[0])).toList();
        
        // Rota yumuşatma uygula (daha tutarlı rota için)
        optimizedRoute = _smoothRoute(optimizedRoute);
        
        // Mesafe ve süre bilgilerini güncelle
        setState(() {
          routeDistanceKm = props['distance'] / 1000;
          routeDurationMin = props['duration'] / 60;
        });
        
        print('✅ Optimize edilmiş rota başarıyla oluşturuldu');
        print('📏 Yeni mesafe: ${routeDistanceKm?.toStringAsFixed(2)} km, Süre: ${routeDurationMin?.toStringAsFixed(0)} dk');
        print('🔄 Rota nokta sayısı: ${optimizedRoute.length}');
        
        return optimizedRoute;
      } else {
        print('⚠️ Optimizasyon API hatası: ${response.statusCode}');
        print('📋 Temel rota kullanılıyor');
        return baseRoute;
      }
    } catch (e) {
      print('❌ Rota optimizasyon hatası: $e');
      print('📋 Temel rota kullanılıyor');
      return baseRoute;
    }
  }

  // Basit waypoint sıralama - mesafe tabanlı
  List<LatLng> _simpleWaypointOrdering(LatLng start, LatLng end, List<LatLng> waypoints) {
    if (waypoints.length <= 1) return waypoints;
    
    print('=== WAYPOINT SIRALAMA (GELİŞTİRİLMİŞ) ===');
    
    // Her waypoint için rota üzerindeki pozisyonu hesapla
    List<MapEntry<LatLng, double>> waypointPositions = [];
    
    for (final waypoint in waypoints) {
      // Başlangıç noktasına olan mesafe
      final distanceFromStart = _calculateDistance(start, waypoint);
      
      // Hedef noktasına olan mesafe
      final distanceToEnd = _calculateDistance(waypoint, end);
      
      // Toplam düz rota mesafesi
      final directDistance = _calculateDistance(start, end);
      
      // Sapma mesafesi (başlangıç -> waypoint -> hedef) - (başlangıç -> hedef)
      final detourDistance = (distanceFromStart + distanceToEnd) - directDistance;
      
      // Rota ilerleme oranı (0.0 = başlangıç, 1.0 = hedef)
      final routeProgress = distanceFromStart / (distanceFromStart + distanceToEnd);
      
      // Puanlama sistemi - ters istikameti önle
      double score = 0.0;
      
      // 1. Sapma kontrolü (0-100 puan) - çok önemli
      if (detourDistance <= 50) {
        score += 100; // Çok az sapma
      } else if (detourDistance <= 150) {
        score += 70; // Az sapma
      } else if (detourDistance <= 300) {
        score += 30; // Orta sapma
      } else {
        score -= 50; // Çok fazla sapma için ceza
      }
      
      // 2. Rota ilerleme kontrolü (0-100 puan) - ters istikameti önle
      if (routeProgress >= 0.2 && routeProgress <= 0.8) {
        score += 100; // Rota ortası - ideal
      } else if (routeProgress >= 0.1 && routeProgress <= 0.9) {
        score += 60; // Rota kenarları - kabul edilebilir
      } else {
        score -= 30; // Başlangıç/bitiş yakını - ters istikamet riski
      }
      
      // 3. Yön kontrolü (0-100 puan) - ters istikameti önle
      final startToWaypoint = _getBearing(start, waypoint);
      final waypointToEnd = _getBearing(waypoint, end);
      final startToEnd = _getBearing(start, end);
      
      // Yön tutarlılığı kontrolü
      final bearingDiff1 = (_getBearingDifference(startToWaypoint, startToEnd)).abs();
      final bearingDiff2 = (_getBearingDifference(waypointToEnd, startToEnd)).abs();
      
      if (bearingDiff1 <= 45 && bearingDiff2 <= 45) {
        score += 100; // Yön tutarlı
      } else if (bearingDiff1 <= 90 && bearingDiff2 <= 90) {
        score += 50; // Yön kabul edilebilir
      } else {
        score -= 50; // Ters istikamet - büyük ceza
      }
      
      waypointPositions.add(MapEntry(waypoint, score));
      
      print('   📍 ${waypoint.latitude.toStringAsFixed(6)}, ${waypoint.longitude.toStringAsFixed(6)}');
      print('     📏 Başlangıçtan: ${distanceFromStart.toStringAsFixed(0)}m, Hedefe: ${distanceToEnd.toStringAsFixed(0)}m');
      print('     🔄 Sapma: ${detourDistance.toStringAsFixed(0)}m, İlerleme: ${(routeProgress * 100).toStringAsFixed(1)}%');
      print('     🧭 Yön farkı: ${bearingDiff1.toStringAsFixed(1)}°, ${bearingDiff2.toStringAsFixed(1)}°');
      print('     ⭐ Skor: ${score.toStringAsFixed(1)}');
    }
    
    // Puana göre sırala (yüksek puan önce)
    waypointPositions.sort((a, b) => b.value.compareTo(a.value));
    
    // En yüksek puanlı waypoint'leri al
    List<LatLng> orderedWaypoints = waypointPositions
        .take(2) // Maksimum 2 waypoint
        .map((e) => e.key)
        .toList();
    
    // Son olarak rota boyunca sırala (başlangıçtan hedefe doğru)
    orderedWaypoints.sort((a, b) {
      final distanceA = _calculateDistance(start, a);
      final distanceB = _calculateDistance(start, b);
      return distanceA.compareTo(distanceB);
    });
    
    print('🎯 Sıralanmış waypoint\'ler:');
    for (int i = 0; i < orderedWaypoints.length; i++) {
      final wp = orderedWaypoints[i];
      final distance = _calculateDistance(start, wp);
      final bearing = _getBearing(start, wp);
      print('   ${i + 1}. ${wp.latitude.toStringAsFixed(6)}, ${wp.longitude.toStringAsFixed(6)}');
      print('      📏 Mesafe: ${distance.toStringAsFixed(0)}m, 🧭 Yön: ${bearing.toStringAsFixed(1)}°');
    }
    
    return orderedWaypoints;
  }

  // İki nokta arasındaki yönü hesapla (0-360 derece)
  double _getBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final deltaLng = (to.longitude - from.longitude) * pi / 180;
    
    final y = sin(deltaLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng);
    
    double bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360; // 0-360 aralığında
  }

  // İki yön arasındaki farkı hesapla (-180 ile 180 arasında)
  double _getBearingDifference(double bearing1, double bearing2) {
    double diff = bearing2 - bearing1;
    
    // -180 ile 180 aralığına normalize et
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    
    return diff;
  }

  // Rotayı yumuşat (daha tutarlı rota için) - İYİLEŞTİRİLMİŞ VERSİYON
  List<LatLng> _smoothRoute(List<LatLng> route) {
    if (route.length <= 3) return route;
    
    print('=== ROTA YUMUŞATMA BAŞLADI ===');
    print('📏 Giriş nokta sayısı: ${route.length}');
    
    // 1. Douglas-Peucker algoritması ile gereksiz noktaları kaldır
    List<LatLng> simplifiedRoute = _douglasPeuckerSimplify(route, 10.0); // 10m tolerans
    print('🔄 Douglas-Peucker sonrası: ${simplifiedRoute.length} nokta');
    
    // 2. Yön tutarlılığı kontrolü ve düzeltme
    List<LatLng> directionCorrectedRoute = _correctRouteDirection(simplifiedRoute);
    print('🔄 Yön düzeltme sonrası: ${directionCorrectedRoute.length} nokta');
    
    // 3. Açı tabanlı yumuşatma
    List<LatLng> smoothedRoute = _angleBasedSmoothing(directionCorrectedRoute);
    print('🔄 Açı tabanlı yumuşatma sonrası: ${smoothedRoute.length} nokta');
    
    // 4. Minimum mesafe kontrolü
    List<LatLng> finalRoute = _removeClosePoints(smoothedRoute, 20.0); // 20m minimum mesafe
    print('🔄 Minimum mesafe kontrolü sonrası: ${finalRoute.length} nokta');
    
    print('✅ Rota yumuşatma tamamlandı');
    print('📊 Yumuşatma oranı: ${((route.length - finalRoute.length) / route.length * 100).toStringAsFixed(1)}%');
    
    return finalRoute;
  }

  // Rota yön tutarlılığını kontrol et ve düzelt
  List<LatLng> _correctRouteDirection(List<LatLng> route) {
    if (route.length <= 2) return route;
    
    List<LatLng> correctedRoute = [route.first];
    
    for (int i = 1; i < route.length - 1; i++) {
      final prev = route[i - 1];
      final current = route[i];
      final next = route[i + 1];
      
      // Yön tutarlılığını kontrol et
      final bearing1 = _getBearing(prev, current);
      final bearing2 = _getBearing(current, next);
      final bearingDiff = _getBearingDifference(bearing1, bearing2).abs();
      
      // Çok büyük yön değişimi varsa (ters istikamet) düzelt
      if (bearingDiff > 135) { // 135° üzeri ters istikamet
        print('⚠️ Ters istikamet tespit edildi: ${bearingDiff.toStringAsFixed(1)}°');
        
        // Orta nokta ekle
        final midPoint = LatLng(
          (prev.latitude + next.latitude) / 2,
          (prev.longitude + next.longitude) / 2,
        );
        
        correctedRoute.add(midPoint);
        correctedRoute.add(current);
        
        print('✅ Ters istikamet düzeltildi - orta nokta eklendi');
      } else {
        correctedRoute.add(current);
      }
    }
    
    correctedRoute.add(route.last);
    
    return correctedRoute;
  }

  // Douglas-Peucker algoritması ile rota basitleştirme
  List<LatLng> _douglasPeuckerSimplify(List<LatLng> points, double tolerance) {
    if (points.length <= 2) return points;
    
    // En uzak noktayı bul
    double maxDistance = 0;
    int maxIndex = 0;
    
    for (int i = 1; i < points.length - 1; i++) {
      double distance = _perpendicularDistance(points[i], points.first, points.last);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }
    
    // Eğer maksimum mesafe toleranstan büyükse, noktayı böl
    if (maxDistance > tolerance) {
      List<LatLng> firstHalf = _douglasPeuckerSimplify(points.sublist(0, maxIndex + 1), tolerance);
      List<LatLng> secondHalf = _douglasPeuckerSimplify(points.sublist(maxIndex), tolerance);
      
      // İlk yarıyı ekle (son nokta hariç, çünkü ikinci yarıda var)
      List<LatLng> result = firstHalf.sublist(0, firstHalf.length - 1);
      result.addAll(secondHalf);
      return result;
    } else {
      // Sadece başlangıç ve bitiş noktalarını döndür
      return [points.first, points.last];
    }
  }

  // Bir noktanın çizgiye olan dik mesafesini hesapla
  double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
    if (lineStart.latitude == lineEnd.latitude && lineStart.longitude == lineEnd.longitude) {
      return _calculateDistance(point, lineStart);
    }
    
    double A = lineEnd.latitude - lineStart.latitude;
    double B = lineEnd.longitude - lineStart.longitude;
    double C = lineStart.longitude * lineEnd.latitude - lineEnd.longitude * lineStart.latitude;
    
    double distance = (A * point.longitude - B * point.latitude + C).abs() / sqrt(A * A + B * B);
    return distance * 111000; // Yaklaşık metre cinsinden
  }

  // Açı tabanlı yumuşatma
  List<LatLng> _angleBasedSmoothing(List<LatLng> route) {
    if (route.length <= 3) return route;
    
    List<LatLng> smoothedRoute = [route.first];
    
    for (int i = 1; i < route.length - 1; i++) {
      final prev = route[i - 1];
      final current = route[i];
      final next = route[i + 1];
      
      // Açı hesapla
      final angle = _calculateAngle(prev, current, next);
      
      // Çok keskin dönüşler varsa yumuşat
      if (angle < 60) { // 60 dereceden küçük açı - daha toleranslı
        // Orta nokta ekle
        final midPoint = LatLng(
          (prev.latitude + next.latitude) / 2,
          (prev.longitude + next.longitude) / 2,
        );
        smoothedRoute.add(midPoint);
        smoothedRoute.add(current);
      } else {
        smoothedRoute.add(current);
      }
    }
    
    smoothedRoute.add(route.last);
    
    return smoothedRoute;
  }

  // Çok yakın noktaları kaldır
  List<LatLng> _removeClosePoints(List<LatLng> route, double minDistance) {
    if (route.length <= 2) return route;
    
    List<LatLng> filteredRoute = [route.first];
    
    for (int i = 1; i < route.length; i++) {
      final lastPoint = filteredRoute.last;
      final currentPoint = route[i];
      
      if (_calculateDistance(lastPoint, currentPoint) >= minDistance) {
        filteredRoute.add(currentPoint);
      }
    }
    
    return filteredRoute;
  }

  // Üç nokta arasındaki açıyı hesapla
  double _calculateAngle(LatLng a, LatLng b, LatLng c) {
    final ab = _calculateDistance(a, b);
    final bc = _calculateDistance(b, c);
    final ac = _calculateDistance(a, c);
    
    if (ab == 0 || bc == 0) return 180;
    
    // Kosinüs teoremi ile açı hesapla
    final cosAngle = (ab * ab + bc * bc - ac * ac) / (2 * ab * bc);
    final angle = acos(cosAngle.clamp(-1.0, 1.0)) * 180 / pi;
    
    return angle;
  }

  // Gereksiz grid dönüşüm fonksiyonları kaldırıldı - ORS API kullanılıyor

  // Gereksiz A* algoritması kaldırıldı - ORS API kullanılıyor

  Future<void> drawRoute() async {
    if (startPoint == null || endPoint == null) {
      _showMessage('Lütfen başlangıç ve bitiş noktalarını seçin');
      return;
    }

    try {
      _showMessage('🔄 Rota hesaplanıyor...', isError: false);
      
      // Rota hesapla
      final routePoints = await getRoute(startPoint!, endPoint!);
      
      if (routePoints.isNotEmpty) {
        // Mevcut rotayı temizle
        clearRoute();
        
        // Yeni rotayı çiz
        if (_controller != null) {
          // Rota noktalarını maplibre formatına çevir
          final maplibrePoints = routePoints
              .map((p) => maplibre.LatLng(p.latitude, p.longitude))
              .toList();
          
          // Rota çizgisini ekle
          final line = await _controller!.addLine(
            maplibre.LineOptions(
              geometry: maplibrePoints,
              lineWidth: 6.0, // Biraz daha kalın çizgi
              lineColor: '#1976D2',
              lineOpacity: 0.9,
            ),
          );

          // Rota çizgisini sakla
          _routeLine = line;

          // Rota bilgilerini göster
          _showRouteInfo(routePoints);

          // Rotayı haritada göster
          final bounds = _boundsFromLatLngList(routePoints);
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
          
          print('🎯 Rota başarıyla çizildi: ${routePoints.length} nokta');
        }
      } else {
        _showMessage('❌ Rota hesaplanamadı');
      }
    } catch (e) {
      print('💥 Rota çizme hatası: $e');
      _showMessage('Rota çizilirken hata oluştu: $e');
    }
  }

  // Rota bilgilerini göster
  void _showRouteInfo(List<LatLng> routePoints) {
    if (routePoints.isEmpty) return;
    
    // Rota mesafesi hesapla
    double totalDistance = 0;
    for (int i = 0; i < routePoints.length - 1; i++) {
      totalDistance += _calculateDistance(routePoints[i], routePoints[i + 1]);
    }
    
    // Rota kalitesi değerlendirmesi
    String routeQuality = _evaluateRouteQuality(routePoints);
    
    _showMessage(
      '✅ Rota başarıyla oluşturuldu!\n'
      '📏 Toplam mesafe: ${(totalDistance / 1000).toStringAsFixed(2)} km\n'
      '⏱️ Tahmini süre: ${routeDurationMin?.toStringAsFixed(0) ?? 'N/A'} dk\n'
      '🎯 Rota kalitesi: $routeQuality\n'
      '📍 Rota nokta sayısı: ${routePoints.length}',
      isError: false,
    );
  }

  // Rota kalitesini değerlendir
  String _evaluateRouteQuality(List<LatLng> routePoints) {
    if (routePoints.length <= 2) return 'Basit';
    
    // Keskin dönüş sayısını hesapla
    int sharpTurns = 0;
    for (int i = 1; i < routePoints.length - 1; i++) {
      final angle = _calculateAngle(
        routePoints[i - 1], 
        routePoints[i], 
        routePoints[i + 1]
      );
      if (angle < 45) sharpTurns++;
    }
    
    // Rota düzgünlüğünü değerlendir
    if (sharpTurns == 0) return 'Mükemmel';
    if (sharpTurns <= 2) return 'İyi';
    if (sharpTurns <= 5) return 'Orta';
    return 'Geliştirilebilir';
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

  void _showMessage(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : const Color(0xFF1976D2),
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  // Seçilen noktaya erişim noktası ekle
  Future<void> _addMarkerAtLocation(maplibre.LatLng latLng) async {
    try {
      // Marker türünü seç
      String? selectedType = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: const Text(
                  'Erişim Noktası Türü Seçin',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.accessible_forward, color: Colors.green),
                title: const Text('Rampa'),
                subtitle: const Text('Tekerlekli sandalye erişimi için'),
                onTap: () => Navigator.pop(context, 'rampa'),
              ),
              ListTile(
                leading: const Icon(Icons.elevator, color: Colors.orange),
                title: const Text('Asansör'),
                subtitle: const Text('Dikey erişim için'),
                onTap: () => Navigator.pop(context, 'asansör'),
              ),
              ListTile(
                leading: const Icon(Icons.directions_walk, color: Colors.blue),
                title: const Text('Yaya Geçidi'),
                subtitle: const Text('Güvenli yaya geçişi için'),
                onTap: () => Navigator.pop(context, 'yaya_gecidi'),
              ),
              ListTile(
                leading: const Icon(Icons.traffic, color: Colors.red),
                title: const Text('Trafik Işığı'),
                subtitle: const Text('Sesli trafik ışığı'),
                onTap: () => Navigator.pop(context, 'trafik_isigi'),
              ),
              ListTile(
                leading: const Icon(Icons.alt_route, color: Colors.purple),
                title: const Text('Üst/Alt Geçit'),
                subtitle: const Text('Yol üstü/altı geçiş'),
                onTap: () => Navigator.pop(context, 'ust_gecit'),
              ),
            ],
          );
        },
      );

      if (selectedType != null) {
        // Açıklama gir
        String? description = await showDialog<String>(
          context: context,
          builder: (context) {
            TextEditingController controller = TextEditingController();
            return AlertDialog(
              title: const Text("Erişim Noktası Açıklaması"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Konum: ${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: "Kısa açıklama girin (örn: Ana giriş rampası)",
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("İptal"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text("Ekle"),
                ),
              ],
            );
          },
        );

        if (description != null && description.isNotEmpty) {
          // Firestore'a kaydet
          await FirebaseFirestore.instance
              .collection('markers')
              .add(
                MarkerModel(
                  type: selectedType,
                  latitude: latLng.latitude,
                  longitude: latLng.longitude,
                  description: description,
                  likes: 0,
                  createdAt: DateTime.now(),
                ).toMap(),
              );

          // Başarı mesajı göster
          _showMessage(
            "Erişim noktası başarıyla eklendi!",
            isError: false,
          );

          // Haritayı yeni eklenen noktaya odakla
          await _controller!.animateCamera(
            maplibre.CameraUpdate.newLatLngZoom(latLng, 17),
          );

          // Marker'ları yenile
          _listenFirestoreMarkers();
        }
      }
    } catch (e) {
      print('Marker ekleme hatası: $e');
      _showMessage('Marker eklenirken hata oluştu: $e');
    }
  }

  // Manuel koordinat girişi dialog'u
  Future<void> _showManualCoordinateInput() async {
    try {
      final TextEditingController latController = TextEditingController();
      final TextEditingController lngController = TextEditingController();
      
      String? selectedType = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Manuel Koordinat Girişi"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: latController,
                  decoration: const InputDecoration(
                    labelText: "Latitude (Enlem)",
                    hintText: "Örn: 38.7569",
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lngController,
                  decoration: const InputDecoration(
                    labelText: "Longitude (Boylam)",
                    hintText: "Örn: 30.5387",
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Koordinatları ondalık formatta girin (örn: 38.7569, 30.5387)",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text("İptal"),
              ),
              ElevatedButton(
                onPressed: () {
                  if (latController.text.isNotEmpty && lngController.text.isNotEmpty) {
                    Navigator.pop(context, 'coordinates_entered');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Lütfen her iki koordinatı da girin'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text("Devam Et"),
              ),
            ],
          );
        },
      );

      if (selectedType == 'coordinates_entered') {
        // Koordinatları parse et
        double? lat = double.tryParse(latController.text);
        double? lng = double.tryParse(lngController.text);
        
        if (lat != null && lng != null) {
          // Koordinat geçerliliğini kontrol et
          if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
            await _addMarkerAtLocation(maplibre.LatLng(lat, lng));
          } else {
            _showMessage('Geçersiz koordinatlar: Latitude -90 ile 90, Longitude -180 ile 180 arasında olmalı');
          }
        } else {
          _showMessage('Koordinatlar sayısal değer olmalı');
        }
      }
    } catch (e) {
      print('Manuel koordinat girişi hatası: $e');
      _showMessage('Koordinat girişi sırasında hata oluştu: $e');
    }
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

  // Basit mesafe tabanlı sistem kullanılıyor - karmaşık bölge sistemi kaldırıldı

  // İki nokta arasındaki mesafeyi hesapla
  double _calculateDistance(LatLng p1, LatLng p2) {
    return Geolocator.distanceBetween(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
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
              
              // Uzun basma menüsünü göster
              String? selectedOption = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: const Text(
                          'Bu Nokta İçin Seçenekler',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
            ListTile(
                        leading: const Icon(Icons.play_arrow, color: Colors.green),
              title: const Text('Başlangıç Noktası Seç'),
                        subtitle: const Text('Rota başlangıcı olarak ayarla'),
              onTap: () => Navigator.pop(context, 'start'),
            ),
            ListTile(
                        leading: const Icon(Icons.flag, color: Colors.red),
              title: const Text('Hedef Nokta Seç'),
                        subtitle: const Text('Rota hedefi olarak ayarla'),
              onTap: () => Navigator.pop(context, 'end'),
            ),
                      ListTile(
                        leading: const Icon(Icons.add_location_alt, color: Colors.blue),
                        title: const Text('Erişim Noktası Ekle'),
                        subtitle: const Text('Bu noktaya erişim noktası ekle'),
                        onTap: () => Navigator.pop(context, 'add_marker'),
                      ),
          ],
        );
      },
    );

    if (selectedOption == 'start') {
      setState(() {
        startPoint = LatLng(latLng.latitude, latLng.longitude);
      });
      if (_currentLocationSymbol != null) {
        await _controller!.updateSymbol(
          _currentLocationSymbol!,
          maplibre.SymbolOptions(
            geometry: latLng,
            iconImage: 'marker-15',
            iconSize: 1.6,
            textField: 'Başlangıç',
            textOffset: const Offset(0, 1.5),
            iconColor: '#00FF00',
          ),
        );
      } else {
                  _currentLocationSymbol = await _controller!.addSymbol(
          maplibre.SymbolOptions(
            geometry: latLng,
            iconImage: 'marker-15',
            iconSize: 1.6,
            textField: 'Başlangıç',
            textOffset: const Offset(0, 1.5),
            iconColor: '#00FF00',
          ),
        );
      }
      await _controller!.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(latLng, 15),
      );
    } else if (selectedOption == 'end') {
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
              } else if (selectedOption == 'add_marker') {
                // Seçilen noktaya erişim noktası ekle
                await _addMarkerAtLocation(latLng);
    }

              // Eğer hem başlangıç hem bitiş noktası varsa rota çiz
    if (startPoint != null && endPoint != null) {
      await drawRoute();
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
                          // Marker ekleme seçeneklerini göster
                          String? addOption = await showModalBottomSheet<String>(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (context) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    child: const Text(
                                      'Erişim Noktası Ekleme',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.my_location, color: Colors.blue),
                                    title: const Text('Mevcut Konumuma Ekle'),
                                    subtitle: const Text('GPS konumunuzu kullanarak'),
                                    onTap: () => Navigator.pop(context, 'current_location'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.map, color: Colors.green),
                                    title: const Text('Haritada Nokta Seç'),
                                    subtitle: const Text('Haritaya uzun basarak nokta seçin'),
                                    onTap: () => Navigator.pop(context, 'map_selection'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.edit_location, color: Colors.orange),
                                    title: const Text('Koordinat Girerek Ekle'),
                                    subtitle: const Text('Latitude ve longitude değerlerini girin'),
                                    onTap: () => Navigator.pop(context, 'manual_input'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (addOption == 'current_location') {
                            // Mevcut konuma marker ekle
                            final pos = await _getCurrentLocation();
                            if (pos != null) {
                              await _addMarkerAtLocation(
                                maplibre.LatLng(pos.latitude, pos.longitude),
                              );
                            }
                          } else if (addOption == 'map_selection') {
                            // Haritada nokta seçme talimatı
                                _showMessage(
                              'Haritaya uzun basarak istediğiniz noktayı seçin, sonra "Bu Noktaya Erişim Noktası Ekle" seçeneğini kullanın.',
                              isError: false,
                                );
                          } else if (addOption == 'manual_input') {
                            // Manuel koordinat girişi
                            await _showManualCoordinateInput();
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
                    const SizedBox(width: 12),
                    FloatingActionButton(
                      heroTag: 'markerYenile',
                      onPressed: () async {
                        // Marker'ları yenile
                        await _refreshMarkers();
                      },
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.refresh, size: 28),
                    ),
                    const SizedBox(width: 12),
                    // Bölge sistemi kaldırıldı - basit mesafe tabanlı sistem kullanılıyor
                    const SizedBox(width: 12),
                    if (routePoints.isNotEmpty)
                      FloatingActionButton(
                        heroTag: 'rotaIstatistik',
                        onPressed: () {
                          _showAdvancedRouteInfo(routePoints);
                        },
                        backgroundColor: Colors.teal,
                        child: const Icon(Icons.analytics, size: 28),
                        tooltip: 'Rota İstatistikleri',
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
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                  Icon(
                    _getIcon(marker.type),
                    color: _getMarkerColor(marker.type),
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      _typeToLabel(marker.type),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                        Text(
                          'Koordinat: ${marker.latitude.toStringAsFixed(6)}, ${marker.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (marker.description.isNotEmpty) ...[
                Text(
                  'Açıklama:',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                      child: Text(
                        marker.description,
                    style: const TextStyle(fontSize: 14),
                      ),
                    ),
                const SizedBox(height: 16),
                  ],
                Row(
                  children: [
                  GestureDetector(
                    onTap: () async {
                      await _likeMarker(docId, marker.likes);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite,
                            color: Colors.green[600],
                            size: 20,
                          ),
                    const SizedBox(width: 8),
                    Text(
                            '${marker.likes} beğeni',
                            style: TextStyle(
                              color: Colors.green[600],
                              fontWeight: FontWeight.w500,
                            ),
                    ),
                  ],
                ),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Eklenme: ${_formatDate(marker.createdAt!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (marker.updatedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Güncelleme: ${_formatDate(marker.updatedAt!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
                Row(
                  children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _editMarker(marker, docId);
                      },
                      icon: const Icon(Icons.edit, size: 20),
                      label: const Text('Düzenle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deleteMarker(docId);
                      },
                      icon: const Icon(Icons.delete, size: 20),
                      label: const Text('Sil'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // Haritayı bu noktaya odakla
                    if (_controller != null) {
                      _controller!.animateCamera(
                        maplibre.CameraUpdate.newLatLngZoom(
                          maplibre.LatLng(marker.latitude, marker.longitude),
                          17,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.my_location, size: 20),
                  label: const Text('Haritada Göster'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Tarih formatla
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // Marker düzenleme
  Future<void> _editMarker(MarkerModel marker, String docId) async {
    try {
      // Marker türünü seç
      String? selectedType = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: const Text(
                  'Erişim Noktası Türünü Güncelleyin',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.accessible_forward, color: Colors.green),
                title: const Text('Rampa'),
                subtitle: const Text('Tekerlekli sandalye erişimi için'),
                trailing: marker.type == 'rampa' ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () => Navigator.pop(context, 'rampa'),
              ),
              ListTile(
                leading: const Icon(Icons.elevator, color: Colors.orange),
                title: const Text('Asansör'),
                subtitle: const Text('Dikey erişim için'),
                trailing: marker.type == 'asansör' ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () => Navigator.pop(context, 'asansör'),
              ),
              ListTile(
                leading: const Icon(Icons.directions_walk, color: Colors.blue),
                title: const Text('Yaya Geçidi'),
                subtitle: const Text('Güvenli yaya geçişi için'),
                trailing: marker.type == 'yaya_gecidi' ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () => Navigator.pop(context, 'yaya_gecidi'),
              ),
              ListTile(
                leading: const Icon(Icons.traffic, color: Colors.red),
                title: const Text('Trafik Işığı'),
                subtitle: const Text('Sesli trafik ışığı'),
                trailing: marker.type == 'trafik_isigi' ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () => Navigator.pop(context, 'trafik_isigi'),
              ),
              ListTile(
                leading: const Icon(Icons.alt_route, color: Colors.purple),
                title: const Text('Üst/Alt Geçit'),
                subtitle: const Text('Yol üstü/altı geçiş'),
                trailing: marker.type == 'ust_gecit' ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () => Navigator.pop(context, 'ust_gecit'),
              ),
            ],
          );
        },
      );

      if (selectedType != null && selectedType != marker.type) {
        // Açıklama güncelle
        String? newDescription = await showDialog<String>(
          context: context,
          builder: (context) {
            TextEditingController controller = TextEditingController(text: marker.description);
            return AlertDialog(
              title: const Text("Açıklamayı Güncelleyin"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    Text(
                    "Konum: ${marker.latitude.toStringAsFixed(6)}, ${marker.longitude.toStringAsFixed(6)}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: "Güncellenmiş açıklama girin",
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("İptal"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text("Güncelle"),
                ),
              ],
            );
          },
        );

        if (newDescription != null) {
          // Firestore'da güncelle
          await FirebaseFirestore.instance
              .collection('markers')
              .doc(docId)
              .update({
            'type': selectedType,
            'description': newDescription,
            'updatedAt': DateTime.now(),
          });

          _showMessage(
            "Erişim noktası başarıyla güncellendi!",
            isError: false,
          );

          // Marker'ları yenile
          _listenFirestoreMarkers();
        }
      }
    } catch (e) {
      print('Marker güncelleme hatası: $e');
      _showMessage('Marker güncellenirken hata oluştu: $e');
    }
  }

  // Marker silme
  Future<void> _deleteMarker(String docId) async {
    try {
      // Silme onayı al
      bool? confirmDelete = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Erişim Noktasını Sil"),
            content: const Text(
              "Bu erişim noktasını silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("İptal"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Sil"),
              ),
            ],
        );
      },
    );

      if (confirmDelete == true) {
        // Firestore'dan sil
        await FirebaseFirestore.instance
            .collection('markers')
            .doc(docId)
            .delete();

        // Haritadan symbol'ü kaldır
        final symbol = _symbols.remove(docId);
        if (symbol != null && _controller != null) {
          try {
            await _controller!.removeSymbol(symbol);
          } catch (_) {}
        }

        _showMessage(
          "Erişim noktası başarıyla silindi!",
          isError: false,
        );
      }
    } catch (e) {
      print('Marker silme hatası: $e');
      _showMessage('Marker silinirken hata oluştu: $e');
    }
  }

  // Marker beğenme
  Future<void> _likeMarker(String docId, int currentLikes) async {
    try {
      // Firestore'da beğeni sayısını güncelle
      await FirebaseFirestore.instance
          .collection('markers')
          .doc(docId)
          .update({
        'likes': currentLikes + 1,
        'lastLikedAt': DateTime.now(),
      });

      _showMessage(
        "Beğeniniz eklendi! 👍",
        isError: false,
      );

      // Marker'ları yenile
      _listenFirestoreMarkers();
    } catch (e) {
      print('Marker beğenme hatası: $e');
      _showMessage('Beğeni eklenirken hata oluştu: $e');
    }
  }

  // Marker'ları yenile
  Future<void> _refreshMarkers() async {
    try {
      _showMessage('Marker\'lar yenileniyor...', isError: false);
      
      // Mevcut marker'ları temizle
      for (final symbol in _symbols.values) {
        if (_controller != null) {
          try {
            await _controller!.removeSymbol(symbol);
          } catch (_) {}
        }
      }
      _symbols.clear();
      
      // Firestore'dan yeniden yükle
      _listenFirestoreMarkers();
      
      _showMessage('Marker\'lar başarıyla yenilendi!', isError: false);
    } catch (e) {
      print('Marker yenileme hatası: $e');
      _showMessage('Marker\'lar yenilenirken hata oluştu: $e');
    }
  }

  // Bölge sistemi kaldırıldı - basit mesafe tabanlı sistem kullanılıyor

  // Rota istatistiklerini hesapla
  Map<String, dynamic> _calculateRouteStatistics(List<LatLng> routePoints) {
    if (routePoints.length < 2) {
      return {
        'totalDistance': 0.0,
        'straightLineDistance': 0.0,
        'efficiency': 0.0,
        'sharpTurns': 0,
        'averageSegmentLength': 0.0,
      };
    }
    
    double totalDistance = 0.0;
    int sharpTurns = 0;
    List<double> segmentLengths = [];
    
    for (int i = 0; i < routePoints.length - 1; i++) {
      final segmentLength = _calculateDistance(routePoints[i], routePoints[i + 1]);
      totalDistance += segmentLength;
      segmentLengths.add(segmentLength);
      
      // Keskin dönüş kontrolü
      if (i > 0 && i < routePoints.length - 1) {
        final angle = _calculateAngle(
          routePoints[i - 1], 
          routePoints[i], 
          routePoints[i + 1]
        );
        if (angle < 45) sharpTurns++;
      }
    }
    
    final straightLineDistance = _calculateDistance(routePoints.first, routePoints.last);
    final efficiency = straightLineDistance > 0 ? (straightLineDistance / totalDistance) * 100 : 0;
    final averageSegmentLength = segmentLengths.isNotEmpty 
        ? segmentLengths.reduce((a, b) => a + b) / segmentLengths.length 
        : 0.0;
    
    return {
      'totalDistance': totalDistance,
      'straightLineDistance': straightLineDistance,
      'efficiency': efficiency,
      'sharpTurns': sharpTurns,
      'averageSegmentLength': averageSegmentLength,
    };
  }

  // Gelişmiş rota bilgilerini göster
  void _showAdvancedRouteInfo(List<LatLng> routePoints) {
    if (routePoints.isEmpty) return;
    
    final stats = _calculateRouteStatistics(routePoints);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 Rota Detayları'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📏 Toplam mesafe: ${(stats['totalDistance'] / 1000).toStringAsFixed(2)} km'),
            Text('🔄 Düz çizgi mesafesi: ${(stats['straightLineDistance'] / 1000).toStringAsFixed(2)} km'),
            Text('⚡ Rota verimliliği: ${stats['efficiency'].toStringAsFixed(1)}%'),
            Text('🔄 Keskin dönüş sayısı: ${stats['sharpTurns']}'),
            Text('📐 Ortalama segment uzunluğu: ${stats['averageSegmentLength'].toStringAsFixed(0)}m'),
            Text('📍 Rota nokta sayısı: ${routePoints.length}'),
            if (routeDurationMin != null)
              Text('⏱️ Tahmini süre: ${routeDurationMin!.toStringAsFixed(0)} dk'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
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
  final DateTime? updatedAt;

  MarkerModel({
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.likes,
    this.createdAt,
    this.updatedAt,
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
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate()
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
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}

// GridNode sınıfı kaldırıldı - gereksiz karmaşıklık


