import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:engelsiz_rota/theme/app_theme.dart';
import 'package:engelsiz_rota/model/marker_model.dart';
import 'package:flutter_tts/flutter_tts.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

// EKLE: _MapPageState'in ÜSTÜNE
class TurnStep {
  final String instruction; // ORS instruction
  final double distance; // m
  final double duration; // s
  final LatLng location; // manevra koordinatı
  final String maneuver; // "turn-right", "arrive", ...

  TurnStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.location,
    required this.maneuver,
  });
}

bool _hasAnnouncedRouteStart = false; // Tracks if route start is announced
bool _hasAnnouncedDestinationReached =
    false; // Tracks if destination is announced
int?
_lastAnnouncedTurnIndex; // Tracks the last announced turn to avoid repetition

class _MapPageState extends State<MapPage> {
  static const String _mapTilerKey = 'RUlFyEFNM0RNo0FrC3ch';
  static const String _orsApiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4MGE1MzhlMWIwNTRiOGZiOTE5YTg3M2NmYzQ3MzJjIiwiaCI6Im11cm11cjY0In0=';
  final String _styleUrl =
      'https://api.maptiler.com/maps/openstreetmap/style.json?key=$_mapTilerKey';

  maplibre.MaplibreMapController? _controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _markerSub;
  Timer? locationTimer;

  // TTS Controller for voice guidance
  FlutterTts? _flutterTts;
  bool _isVoiceEnabled = true;
  bool _isClusteringEnabled = false; // Tracks clustering state

  final Map<String, maplibre.Symbol> _symbols = {};
  maplibre.Symbol? _currentLocationSymbol;
  maplibre.Symbol? _endPointSymbol;
  maplibre.Line? _routeLine;

  // EKLE: _MapPageState içinde alanlar arasına
  LatLng? _livePos; // anlık konum
  List<TurnStep> _steps = []; // turn-by-turn adımlar
  int _currentStepIdx = 0; // sıradaki adım index

  String _nextTurnText = ''; // UI'da gösterilecek
  double _nextTurnDistM = 0; // sıradaki adıma kalan mesafe

  // Rota sembollerini takip etmek için
  final List<maplibre.Symbol> _routeSymbols = [];

  // Rota çizgilerini takip etmek için
  final List<maplibre.Line> _routeLines = [];

  // Erişilebilir nokta sayısını takip etmek için
  int _totalAccessiblePoints = 0;

  // Son sesli uyarı verilen noktaları takip etmek için
  final Set<String> _announcedPoints = {};

  // Rota dışında olduğunu duyurmak için
  bool _hasAnnouncedOffRoute = false;

  // Hedef noktaya ulaştığını duyurmak için
  bool _hasAnnouncedDestinationReached = false;

  LatLng? startPoint;
  LatLng? endPoint;
  List<LatLng> routePoints = [];
  double? routeDistanceKm;
  double? routeDurationMin;
  String selectedFilter = 'hepsi';
  String selectedProfile = 'wheelchair'; // Sadece tekerlekli sandalye
  bool isStartPointFixed = false; // Başlangıç noktası sabit mi?

  // Erişilebilir nokta türlerini tanımla
  List<String> get _accessibleTypes => [
    'rampa', // Ramp
    'asansör', // Elevator
    'yaya_gecidi', // Pedestrian crossing
    'trafik_isigi', // Traffic light
    'ust_gecit', // Overpass/Underpass
  ];

  // Nokta türünün erişilebilir olup olmadığını kontrol et
  bool _isAccessibleType(String type) {
    return _accessibleTypes.contains(type);
  }

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _listenFirestoreMarkers();

    // Konumu hemen göster
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setInitialLocation();
    });

    locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!isStartPointFixed) {
        // Sadece başlangıç noktası sabit değilse güncelle
        final pos = await _getCurrentLocation();
        if (pos != null) {
          updateCurrentLocationMarker(pos);
          await _checkAndAnnounceNearbyAccessiblePoints();
          await _announceRouteProgress();
          await _checkOffRoute();
        }
      }
    });
  }

  // TTS initialization
  void _initializeTTS() async {
    _flutterTts = FlutterTts();

    // Set language to Turkish
    await _flutterTts!.setLanguage("tr-TR");
    await _flutterTts!.setSpeechRate(
      0.5,
    ); // Slower speech rate for better understanding
    await _flutterTts!.setVolume(1.0);
    await _flutterTts!.setPitch(1.0);

    // Set voice if available
    var voices = await _flutterTts!.getVoices;
    if (voices != null) {
      for (var voice in voices) {
        if (voice['name'].toString().contains('Turkish') ||
            voice['name'].toString().contains('tr')) {
          await _flutterTts!.setVoice({
            "name": voice['name'],
            "locale": voice['locale'],
          });
          break;
        }
      }
    }
  }

  // Voice guidance methods
  Future<void> _speak(String text) async {
    if (!_isVoiceEnabled || _flutterTts == null) return;

    try {
      await _flutterTts!.speak(text);
    } catch (e) {
      print('TTS Error: $e');
    }
  }

  Future<void> _announceRouteCreated() async {
    if (routeDistanceKm != null && routeDurationMin != null) {
      final distanceText = routeDistanceKm! < 1
          ? '${(routeDistanceKm! * 1000).toInt()} metre'
          : '${routeDistanceKm!.toStringAsFixed(1)} kilometre';

      final durationText = routeDurationMin! < 1
          ? '${(routeDurationMin! * 60).toInt()} saniye'
          : '${routeDurationMin!.toInt()} dakika';

      final announcement =
          'Rota oluşturuldu. Mesafe: $distanceText, süre: $durationText. Tekerlekli sandalye için rampa, asansör, yaya geçidi, trafik ışığı ve üst alt geçitler dikkate alınarak erişilebilir rota hazırlandı.';
      await _speak(announcement);

      // Reset destination reached flag for new route
      _hasAnnouncedDestinationReached = false;
      _hasAnnouncedOffRoute = false;
    }
  }

  Future<void> _announceRouteProgress() async {
    if (!_isVoiceEnabled ||
        routePoints.isEmpty ||
        startPoint == null ||
        _controller == null)
      return;

    // Check if route has just started (within 20 meters of the first point)
    final firstPoint = routePoints.first;
    final distanceToStart = Geolocator.distanceBetween(
      startPoint!.latitude,
      startPoint!.longitude,
      firstPoint.latitude,
      firstPoint.longitude,
    );

    if (distanceToStart < 20 && !_hasAnnouncedRouteStart) {
      await _speak('Rota başlangıcına ulaştınız. Yönlendirmeyi takip edin.');
      _hasAnnouncedRouteStart = true;
    }

    // Check if destination is reached (within 10 meters of the last point)
    final lastPoint = routePoints.last;
    final distanceToEnd = Geolocator.distanceBetween(
      startPoint!.latitude,
      startPoint!.longitude,
      lastPoint.latitude,
      lastPoint.longitude,
    );

    if (distanceToEnd < 10 && !_hasAnnouncedDestinationReached) {
      await _speak('Hedef noktaya ulaştınız. Yolculuğunuz tamamlandı.');
      _hasAnnouncedDestinationReached = true;
      return; // Stop further announcements once destination is reached
    }

    // Check for approaching turns
    if (routePoints.length >= 3) {
      for (int i = 1; i < routePoints.length - 1; i++) {
        final prevPoint = routePoints[i - 1];
        final currentPoint = routePoints[i];
        final nextPoint = routePoints[i + 1];

        final distanceToTurn = Geolocator.distanceBetween(
          startPoint!.latitude,
          startPoint!.longitude,
          currentPoint.latitude,
          currentPoint.longitude,
        );

        // Only announce if within 30 meters and this turn hasn't been announced
        if (distanceToTurn < 30 && _lastAnnouncedTurnIndex != i) {
          final bearing1 = _getBearing(prevPoint, currentPoint);
          final bearing2 = _getBearing(currentPoint, nextPoint);
          final bearingDiff = _getBearingDifference(bearing1, bearing2).abs();

          if (bearingDiff > 45) {
            String direction;
            if (bearingDiff > 135) {
              direction = 'U dönüşü';
            } else if (bearingDiff > 90) {
              direction = 'keskin dönüş';
            } else {
              direction = 'hafif dönüş';
            }
            await _speak('$direction yaklaşıyor. Hazırlanın.');
            _lastAnnouncedTurnIndex = i; // Mark this turn as announced
            break; // Announce only the closest turn
          }
        }
      }
    }
  }

  Future<void> _announceNavigationStart() async {
    if (startPoint != null && endPoint != null && !_hasAnnouncedRouteStart) {
      final announcement =
          'Navigasyon başlatılıyor. Başlangıç noktasından hedef noktaya doğru yönlendiriliyorsunuz.';
      await _speak(announcement);
      _hasAnnouncedRouteStart = true;
    }
  }

  Future<void> _announceAccessiblePointNearby(LatLng point, String type) async {
    final distance = Geolocator.distanceBetween(
      startPoint!.latitude,
      startPoint!.longitude,
      point.latitude,
      point.longitude,
    );

    String distanceText;
    if (distance < 100) {
      distanceText = '${distance.toInt()} metre';
    } else if (distance < 1000) {
      distanceText = '${(distance / 100).round() * 100} metre';
    } else {
      distanceText = '${(distance / 1000).toStringAsFixed(1)} kilometre';
    }

    final typeText = _typeToLabel(type);
    final announcement =
        'Yakınınızda $typeText bulunuyor. Mesafe: $distanceText.';
    await _speak(announcement);
  }

  Future<void> _announceRouteCleared() async {
    await _speak('Rota temizlendi. Yeni rota oluşturabilirsiniz.');
  }

  Future<void> _announceLocationUpdated() async {
    await _speak('Konumunuz güncellendi.');
  }

  Future<void> _announceMarkerAdded(String type) async {
    final typeText = _typeToLabel(type);
    await _speak('$typeText erişim noktası başarıyla eklendi.');
  }

  Future<void> _checkOffRoute() async {
    if (routePoints.isEmpty || startPoint == null) return;

    double minDistanceToRoute = double.infinity;

    for (final routePoint in routePoints) {
      final distance = Geolocator.distanceBetween(
        startPoint!.latitude,
        startPoint!.longitude,
        routePoint.latitude,
        routePoint.longitude,
      );
      if (distance < minDistanceToRoute) {
        minDistanceToRoute = distance;
      }
    }

    if (minDistanceToRoute > 50 && !_hasAnnouncedOffRoute) {
      await _speak('Rota dışındasınız. Lütfen rotaya geri dönün.');
      _hasAnnouncedOffRoute = true;
    } else if (minDistanceToRoute <= 50) {
      _hasAnnouncedOffRoute = false;
    }
  }

  Future<void> _checkAndAnnounceNearbyAccessiblePoints() async {
    if (startPoint == null || !_isVoiceEnabled) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('markers')
          .get();

      for (final doc in snapshot.docs) {
        final marker = MarkerModel.fromMap(doc.data());
        if (!_isAccessibleType(marker.type)) continue;

        final point = LatLng(marker.latitude, marker.longitude);
        final distance = Geolocator.distanceBetween(
          startPoint!.latitude,
          startPoint!.longitude,
          point.latitude,
          point.longitude,
        );

        // 50 metre yakınında erişilebilir nokta varsa ve henüz duyurulmamışsa
        if (distance <= 50) {
          final pointKey = '${marker.latitude}_${marker.longitude}';
          if (!_announcedPoints.contains(pointKey)) {
            _announcedPoints.add(pointKey);
            await _announceAccessiblePointNearby(point, marker.type);
          }
        } else {
          // 100 metreden uzaklaştıysa uyarı listesinden çıkar
          final pointKey = '${marker.latitude}_${marker.longitude}';
          if (_announcedPoints.contains(pointKey)) {
            _announcedPoints.remove(pointKey);
          }
        }
      }
    } catch (e) {
      print('Yakındaki noktalar kontrol edilirken hata: $e');
    }
  }

  @override
  void dispose() {
    _markerSub?.cancel();
    locationTimer?.cancel();
    _controller?.dispose();
    _flutterTts?.stop();
    super.dispose();
  }

  void _onMapCreated(maplibre.MaplibreMapController controller) {
    _controller = controller;

    // Harita hazır olduğunda konumu ve marker'ları göster
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setInitialLocation();
      _listenFirestoreMarkers(); // Ensure markers are loaded after map creation
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
          textField: 'Konumum',
          textSize: 14.0,
          textColor: '#00FF00',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
          iconImage: null,
        ),
      );
      _currentLocationSymbol = symbol;
    } else {
      try {
        await _controller!.updateSymbol(
          _currentLocationSymbol!,
          maplibre.SymbolOptions(
            geometry: maplibre.LatLng(pos.latitude, pos.longitude),
          ),
        );
      } catch (e) {
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
      isStartPointFixed = false;
    });

    if (_controller != null) {
      await _controller!.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(pos.latitude, pos.longitude),
          17,
        ),
      );
      updateCurrentLocationMarker(pos);
      await _announceLocationUpdated();
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
        .orderBy('createdAt', descending: true);
    // .limit(50); // Limit kaldırıldı - tüm marker'ları göster

    _markerSub?.cancel(); // Önceki dinleyiciyi iptal et
    _markerSub = coll.snapshots().listen((snap) async {
      if (_controller == null) {
        // Controller henüz hazır değilse, bir süre bekle ve tekrar dene
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller == null) return; // Hala null ise çık
      }

      // Filtre değiştiğinde tüm mevcut marker'ları temizle
      if (_symbols.values.length > 0) {
        try {
          for (final symbol in _symbols.values) {
            await _controller!.removeSymbol(symbol);
          }
        } catch (_e) {
          print(
            "Marker'lar temizlenirken hata!!!!!!!!!!!!!!!!!!!!!!!!!! = $_e",
          );
        }

        _symbols.clear();
      }

      final currentIds = snap.docs.map((d) => d.id).toSet();
      final knownIds = _symbols.keys.toSet();

      // Kaldırılan marker'ları temizle
      for (final removedId in knownIds.difference(currentIds)) {
        final sym = _symbols.remove(removedId);
        if (sym != null) {
          try {
            await _controller!.removeSymbol(sym);
          } catch (_) {}
        }
      }

      // Yeni veya güncellenmiş marker'ları ekle
      for (final doc in snap.docs) {
        final marker = MarkerModel.fromMap(doc.data());

        // Filtre kontrolü - sadece seçili tipe ait marker'ları göster
        if (selectedFilter != 'hepsi' && marker.type != selectedFilter) {
          continue;
        }

        final lat = marker.latitude;
        final lng = marker.longitude;
        final docId = doc.id;

        if (_symbols.containsKey(docId)) {
          // Mevcut marker'ı güncelle
          try {
            await _controller!.updateSymbol(
              _symbols[docId]!,
              maplibre.SymbolOptions(
                geometry: maplibre.LatLng(lat, lng),
                textField: _typeToLabel(marker.type),
                textColor: _getMarkerTextColor(marker.type),
              ),
            );
          } catch (e) {
            // Güncelleme başarısız olursa marker'ı yeniden oluştur
            try {
              await _controller!.removeSymbol(_symbols[docId]!);
            } catch (_) {}
            _symbols.remove(docId);
          }
        }

        // Eğer marker henüz eklenmemişse veya güncelleme başarısız olduysa ekle
        if (!_symbols.containsKey(docId)) {
          try {
            String? distanceText;
            if (startPoint != null) {
              final distance = Geolocator.distanceBetween(
                startPoint!.latitude,
                startPoint!.longitude,
                lat,
                lng,
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
                iconOffset: const Offset(0, -10), // Icon'u yukarı kaydır
                iconHaloColor: '#FFFFFF',
                iconHaloWidth: 3.0, // Daha belirgin halo
                textField: distanceText != null
                    ? '${_typeToLabel(marker.type)}\n$distanceText'
                    : _typeToLabel(marker.type),
                textSize: 12.0, // Daha okunabilir text boyutu
                textColor: _getMarkerTextColor(marker.type),
                textHaloColor: '#FFFFFF',
                textHaloWidth: 3.0, // Daha belirgin text halo
                textOffset: const Offset(0, 2.0), // Text'i daha aşağı kaydır
              ),
            );
            _symbols[docId] = symbol;

            _controller!.onSymbolTapped.add((symbol) {
              if (symbol == _symbols[docId]) {
                _showMarkerDetails(marker, docId);
              }
            });
          } catch (e) {
            print('Marker eklenirken hata: $e');
          }
        }
      }

      // Toplam erişilebilir nokta sayısını güncelle
      final filteredCount = snap.docs.where((doc) {
        final marker = MarkerModel.fromMap(doc.data());
        return selectedFilter == 'hepsi' || marker.type == selectedFilter;
      }).length;

      setState(() {
        _totalAccessiblePoints = filteredCount;
      });

      print(
        '📍 Toplam marker: ${snap.docs.length}, Filtrelenmiş: $filteredCount, Filtre: $selectedFilter',
      );
    });
  }

  void _ensureCurrentLocationVisible() async {
    if (_controller == null) return;

    // Eğer konum henüz alınmadıysa ve başlangıç noktası sabit değilse, al
    if (startPoint == null && !isStartPointFixed) {
      final pos = await _getCurrentLocation();
      if (pos != null) {
        setState(() {
          startPoint = pos;
        });
        updateCurrentLocationMarker(pos);
      }
    } else if (startPoint != null) {
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
      List<LatLng> accessiblePoints = await _findAccessiblePoints(start, end);
      print('♿ ${accessiblePoints.length} erişilebilir nokta bulundu');

      List<LatLng> selectedWaypoints = _selectBestWaypoints(
        start,
        end,
        accessiblePoints,
      );
      print('🔄 ${selectedWaypoints.length} waypoint seçildi');

      List<LatLng> route = await _createSimpleRoute(
        start,
        end,
        selectedWaypoints,
      );

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

  Future<List<LatLng>> _findAccessiblePoints(LatLng start, LatLng end) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('markers')
        .get();

    List<LatLng> accessiblePoints = [];
    final totalDistance = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );

    for (final doc in snapshot.docs) {
      final marker = MarkerModel.fromMap(doc.data());
      final point = LatLng(marker.latitude, marker.longitude);

      if (!_isAccessibleType(marker.type)) continue;

      if (Geolocator.distanceBetween(
                start.latitude,
                start.longitude,
                point.latitude,
                point.longitude,
              ) <
              50 ||
          Geolocator.distanceBetween(
                end.latitude,
                end.longitude,
                point.latitude,
                point.longitude,
              ) <
              50)
        continue;

      final distanceFromStart = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        point.latitude,
        point.longitude,
      );
      final distanceToEnd = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        end.latitude,
        end.longitude,
      );
      final detour = (distanceFromStart + distanceToEnd) - totalDistance;

      if (detour <= totalDistance * 0.2) {
        accessiblePoints.add(point);
      }
    }

    return accessiblePoints;
  }

  List<LatLng> _selectBestWaypoints(
    LatLng start,
    LatLng end,
    List<LatLng> points,
  ) {
    if (points.isEmpty) return [];

    List<MapEntry<LatLng, double>> scoredPoints = [];

    for (final point in points) {
      double score = _calculateSimpleScore(start, end, point);
      scoredPoints.add(MapEntry(point, score));
    }

    scoredPoints.sort((a, b) => b.value.compareTo(a.value));

    final topPoints = scoredPoints.take(2).map((e) => e.key).toList();

    topPoints.sort((a, b) {
      final distA = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        a.latitude,
        a.longitude,
      );
      final distB = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        b.latitude,
        b.longitude,
      );
      return distA.compareTo(distB);
    });

    return topPoints;
  }

  double _calculateSimpleScore(LatLng start, LatLng end, LatLng point) {
    double score = 0.0;

    final totalDistance = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    final distanceFromStart = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      point.latitude,
      point.longitude,
    );
    final distanceToEnd = Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      end.latitude,
      end.longitude,
    );
    final detour = (distanceFromStart + distanceToEnd) - totalDistance;

    if (detour <= totalDistance * 0.1)
      score += 50;
    else if (detour <= totalDistance * 0.2)
      score += 30;
    else
      score += 10;

    final routeProgress =
        distanceFromStart / (distanceFromStart + distanceToEnd);
    if (routeProgress >= 0.3 && routeProgress <= 0.7)
      score += 30;
    else if (routeProgress >= 0.2 && routeProgress <= 0.8)
      score += 20;
    else
      score += 5;

    final bearing1 = _getBearing(start, point);
    final bearing2 = _getBearing(point, end);
    final bearingDiff = _getBearingDifference(bearing1, bearing2).abs();

    if (bearingDiff <= 45)
      score += 20;
    else if (bearingDiff <= 90)
      score += 10;
    else
      score += 0;

    return score;
  }

  Future<List<LatLng>> _createSimpleRoute(
    LatLng start,
    LatLng end,
    List<LatLng> waypoints,
  ) async {
    if (waypoints.isEmpty) return await _createDirectRoute(start, end);

    final String url =
        'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

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
        print('⚠️ ORS API hatası: ${response.statusCode}');
        return await _createDirectRoute(start, end);
      }
    } catch (e) {
      print('❌ Rota oluşturma hatası: $e');
      return await _createDirectRoute(start, end);
    }
  }

  Future<List<LatLng>> _createDirectRoute(LatLng start, LatLng end) async {
    final String url =
        'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

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
        _hasAnnouncedRouteStart = false; // Reset for new route
        _hasAnnouncedDestinationReached = false; // Reset for new route
        _lastAnnouncedTurnIndex = null; // Reset turn announcements
        _hasAnnouncedOffRoute = false; // Reset off-route flag
      });

      await _clearAllRoutes();
      await _drawMainRoute(points);
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
      await _announceRouteCreated();
      await _announceNavigationStart();
    } else {
      _showMessage(
        'Rota oluşturulamadı. Lütfen başka bir hedef seçin veya erişim noktası ekleyin.',
      );
    }
  }

  Future<void> _clearAllRoutes() async {
    if (_routeLine != null) {
      try {
        await _controller!.removeLine(_routeLine!);
      } catch (_) {}
      _routeLine = null;
    }

    for (final line in _routeLines) {
      try {
        await _controller!.removeLine(line);
      } catch (_) {}
    }
    _routeLines.clear();
  }

  Future<void> _drawMainRoute(List<LatLng> points) async {
    if (points.length < 2) return;

    final coordinates = points
        .map((p) => maplibre.LatLng(p.latitude, p.longitude))
        .toList();

    final dashLength = 15.0;
    final gapLength = 8.0;

    List<maplibre.Line> dashLines = [];

    for (int i = 0; i < coordinates.length - 1; i++) {
      final start = coordinates[i];
      final end = coordinates[i + 1];

      final distance = _calculateDistance(start, end);
      final segments = (distance / (dashLength + gapLength)).ceil();

      for (int j = 0; j < segments; j++) {
        final progress = j / segments;
        final nextProgress = (j + 1) / segments;

        final dashStart = _interpolatePoint(start, end, progress);
        final dashEnd = _interpolatePoint(start, end, nextProgress);

        final dashLine = await _controller!.addLine(
          maplibre.LineOptions(
            geometry: [dashStart, dashEnd],
            lineWidth: 6.0,
            lineColor: '#FF8C00',
            lineOpacity: 0.9,
          ),
        );

        dashLines.add(dashLine);
      }
    }

    _routeLine = null;
    _routeLines.addAll(dashLines);

    await _addStartEndMarkers();
  }

  double _calculateDistance(maplibre.LatLng start, maplibre.LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  maplibre.LatLng _interpolatePoint(
    maplibre.LatLng start,
    maplibre.LatLng end,
    double progress,
  ) {
    final lat = start.latitude + (end.latitude - start.latitude) * progress;
    final lng = start.longitude + (end.longitude - start.longitude) * progress;
    return maplibre.LatLng(lat, lng);
  }

  Future<void> _addStartEndMarkers() async {
    if (startPoint == null || endPoint == null || _controller == null) return;

    final startSymbol = await _controller!.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(startPoint!.latitude, startPoint!.longitude),
        iconImage: 'marker-15',
        iconSize: 3.0,
        iconColor: '#4CAF50',
        iconHaloColor: '#FFFFFF',
        iconHaloWidth: 2.0,
        textField: 'Konumum',
        textSize: 12.0,
        textColor: '#FFFFFF',
        textHaloColor: '#000000',
        textHaloWidth: 1.0,
      ),
    );
    _routeSymbols.add(startSymbol);

    final endSymbol = await _controller!.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(endPoint!.latitude, endPoint!.longitude),
        iconImage: 'marker-15',
        iconSize: 3.0,
        iconColor: '#F44336',
        iconHaloColor: '#FFFFFF',
        iconHaloWidth: 2.0,
        textField: 'Hedef',
        textSize: 12.0,
        textColor: '#FFFFFF',
        textHaloColor: '#000000',
        textHaloWidth: 1.0,
      ),
    );
    _routeSymbols.add(endSymbol);
  }

  Future<void> _clearPreviousRouteIndicators() async {
    if (_controller != null) {
      if (_routeLine != null) {
        try {
          await _controller!.removeLine(_routeLine!);
        } catch (_) {}
        _routeLine = null;
      }

      for (final line in _routeLines) {
        try {
          await _controller!.removeLine(line);
        } catch (_) {}
      }
      _routeLines.clear();

      if (_endPointSymbol != null) {
        try {
          await _controller!.removeSymbol(_endPointSymbol!);
        } catch (_) {}
        _endPointSymbol = null;
      }

      for (final symbol in _routeSymbols) {
        try {
          await _controller!.removeSymbol(symbol);
        } catch (_) {}
      }
      _routeSymbols.clear();
    }

    setState(() {
      routePoints.clear();
      routeDistanceKm = null;
      routeDurationMin = null;
    });
  }

  void clearRoute() async {
    if (_controller != null) {
      if (_routeLine != null) {
        try {
          await _controller!.removeLine(_routeLine!);
        } catch (_) {}
        _routeLine = null;
      }

      for (final line in _routeLines) {
        try {
          await _controller!.removeLine(line);
        } catch (_) {}
      }
      _routeLines.clear();

      if (_endPointSymbol != null) {
        try {
          await _controller!.removeSymbol(_endPointSymbol!);
        } catch (_) {}
        _endPointSymbol = null;
      }

      for (final symbol in _routeSymbols) {
        try {
          await _controller!.removeSymbol(symbol);
        } catch (_) {}
      }
      _routeSymbols.clear();
    }

    setState(() {
      startPoint = null;
      endPoint = null;
      routePoints.clear();
      routeDistanceKm = null;
      routeDurationMin = null;
      isStartPointFixed = false;
      _hasAnnouncedRouteStart = false; // Reset
      _hasAnnouncedDestinationReached = false; // Reset
      _lastAnnouncedTurnIndex = null; // Reset
      _hasAnnouncedOffRoute = false; // Reset
    });

    final pos = await _getCurrentLocation();
    if (pos != null) {
      updateCurrentLocationMarker(pos);
    }
    await _announceRouteCleared();
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

  String _getMapLibreIcon(String type) {
    switch (type) {
      case 'rampa':
      case 'asansör':
      case 'yaya_gecidi':
      case 'trafik_isigi':
      case 'ust_gecit':
        return 'marker-15';
      default:
        return 'marker-15';
    }
  }

  double _getMarkerSize(String type) {
    switch (type) {
      case 'rampa':
        return 3.0; // Daha büyük ve görünür
      case 'asansör':
        return 2.8;
      case 'yaya_gecidi':
        return 2.5;
      case 'trafik_isigi':
        return 2.5;
      case 'ust_gecit':
        return 2.8;
      default:
        return 2.5;
    }
  }

  Color _getMarkerColor(String type) {
    switch (type) {
      case 'rampa':
        return Colors.green.shade700;
      case 'asansör':
        return Colors.orange.shade700;
      case 'yaya_gecidi':
        return Colors.blue.shade700;
      case 'trafik_isigi':
        return Colors.red.shade700;
      case 'ust_gecit':
        return Colors.purple.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _getMarkerTextColor(String type) {
    switch (type) {
      case 'rampa':
        return '#006400';
      case 'asansör':
        return '#CC6600';
      case 'yaya_gecidi':
        return '#0033CC';
      case 'trafik_isigi':
        return '#CC0000';
      case 'ust_gecit':
        return '#660066';
      default:
        return '#333333';
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

  Future<void> _highlightNearestAccessiblePoints() async {
    if (startPoint == null || _controller == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('markers')
          .get();

      List<MapEntry<MarkerModel, double>> accessiblePoints = [];

      for (final doc in snapshot.docs) {
        final marker = MarkerModel.fromMap(doc.data());
        final point = LatLng(marker.latitude, marker.longitude);

        if (!_isAccessibleType(marker.type)) continue;

        final distance = Geolocator.distanceBetween(
          startPoint!.latitude,
          startPoint!.longitude,
          point.latitude,
          point.longitude,
        );

        accessiblePoints.add(MapEntry(marker, distance));
      }

      accessiblePoints.sort((a, b) => a.value.compareTo(b.value));

      final nearestPoints = accessiblePoints.take(3).toList();

      if (nearestPoints.isNotEmpty) {
        for (final entry in nearestPoints) {
          final marker = entry.key;
          final docId =
              marker.type +
              marker.latitude.toString() +
              marker.longitude.toString();
          if (_symbols.containsKey(docId)) {
            await _controller!.updateSymbol(
              _symbols[docId]!,
              maplibre.SymbolOptions(
                iconSize: _getMarkerSize(marker.type) * 1.5,
                iconHaloColor: '#FFFF00',
                iconHaloWidth: 3.0,
              ),
            );
          }
        }

        final nearestPoint = nearestPoints.first;
        final marker = nearestPoint.key;
        final distance = nearestPoint.value;

        await _controller!.animateCamera(
          maplibre.CameraUpdate.newLatLngZoom(
            maplibre.LatLng(marker.latitude, marker.longitude),
            18,
          ),
        );

        _showMessage(
          'En yakın ${_typeToLabel(marker.type)}: ${distance < 1000 ? '${distance.toInt()}m' : '${(distance / 1000).toStringAsFixed(1)}km'} uzaklıkta',
        );
        await _announceAccessiblePointNearby(
          LatLng(marker.latitude, marker.longitude),
          marker.type,
        );
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
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text(
          "Harita",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(
                _isVoiceEnabled ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _isVoiceEnabled = !_isVoiceEnabled;
                });
                if (_isVoiceEnabled) {
                  _speak('Sesli yönlendirme aktif');
                } else {
                  _speak('Sesli yönlendirme devre dışı');
                }
              },
              tooltip: _isVoiceEnabled
                  ? 'Sesli Yönlendirmeyi Kapat'
                  : 'Sesli Yönlendirmeyi Aç',
            ),
          ),

          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: clearRoute,
              tooltip: 'Rota Sıfırla',
            ),
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
                        leading: const Icon(Icons.gps_fixed),
                        title: const Text('Başlangıç Noktası Ekle'),
                        onTap: () => Navigator.pop(context, 'start'),
                      ),
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

              if (action == 'start') {
                setState(() {
                  startPoint = LatLng(latLng.latitude, latLng.longitude);
                  isStartPointFixed = true;
                });
                await _clearPreviousRouteIndicators();
                if (_currentLocationSymbol != null) {
                  await _controller!.removeSymbol(_currentLocationSymbol!);
                  _currentLocationSymbol = null;
                }
                updateCurrentLocationMarker(startPoint!);
                await _controller!.animateCamera(
                  maplibre.CameraUpdate.newLatLngZoom(latLng, 17),
                );
                if (endPoint != null) {
                  await drawRoute();
                  await _announceNavigationStart();
                }
              } else if (action == 'target') {
                setState(() {
                  endPoint = LatLng(latLng.latitude, latLng.longitude);
                });
                await _clearPreviousRouteIndicators();
                if (_endPointSymbol != null) {
                  await _controller!.removeSymbol(_endPointSymbol!);
                }
                _endPointSymbol = await _controller!.addSymbol(
                  maplibre.SymbolOptions(
                    geometry: latLng,
                    iconImage: 'marker-15',
                    iconSize: 3.0,
                    iconColor: '#FF0000',
                    iconHaloColor: '#FFFFFF',
                    iconHaloWidth: 2.0,
                  ),
                );
                await drawRoute();
                await _announceNavigationStart();
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
                            onPressed: () =>
                                Navigator.pop(context, controller.text),
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
                            latitude: latLng.latitude,
                            longitude: latLng.longitude,
                            description: description,
                            likes: 0,
                            createdAt: DateTime.now(),
                          ).toMap(),
                        );
                    _showMessage("Erişim noktası başarıyla eklendi!");
                    await _announceMarkerAdded(selectedType);
                  }
                }
              }
            },
          ),
          // UI Overlay
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Route Info Card
              if (routeDistanceKm != null && routeDurationMin != null)
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: AppTheme.cardDecoration,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.directions,
                            color: AppTheme.primaryBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Rota Bilgileri",
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${routeDistanceKm!.toStringAsFixed(2)} km • ${routeDurationMin!.toStringAsFixed(0)} dk",
                                style: AppTheme.bodyLarge.copyWith(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Marker Count Info
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: AppTheme.cardDecorationLight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: AppTheme.primaryBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Gösterilen: $_totalAccessiblePoints nokta',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (selectedFilter != 'hepsi')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            selectedFilter.toUpperCase(),
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Filter Controls
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: AppTheme.cardDecoration,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(child: _buildFilterDropdown()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildProfileDropdown()),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.my_location,
                        label: 'Konumum',
                        gradient: AppTheme.primaryGradient,
                        onTap: () async {
                          final pos = await _getCurrentLocation();
                          if (pos != null) {
                            centerOnCurrentLocation(pos);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.add_location_alt,
                        label: 'Ekle',
                        gradient: AppTheme.secondaryGradient,
                        onTap: () async {
                          String?
                          selectedType = await showModalBottomSheet<String>(
                            context: context,
                            backgroundColor: AppTheme.backgroundWhite,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            builder: (context) {
                              return Container(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 20),
                                      decoration: BoxDecoration(
                                        color: AppTheme.textLight,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    Text(
                                      'Erişim Noktası Türü Seçin',
                                      style: AppTheme.headingSmall,
                                    ),
                                    const SizedBox(height: 20),
                                    _buildMarkerTypeTile(
                                      icon: Icons.accessible_forward,
                                      title: 'Rampa',
                                      color: AppTheme.secondaryGreen,
                                      onTap: () =>
                                          Navigator.pop(context, 'rampa'),
                                    ),
                                    _buildMarkerTypeTile(
                                      icon: Icons.elevator,
                                      title: 'Asansör',
                                      color: AppTheme.secondaryOrange,
                                      onTap: () =>
                                          Navigator.pop(context, 'asansör'),
                                    ),
                                    _buildMarkerTypeTile(
                                      icon: Icons.directions_walk,
                                      title: 'Yaya Geçidi',
                                      color: AppTheme.secondaryPurple,
                                      onTap: () =>
                                          Navigator.pop(context, 'yaya_gecidi'),
                                    ),
                                    _buildMarkerTypeTile(
                                      icon: Icons.traffic,
                                      title: 'Trafik Işığı',
                                      color: AppTheme.error,
                                      onTap: () => Navigator.pop(
                                        context,
                                        'trafik_isigi',
                                      ),
                                    ),
                                    _buildMarkerTypeTile(
                                      icon: Icons.alt_route,
                                      title: 'Üst/Alt Geçit',
                                      color: AppTheme.info,
                                      onTap: () =>
                                          Navigator.pop(context, 'ust_gecit'),
                                    ),
                                  ],
                                ),
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
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    title: Text(
                                      "Açıklama Girin",
                                      style: AppTheme.headingSmall,
                                    ),
                                    content: TextField(
                                      controller: controller,
                                      style: AppTheme.bodyMedium,
                                      decoration: AppTheme.inputDecoration(
                                        'Kısa açıklama',
                                        Icons.description,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, null),
                                        child: Text(
                                          "İptal",
                                          style: AppTheme.bodyMedium.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(
                                          context,
                                          controller.text,
                                        ),
                                        style: AppTheme.primaryButtonStyle,
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
                                await _announceMarkerAdded(selectedType);
                              }
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.near_me,
                        label: 'Yakındakiler',
                        gradient: AppTheme.accentGradient,
                        onTap: () async {
                          if (startPoint != null) {
                            await _highlightNearestAccessiblePoints();
                          } else {
                            _showMessage('Önce konumunuzu alın');
                          }
                        },
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

  // Helper methods for improved UI
  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.cardDecorationLight,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: AppTheme.bodyLarge),
        subtitle: Text(subtitle, style: AppTheme.bodySmall),
        onTap: onTap,
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: AppTheme.textLight,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildMarkerTypeTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.cardDecorationLight,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: AppTheme.bodyLarge),
        onTap: onTap,
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: AppTheme.textLight,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedFilter,
          isExpanded: true,
          dropdownColor: AppTheme.backgroundWhite,
          icon: Icon(Icons.filter_list, color: AppTheme.primaryBlue),
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          items: [
            DropdownMenuItem(value: 'hepsi', child: Text('Hepsi')),
            DropdownMenuItem(value: 'rampa', child: Text('Rampa')),
            DropdownMenuItem(value: 'asansör', child: Text('Asansör')),
            DropdownMenuItem(value: 'yaya_gecidi', child: Text('Yaya Geçidi')),
            DropdownMenuItem(
              value: 'trafik_isigi',
              child: Text('Trafik Işığı'),
            ),
            DropdownMenuItem(value: 'ust_gecit', child: Text('Üst/Alt Geçit')),
          ],
          onChanged: (value) async {
            setState(() {
              selectedFilter = value!;
            });

            // Filtre değiştiğinde mevcut marker'ları temizle ve yeniden yükle
            if (_controller != null) {
              for (final symbol in _symbols.values) {
                try {
                  await _controller!.removeSymbol(symbol);
                } catch (_) {}
              }
              _symbols.clear();
            }

            // Yeni filtreye göre marker'ları yükle
            _listenFirestoreMarkers();
          },
        ),
      ),
    );
  }

  Widget _buildProfileDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedProfile,
          isExpanded: true,
          dropdownColor: AppTheme.backgroundWhite,
          icon: Icon(Icons.accessible, color: AppTheme.primaryBlue),
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
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
    );
  }

  void _showMarkerDetails(MarkerModel marker, String docId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundWhite,
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
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.textLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getMarkerColor(marker.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getIcon(marker.type),
                      color: _getMarkerColor(marker.type),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeToLabel(marker.type),
                          style: AppTheme.headingMedium,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getMarkerColor(
                              marker.type,
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
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
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Description
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecorationLight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.description,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        marker.description,
                        style: AppTheme.bodyMedium.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Coordinates
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Koordinatlar: ${marker.latitude.toStringAsFixed(5)}, ${marker.longitude.toStringAsFixed(5)}",
                        style: AppTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),

              // Created date
              if (marker.createdAt != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Eklenme: ${DateFormat('dd.MM.yyyy HH:mm').format(marker.createdAt!)}",
                        style: AppTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Actions and likes
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
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
                      style: AppTheme.primaryButtonStyle.copyWith(
                        backgroundColor: MaterialStateProperty.all(
                          AppTheme.success,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              title: Text(
                                "Erişim Noktasını Sil",
                                style: AppTheme.headingSmall,
                              ),
                              content: Text(
                                "Bu erişim noktasını silmek istediğinize emin misiniz?",
                                style: AppTheme.bodyMedium,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(
                                    "İptal",
                                    style: AppTheme.bodyMedium.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: AppTheme.primaryButtonStyle.copyWith(
                                    backgroundColor: MaterialStateProperty.all(
                                      AppTheme.error,
                                    ),
                                  ),
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
                      style: AppTheme.primaryButtonStyle.copyWith(
                        backgroundColor: MaterialStateProperty.all(
                          AppTheme.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Likes count
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite,
                        color: AppTheme.primaryBlue,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${marker.likes} kişi faydalı buldu",
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
