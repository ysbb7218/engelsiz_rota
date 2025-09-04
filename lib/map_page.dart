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
import 'package:engelsiz_rota/view/route_details_page.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  // TTS Controller for voice guidance
  FlutterTts? _flutterTts;
  bool _isVoiceEnabled = true;

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

  // Rota dışında olduğunu duyurmak için
  bool _hasAnnouncedOffRoute = false;

  // Hedef noktaya ulaştığını duyurmak için
  bool _hasAnnouncedDestinationReached = false;

  bool _routeCreatedAnnounced = false; // rota oluşturuldu anonsunu 1 kez söyle
  final Set<int> _announcedTurnSteps = {}; // her dönüş adımı için 1 kez
  bool _isSpeaking = false; // TTS çakışmalarını engelle
  bool _isBottomSheetOpen = false; // Bottom sheet kontrolü
  DateTime? _lastTapTime; // Debounce için son tıklama zamanı

  LatLng? startPoint;
  LatLng? endPoint;
  List<LatLng> routePoints = [];
  List<RouteWaypoint> routeWaypoints = []; // Waypoint'ler için yön bilgisi
  List<Map<String, dynamic>> navigationSteps =
      []; // Navigasyon adımları ve sebepleri
  double? routeDistanceKm;
  double? routeDurationMin;
  String selectedFilter = 'hepsi';
  String selectedProfile = 'wheelchair'; // Sadece tekerlekli sandalye
  bool isStartPointFixed = false; // Başlangıç noktası sabit mi?
  bool isNavigationStarted = false; // Navigasyon başlatıldı mı?
  int currentStepIndex = 0; // Mevcut adım indeksi

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

    // Harita açıldığında Afyon koordinatlarında başla, konum güncellemeye devam et ama kamerayı otomatik ışınlama
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // _setInitialLocation(); // Bu çağrıyı kaldırdık, kamerayı Afyon'da bırak
    });

    locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!isStartPointFixed) {
        // Sadece başlangıç noktası sabit değilse güncelle
        final pos = await _getCurrentLocation();
        if (pos != null) {
          updateCurrentLocationMarker(pos);
          // Sadece navigasyon başladığında sesli uyarıları kontrol et
          if (isNavigationStarted) {
            await _announceRouteProgress();
            await _checkOffRoute();
            await _checkAndAnnounceTurnApproaching();
          }

          // Navigasyon başlatıldığında rota odaklı kamera
          if (isNavigationStarted &&
              _controller != null &&
              routePoints.isNotEmpty) {
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
          }
        }
      }
    });
  }

  // TTS initialization
  void _initializeTTS() async {
    _flutterTts = FlutterTts();
    await _flutterTts!.awaitSpeakCompletion(true);
    _flutterTts!.setCompletionHandler(() {
      _isSpeaking = false;
    });

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
    if (!_isVoiceEnabled || _flutterTts == null || !isNavigationStarted) return;
    if (_isSpeaking) return; // aynı anda birden fazla konuşma engeli
    _isSpeaking = true;
    try {
      await _flutterTts!.speak(text);
    } catch (e) {
      // sessizce yut
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> _announceRouteCreated() async {
    if (_routeCreatedAnnounced) return; // sadece 1 kez
    if (routeDistanceKm != null && routeDurationMin != null) {
      final distanceText = routeDistanceKm! < 1
          ? '${(routeDistanceKm! * 1000).toInt()} metre'
          : '${routeDistanceKm!.toStringAsFixed(1)} kilometre';
      final durationText = routeDurationMin! < 1
          ? '${(routeDurationMin! * 60).toInt()} saniye'
          : '${routeDurationMin!.toInt()} dakika';
      final announcement =
          'Rota oluşturuldu. Mesafe: $distanceText, süre: $durationText. '
          'Tekerlekli sandalye için erişilebilir rota hazır.';
      await _speak(announcement);
      _routeCreatedAnnounced = true;
    }
  }

  Future<void> _announceRouteProgress() async {
    if (_hasAnnouncedDestinationReached) return;
    if (routePoints.isEmpty || startPoint == null) return;

    if (routePoints.length >= 2) {
      final lastPoint = routePoints.last;
      final distanceToEnd = Geolocator.distanceBetween(
        startPoint!.latitude,
        startPoint!.longitude,
        lastPoint.latitude,
        lastPoint.longitude,
      );

      if (distanceToEnd < 10 && !_hasAnnouncedDestinationReached) {
        await _speak('Hedef noktaya ulaştınız! Yolculuğunuz tamamlandı.');
        _hasAnnouncedDestinationReached = true;
      }
    }
  }

  // Dönüşlere yaklaşıldığında uyarı ver
  Future<void> _checkAndAnnounceTurnApproaching() async {
    if (routePoints.isEmpty || startPoint == null || navigationSteps.isEmpty)
      return;
    if (currentStepIndex < navigationSteps.length) {
      final currentStep = navigationSteps[currentStepIndex];
      final turnDirection = currentStep['turnDirection'] as String;
      final distance = currentStep['distance'] as double;

      // sadece "düz" değilse ve 50m kala ve bu adım için daha önce söylemediysek
      if (turnDirection != 'düz' &&
          distance <= 50 &&
          !_announcedTurnSteps.contains(currentStepIndex)) {
        final direction = currentStep['direction'] as String;
        final reason = currentStep['reason'] as String;

        String turnType;
        switch (turnDirection) {
          case 'sağa':
            turnType = 'Sağa dönüş';
            break;
          case 'sola':
            turnType = 'Sola dönüş';
            break;
          case 'geri':
            turnType = 'Geri dönüş';
            break;
          default:
            turnType = 'Dönüş';
        }

        await _speak('$turnType yaklaşıyor. $direction. $reason');
        _announcedTurnSteps.add(currentStepIndex);
      }
    }
  }

  // Mevcut konumdan hedefe olan kalan mesafeyi hesapla
  double _calculateRemainingDistance() {
    if (routePoints.isEmpty || startPoint == null) return 0.0;

    double totalRemainingDistance = 0.0;

    // Mevcut adımdan itibaren kalan mesafeyi hesapla
    for (int i = currentStepIndex; i < navigationSteps.length; i++) {
      final step = navigationSteps[i];
      totalRemainingDistance += step['distance'] as double;
    }

    return totalRemainingDistance;
  }

  // Kalan süreyi hesapla (tekerlekli sandalye hızı: ~1.4 m/s)
  double _calculateRemainingDuration() {
    final remainingDistance = _calculateRemainingDistance();
    const wheelchairSpeed = 1.4; // m/s
    return remainingDistance / wheelchairSpeed / 60; // dakika cinsinden
  }

  // Mesafeyi formatla
  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toInt()} m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  // Süreyi formatla
  String _formatDuration(double durationInMinutes) {
    if (durationInMinutes < 1) {
      return '${(durationInMinutes * 60).toInt()} sn';
    } else if (durationInMinutes < 60) {
      return '${durationInMinutes.toInt()} dk';
    } else {
      final hours = (durationInMinutes / 60).floor();
      final minutes = (durationInMinutes % 60).toInt();
      return '${hours}s ${minutes}dk';
    }
  }

  Future<void> _announceNavigationStart() async {
    if (startPoint != null && endPoint != null) {
      final announcement =
          'Navigasyon başlatılıyor. Başlangıç noktasından hedef noktaya doğru yönlendiriliyorsunuz.';
      await _speak(announcement);
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

    // Symbol tap olayını bir kez tanımla
    _controller!.onSymbolTapped.add((symbol) {
      print('=== Sembol tıklandı: ${symbol.id} ==='); // Hata ayıklama için log

      // Tıklanan sembolün ID'sini bul
      final markerEntry = _symbols.entries.firstWhere(
        (entry) => entry.value == symbol,
        orElse: () => MapEntry('', symbol),
      );

      if (markerEntry.key.isNotEmpty) {
        print(
          'Marker ID bulundu: ${markerEntry.key}',
        ); // Hata ayıklama için log
        FirebaseFirestore.instance
            .collection('markers')
            .doc(markerEntry.key)
            .get()
            .then((doc) {
              if (doc.exists) {
                print(
                  'Firestore verisi alındı: ${doc.data()}',
                ); // Hata ayıklama için log
                final marker = MarkerModel.fromMap(doc.data()!);
                _showMarkerDetails(marker, doc.id);
              } else {
                print('Firestore belgesi bulunamadı: ${markerEntry.key}');
                _showMessage('Marker detayları bulunamadı.');
              }
            })
            .catchError((e) {
              print('Firestore hatası: $e');
              _showMessage('Marker detayları alınırken hata oluştu: $e');
            });
      } else {
        print('Eşleşen marker ID bulunamadı.');
        _showMessage('Bu marker için detay bulunamadı.');
      }
    });

    // Harita hazır olduğunda marker'ları göster
    _listenFirestoreMarkers();
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

    _markerSub?.cancel();
    _markerSub = coll.snapshots().listen((snap) async {
      if (_controller == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller == null) return;
      }

      // Mevcut marker'ları temizle
      for (final symbol in _symbols.values.toList()) {
        try {
          await _controller!.removeSymbol(symbol);
        } catch (_) {}
      }
      _symbols.clear();

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

        // Filtre kontrolü
        if (selectedFilter != 'hepsi' && marker.type != selectedFilter) {
          continue;
        }

        final lat = marker.latitude;
        final lng = marker.longitude;
        final docId = doc.id;

        if (_symbols.containsKey(docId)) {
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
            try {
              await _controller!.removeSymbol(_symbols[docId]!);
            } catch (_) {}
            _symbols.remove(docId);
          }
        }

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
              distanceText = distance < 1000
                  ? '${distance.toInt()}m'
                  : '${(distance / 1000).toStringAsFixed(1)}km';
            }

            final symbol = await _controller!.addSymbol(
              maplibre.SymbolOptions(
                geometry: maplibre.LatLng(lat, lng),
                iconImage: _getMapLibreIcon(marker.type),
                iconSize: _getMarkerSize(marker.type),
                iconColor: _getMarkerColor(marker.type).value.toRadixString(16),
                iconOffset: const Offset(0, -10),
                iconHaloColor: '#FFFFFF',
                iconHaloWidth: 3.0,
                textField: distanceText != null
                    ? '${_typeToLabel(marker.type)}\n$distanceText'
                    : _typeToLabel(marker.type),
                textSize: 12.0,
                textColor: _getMarkerTextColor(marker.type),
                textHaloColor: '#FFFFFF',
                textHaloWidth: 3.0,
                textOffset: const Offset(0, 2.0),
              ),
            );
            _symbols[docId] = symbol;
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
    });
  }

  Future<Map<String, dynamic>> getRoute(LatLng start, LatLng end) async {
    print('=== TEKERLEKLİ SANDALYE İÇİN BASİT ROTA ALGORİTMASI ===');
    print('📍 Başlangıç: ${start.latitude}, ${start.longitude}');
    print('🎯 Bitiş: ${end.latitude}, ${end.longitude}');
    print('♿ Profil: $selectedProfile');

    try {
      List<LatLng> accessiblePoints = await _findAccessiblePoints(start, end);
      print('♿ ${accessiblePoints.length} erişilebilir nokta bulundu');

      List<RouteWaypoint> selectedWaypoints = _selectBestWaypoints(
        start,
        end,
        accessiblePoints,
      );
      print('🔄 ${selectedWaypoints.length} waypoint seçildi');

      // Waypoint'leri LatLng listesine çevir
      List<LatLng> waypointLocations = selectedWaypoints
          .map((wp) => wp.location)
          .toList();

      List<LatLng> route = await _createSimpleRoute(
        start,
        end,
        waypointLocations,
      );

      if (route.isNotEmpty) {
        print('✅ Rota başarıyla oluşturuldu: ${route.length} nokta');
        return {'route': route, 'waypoints': selectedWaypoints};
      } else {
        print('⚠️ Rota oluşturulamadı, düz rota deneniyor');
        final directRoute = await _createDirectRoute(start, end);
        return {'route': directRoute, 'waypoints': <RouteWaypoint>[]};
      }
    } catch (e) {
      print('❌ Rota oluşturma hatası: $e');
      final directRoute = await _createDirectRoute(start, end);
      return {'route': directRoute, 'waypoints': <RouteWaypoint>[]};
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

  List<RouteWaypoint> _selectBestWaypoints(
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

    // Waypoint'ler için yön bilgisi oluştur
    List<RouteWaypoint> waypoints = [];
    for (final point in topPoints) {
      final direction = _calculateDirection(start, end, point);
      final reason = _getDirectionReason(direction, point);
      final type = _getWaypointType(point);

      waypoints.add(
        RouteWaypoint(
          location: point,
          type: type,
          direction: direction,
          reason: reason,
          distanceFromStart: Geolocator.distanceBetween(
            start.latitude,
            start.longitude,
            point.latitude,
            point.longitude,
          ),
          distanceToEnd: Geolocator.distanceBetween(
            point.latitude,
            point.longitude,
            end.latitude,
            end.longitude,
          ),
        ),
      );
    }

    return waypoints;
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

  String _calculateDirection(LatLng start, LatLng end, LatLng waypoint) {
    // Başlangıçtan bitişe olan ana yön
    final mainBearing = _getBearing(start, end);

    // Başlangıçtan waypoint'e olan yön
    final waypointBearing = _getBearing(start, waypoint);

    // Yön farkını hesapla
    final bearingDiff = _getBearingDifference(mainBearing, waypointBearing);

    if (bearingDiff.abs() <= 15) {
      return 'düz';
    } else if (bearingDiff > 0) {
      return 'sağ';
    } else {
      return 'sol';
    }
  }

  String _getDirectionReason(String direction, LatLng waypoint) {
    switch (direction) {
      case 'sağ':
        return 'Erişilebilir nokta ana rotanın sağında bulunuyor ve tekerlekli sandalye için daha uygun';
      case 'sol':
        return 'Erişilebilir nokta ana rotanın solunda bulunuyor ve tekerlekli sandalye için daha uygun';
      case 'düz':
        return 'Erişilebilir nokta ana rota üzerinde veya çok yakınında bulunuyor';
      default:
        return 'Erişilebilir nokta rota planlaması için uygun konumda';
    }
  }

  String _getWaypointType(LatLng waypoint) {
    // Bu noktada gerçek uygulamada Firebase'den waypoint'in tipini alabiliriz
    // Şimdilik genel bir tip döndürüyoruz
    return 'erişilebilir_nokta';
  }

  Future<String> _getTurnReason(
    LatLng from,
    LatLng to,
    LatLng? nextPoint,
  ) async {
    final bearing = _getBearing(from, to);
    final turnDirection = _getTurnDirection(bearing);

    // Eğer bir sonraki nokta varsa, dönüşün sebebini analiz et
    if (nextPoint != null) {
      // Yakındaki erişilebilir noktaları kontrol et
      final nearbyAccessiblePoints = await _findNearbyAccessiblePoints(to, 100);

      if (nearbyAccessiblePoints.isNotEmpty) {
        final closestPoint = nearbyAccessiblePoints.first;
        final pointType = _typeToLabel(closestPoint['type'] as String? ?? '');

        if (turnDirection == 'sağa') {
          return 'Sağa dönüş: $pointType erişilebilir noktasına ulaşmak için';
        } else if (turnDirection == 'sola') {
          return 'Sola dönüş: $pointType erişilebilir noktasına ulaşmak için';
        } else {
          return 'Düz devam: $pointType erişilebilir noktası yakınında';
        }
      }
    }

    // Genel dönüş sebepleri
    switch (turnDirection) {
      case 'sağa':
        return 'Sağa dönüş: Tekerlekli sandalye için daha erişilebilir yol';
      case 'sola':
        return 'Sola dönüş: Tekerlekli sandalye için daha erişilebilir yol';
      case 'geri':
        return 'Geri dönüş: Rota optimizasyonu için';
      default:
        return 'Düz devam: Ana rota takibi';
    }
  }

  String _getTurnDirection(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) {
      return 'düz';
    } else if (bearing >= 22.5 && bearing < 67.5) {
      return 'sağa';
    } else if (bearing >= 67.5 && bearing < 112.5) {
      return 'sağa';
    } else if (bearing >= 112.5 && bearing < 157.5) {
      return 'sağa';
    } else if (bearing >= 157.5 && bearing < 202.5) {
      return 'geri';
    } else if (bearing >= 202.5 && bearing < 247.5) {
      return 'sola';
    } else if (bearing >= 247.5 && bearing < 292.5) {
      return 'sola';
    } else {
      return 'sola';
    }
  }

  Future<List<Map<String, dynamic>>> _findNearbyAccessiblePoints(
    LatLng point,
    double radius,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('markers')
          .get();

      List<Map<String, dynamic>> nearbyPoints = [];

      for (final doc in snapshot.docs) {
        final marker = MarkerModel.fromMap(doc.data());
        final markerPoint = LatLng(marker.latitude, marker.longitude);

        if (!_isAccessibleType(marker.type)) continue;

        final distance = Geolocator.distanceBetween(
          point.latitude,
          point.longitude,
          markerPoint.latitude,
          markerPoint.longitude,
        );

        if (distance <= radius) {
          nearbyPoints.add({
            'type': marker.type,
            'distance': distance,
            'point': markerPoint,
          });
        }
      }

      // Mesafeye göre sırala
      nearbyPoints.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double),
      );
      return nearbyPoints;
    } catch (e) {
      print('Yakındaki noktalar bulunamadı: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _createNavigationSteps(
    List<LatLng> routePoints,
  ) async {
    List<Map<String, dynamic>> steps = [];

    if (routePoints.length < 2) return steps;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final from = routePoints[i];
      final to = routePoints[i + 1];
      final nextPoint = i + 2 < routePoints.length ? routePoints[i + 2] : null;

      final distance = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );

      final direction = _getDirection(from, to);
      final turnReason = await _getTurnReason(from, to, nextPoint);
      final turnDirection = _getTurnDirection(_getBearing(from, to));

      steps.add({
        'step': i + 1,
        'from': from,
        'to': to,
        'distance': distance,
        'direction': direction,
        'turnDirection': turnDirection,
        'reason': turnReason,
        'isLast': i == routePoints.length - 2,
      });
    }

    return steps;
  }

  String _getDirection(LatLng from, LatLng to) {
    final bearing = _getBearing(from, to);

    if (bearing >= 337.5 || bearing < 22.5) {
      return 'Kuzey yönünde';
    } else if (bearing >= 22.5 && bearing < 67.5) {
      return 'Kuzeydoğu yönünde';
    } else if (bearing >= 67.5 && bearing < 112.5) {
      return 'Doğu yönünde';
    } else if (bearing >= 112.5 && bearing < 157.5) {
      return 'Güneydoğu yönünde';
    } else if (bearing >= 157.5 && bearing < 202.5) {
      return 'Güney yönünde';
    } else if (bearing >= 202.5 && bearing < 247.5) {
      return 'Güneybatı yönünde';
    } else if (bearing >= 247.5 && bearing < 292.5) {
      return 'Batı yönünde';
    } else {
      return 'Kuzeybatı yönünde';
    }
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
      await _speak('Rotadan çıktınız. Lütfen rotaya dönün.');
      _hasAnnouncedOffRoute = true;
    } else if (minDistanceToRoute <= 50 && _hasAnnouncedOffRoute) {
      _hasAnnouncedOffRoute = false;
    }
  }

  Future<void> startNavigation() async {
    if (routePoints.isEmpty) {
      _showMessage('Önce rota oluşturun');
      return;
    }

    setState(() {
      isNavigationStarted = true;
      currentStepIndex = 0;
    });

    // Rota odaklı kamera ayarı
    if (_controller != null && routePoints.isNotEmpty) {
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
    }

    // Sesli yönlendirme başlat
    await _speak('Navigasyon başlatıldı. Rota takip ediliyor.');
    await _announceCurrentStep();
  }

  // Navigasyon sonlandırma fonksiyonu
  Future<void> stopNavigation() async {
    setState(() {
      isNavigationStarted = false;
      currentStepIndex = 0;
    });

    // Rota üzerindeki hedef noktaları sil
    clearRoute();

    await _speak('Navigasyon sonlandırıldı.');
  }

  // Mevcut adımı duyur
  Future<void> _announceCurrentStep() async {
    if (!isNavigationStarted || navigationSteps.isEmpty) return;

    if (currentStepIndex < navigationSteps.length) {
      final step = navigationSteps[currentStepIndex];
      final direction = step['direction'];
      final distance = step['distance'] as double;
      final reason = step['reason'];

      String distanceText = distance < 1000
          ? '${distance.toInt()} metre'
          : '${(distance / 1000).toStringAsFixed(1)} kilometre';

      await _speak('$direction $distanceText. $reason');
    } else {
      await _speak('Hedef noktaya ulaştınız!');
    }
  }

  Future<void> drawRoute() async {
    if (startPoint == null || endPoint == null || _controller == null) {
      _showMessage('Başlangıç veya bitiş noktası eksik.');
      return;
    }

    final routeData = await getRoute(startPoint!, endPoint!);
    final points = routeData['route'] as List<LatLng>;
    final waypoints = routeData['waypoints'] as List<RouteWaypoint>;

    if (points.isNotEmpty) {
      // Navigasyon adımlarını oluştur
      final steps = await _createNavigationSteps(points);

      setState(() {
        routePoints = points;
        routeWaypoints = waypoints;
        navigationSteps = steps;

        // TTS tekrar kontrol resetleri
        _routeCreatedAnnounced = false;
        _announcedTurnSteps.clear();
        _hasAnnouncedDestinationReached = false;
      });

      await _clearAllRoutes();

      await _drawMainRoute(points);

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
    await _clearAllRoutes();

    setState(() {
      routePoints.clear();
      routeDistanceKm = null;
      routeDurationMin = null;
      _routeCreatedAnnounced = false;
      _announcedTurnSteps.clear();
      _hasAnnouncedDestinationReached = false;
    });
  }

  void clearRoute() async {
    await _clearAllRoutes();

    setState(() {
      startPoint = null;
      endPoint = null;
      routePoints.clear();
      routeWaypoints.clear();
      navigationSteps.clear();
      routeDistanceKm = null;
      routeDurationMin = null;
      isStartPointFixed = false;
      isNavigationStarted = false;
      currentStepIndex = 0;
      _routeCreatedAnnounced = false;
      _announcedTurnSteps.clear();
      _hasAnnouncedDestinationReached = false;
    });

    final pos = await _getCurrentLocation();
    if (pos != null) {
      updateCurrentLocationMarker(pos);
    }
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
      final snapshot = FirebaseFirestore.instance.collection('markers').get();
      final docs = (await snapshot).docs;

      List<MapEntry<MarkerModel, double>> accessiblePoints = [];

      for (final doc in docs) {
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

              // Navigasyon başlatıldığında marker yerleştirmeyi devre dışı bırak
              if (isNavigationStarted) {
                _showMessage(
                  'Navigasyon sırasında yeni nokta eklenemez. Önce navigasyonu sonlandırın.',
                );
                return;
              }

              String? action = await showModalBottomSheet<String>(
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
                      children: [
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
                        Text('İşlem Seçin', style: AppTheme.headingSmall),
                        const SizedBox(height: 20),
                        _buildActionTile(
                          icon: Icons.gps_fixed,
                          title: 'Başlangıç Noktası Ekle',
                          color: AppTheme.primaryBlue,
                          onTap: () => Navigator.pop(context, 'start'),
                        ),
                        _buildActionTile(
                          icon: Icons.directions,
                          title: 'Hedef Nokta Ekle',
                          color: AppTheme.secondaryGreen,
                          onTap: () => Navigator.pop(context, 'target'),
                        ),
                        _buildActionTile(
                          icon: Icons.add_location_alt,
                          title: 'Erişim Noktası Ekle',
                          color: AppTheme.secondaryOrange,
                          onTap: () => Navigator.pop(context, 'marker'),
                        ),
                      ],
                    ),
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
                          Text(
                            'Erişim Noktası Türü Seçin',
                            style: AppTheme.headingSmall,
                          ),
                          const SizedBox(height: 20),
                          _buildMarkerTypeTile(
                            icon: Icons.accessible_forward,
                            title: 'Rampa',
                            color: Colors.green.shade700,
                            onTap: () => Navigator.pop(context, 'rampa'),
                          ),
                          _buildMarkerTypeTile(
                            icon: Icons.elevator,
                            title: 'Asansör',
                            color: Colors.orange.shade700,
                            onTap: () => Navigator.pop(context, 'asansör'),
                          ),
                          _buildMarkerTypeTile(
                            icon: Icons.directions_walk,
                            title: 'Yaya Geçidi',
                            color: Colors.blue.shade700,
                            onTap: () => Navigator.pop(context, 'yaya_gecidi'),
                          ),
                          _buildMarkerTypeTile(
                            icon: Icons.traffic,
                            title: 'Trafik Işığı',
                            color: Colors.red.shade700,
                            onTap: () => Navigator.pop(context, 'trafik_isigi'),
                          ),
                          _buildMarkerTypeTile(
                            icon: Icons.alt_route,
                            title: 'Üst/Alt Geçit',
                            color: Colors.purple.shade700,
                            onTap: () => Navigator.pop(context, 'ust_gecit'),
                          ),
                        ],
                      ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        title: Row(
                          children: [
                            Icon(
                              Icons.description,
                              color: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Açıklama Girin",
                              style: AppTheme.headingSmall,
                            ),
                          ],
                        ),
                        content: TextField(
                          controller: controller,
                          decoration: AppTheme.inputDecoration(
                            'Kısa açıklama (ör: Eğimli rampa, 5m genişlik)',
                            Icons.edit,
                          ),
                          maxLines: 3,
                          minLines: 1,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: Text(
                              "İptal",
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () =>
                                Navigator.pop(context, controller.text),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text("Ekle"),
                            style: AppTheme.primaryButtonStyle,
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
                  }
                }
              }
            },
          ),
          // Navigation Step Card (Top)
          if (isNavigationStarted && routePoints.isNotEmpty)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  decoration: AppTheme.cardDecoration.copyWith(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
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
                            Icons.navigation,
                            color: AppTheme.primaryBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Adım ${currentStepIndex + 1}/${navigationSteps.length}",
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (currentStepIndex < navigationSteps.length)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      navigationSteps[currentStepIndex]['direction']
                                          as String,
                                      style: AppTheme.bodyLarge.copyWith(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      navigationSteps[currentStepIndex]['reason']
                                          as String,
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  "Hedef noktaya ulaştınız!",
                                  style: AppTheme.bodyLarge.copyWith(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
                            if (currentStepIndex < navigationSteps.length - 1) {
                              setState(() {
                                currentStepIndex++;
                              });
                              await _announceCurrentStep();
                            }
                          },
                          icon: Icon(
                            Icons.skip_next,
                            color: AppTheme.primaryBlue,
                          ),
                          tooltip: 'Sonraki Adım',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // UI Overlay
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Route Info Card (only show when navigation is not started)
                  if (!isNavigationStarted &&
                      routeDistanceKm != null &&
                      routeDurationMin != null)
                    AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: AppTheme.cardDecoration.copyWith(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
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
                              Container(
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: startNavigation,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.play_arrow,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Başlat',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Navigation Control Buttons (only show when navigation is started)
                  if (isNavigationStarted)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.shade600,
                                    Colors.red.shade800,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: stopNavigation,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.stop,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Sonlandır',
                                          style: TextStyle(
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
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => RouteDetailsPage(
                                          navigationSteps: navigationSteps,
                                          routeWaypoints: routeWaypoints,
                                          routeDistanceKm: routeDistanceKm,
                                          routeDurationMin: routeDurationMin,
                                        ),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.list_alt,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Rota Detayı',
                                          style: TextStyle(
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
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Navigation Info Card (only show when navigation is started)
                  if (isNavigationStarted)
                    AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: AppTheme.cardDecoration.copyWith(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
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
                                  Icons.navigation,
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
                                      "Hedefe Kalan",
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.route,
                                          size: 16,
                                          color: AppTheme.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDistance(
                                            _calculateRemainingDistance(),
                                          ),
                                          style: AppTheme.bodyLarge.copyWith(
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Icon(
                                          Icons.timer,
                                          size: 16,
                                          color: AppTheme.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDuration(
                                            _calculateRemainingDuration(),
                                          ),
                                          style: AppTheme.bodyLarge.copyWith(
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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
                                  '${currentStepIndex + 1}/${navigationSteps.length}',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.primaryBlue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Marker Count Info (only show when navigation is not started)
                  if (!isNavigationStarted)
                    AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: AppTheme.cardDecorationLight.copyWith(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
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
                                    color: AppTheme.primaryBlue.withOpacity(
                                      0.1,
                                    ),
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
                    ),

                  // Filter Controls (only show when navigation is not started)
                  if (!isNavigationStarted)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: AppTheme.cardDecoration.copyWith(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
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

                  // Action Buttons (only show when navigation is not started)
                  if (!isNavigationStarted)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                                final pos = await _getCurrentLocation();
                                if (pos == null) {
                                  _showMessage('Konum alınamadı');
                                  return;
                                }

                                String? selectedType =
                                    await showModalBottomSheet<String>(
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
                                              Center(
                                                child: Container(
                                                  width: 40,
                                                  height: 4,
                                                  margin: const EdgeInsets.only(
                                                    bottom: 20,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.textLight,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                  ),
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
                                                color: Colors.green.shade700,
                                                onTap: () => Navigator.pop(
                                                  context,
                                                  'rampa',
                                                ),
                                              ),
                                              _buildMarkerTypeTile(
                                                icon: Icons.elevator,
                                                title: 'Asansör',
                                                color: Colors.orange.shade700,
                                                onTap: () => Navigator.pop(
                                                  context,
                                                  'asansör',
                                                ),
                                              ),
                                              _buildMarkerTypeTile(
                                                icon: Icons.directions_walk,
                                                title: 'Yaya Geçidi',
                                                color: Colors.blue.shade700,
                                                onTap: () => Navigator.pop(
                                                  context,
                                                  'yaya_gecidi',
                                                ),
                                              ),
                                              _buildMarkerTypeTile(
                                                icon: Icons.traffic,
                                                title: 'Trafik Işığı',
                                                color: Colors.red.shade700,
                                                onTap: () => Navigator.pop(
                                                  context,
                                                  'trafik_isigi',
                                                ),
                                              ),
                                              _buildMarkerTypeTile(
                                                icon: Icons.alt_route,
                                                title: 'Üst/Alt Geçit',
                                                color: Colors.purple.shade700,
                                                onTap: () => Navigator.pop(
                                                  context,
                                                  'ust_gecit',
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );

                                if (selectedType != null) {
                                  String?
                                  description = await showDialog<String>(
                                    context: context,
                                    builder: (context) {
                                      TextEditingController controller =
                                          TextEditingController();
                                      return AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        title: Row(
                                          children: [
                                            Icon(
                                              Icons.description,
                                              color: AppTheme.primaryBlue,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "Açıklama Girin",
                                              style: AppTheme.headingSmall,
                                            ),
                                          ],
                                        ),
                                        content: TextField(
                                          controller: controller,
                                          decoration: AppTheme.inputDecoration(
                                            'Kısa açıklama (ör: Eğimli rampa, 5m genişlik)',
                                            Icons.edit,
                                          ),
                                          maxLines: 3,
                                          minLines: 1,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, null),
                                            child: Text(
                                              "İptal",
                                              style: AppTheme.bodyMedium
                                                  .copyWith(
                                                    color:
                                                        AppTheme.textSecondary,
                                                  ),
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () => Navigator.pop(
                                              context,
                                              controller.text,
                                            ),
                                            icon: const Icon(
                                              Icons.add,
                                              size: 18,
                                            ),
                                            label: const Text("Ekle"),
                                            style: AppTheme.primaryButtonStyle,
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
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for improved UI

  Widget _buildMarkerTypeTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecorationLight.copyWith(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          title,
          style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: color, size: 18),
        onTap: onTap,
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecorationLight.copyWith(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          title,
          style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: color, size: 18),
        onTap: onTap,
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
              for (final symbol in _symbols.values.toList()) {
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
    print(
      '=== Bottom sheet açılıyor: ${marker.type}, ID: $docId ===',
    ); // Hata ayıklama için log

    // Mevcut konumu al (mesafe hesaplaması için)
    Future<String> _calculateDistanceText() async {
      if (startPoint == null) return 'Mesafe hesaplanamadı';
      final distance = Geolocator.distanceBetween(
        startPoint!.latitude,
        startPoint!.longitude,
        marker.latitude,
        marker.longitude,
      );
      return distance < 1000
          ? '${distance.toInt()} m'
          : '${(distance / 1000).toStringAsFixed(1)} km';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Şeffaf arka plan
      isScrollControlled: true, // Tam ekran kontrolü için
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6, // Başlangıç yüksekliği
          minChildSize: 0.3, // Minimum yükseklik
          maxChildSize: 0.9, // Maksimum yükseklik
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.backgroundWhite,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Çekme çubuğu
                      Center(
                        child: Container(
                          width: 50,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.textLight.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                      // Başlık ve İkon
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _getMarkerColor(marker.type).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getIcon(marker.type),
                              color: _getMarkerColor(marker.type),
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _typeToLabel(marker.type),
                                style: AppTheme.headingMedium.copyWith(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Açıklama
                      if (marker.description != null &&
                          marker.description!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            marker.description!,
                            style: AppTheme.bodyMedium.copyWith(
                              fontSize: 16,
                              color: AppTheme.textPrimary.withOpacity(0.9),
                            ),
                          ),
                        ),
                      if (marker.description == null ||
                          marker.description!.isEmpty)
                        Text(
                          'Açıklama yok',
                          style: AppTheme.bodyMedium.copyWith(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Konum ve Mesafe
                      FutureBuilder<String>(
                        future: _calculateDistanceText(),
                        builder: (context, snapshot) {
                          return Row(
                            children: [
                              Icon(
                                Icons.location_pin,
                                color: AppTheme.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Konum: ${marker.latitude.toStringAsFixed(6)}, ${marker.longitude.toStringAsFixed(6)}',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (snapshot.hasData)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withOpacity(
                                      0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    snapshot.data!,
                                    style: AppTheme.bodySmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // Eklenme Tarihi
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Eklenme: ${DateFormat('dd/MM/yyyy HH:mm').format(marker.createdAt ?? DateTime.now())}',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Beğeni ve Aksiyon Butonları
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.favorite,
                                color: Colors.red.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${marker.likes} Beğeni',
                                style: AppTheme.bodyMedium.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('markers')
                                      .doc(docId)
                                      .update({
                                        'likes': FieldValue.increment(1),
                                      });
                                  _showMessage('Beğeni eklendi!');
                                  Navigator.pop(
                                    context,
                                  ); // Beğendikten sonra kapat
                                },
                                icon: const Icon(
                                  Icons.favorite_border,
                                  size: 18,
                                ),
                                label: const Text('Beğen'),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: AppTheme.primaryBlue,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  // Paylaşım fonksiyonu (örneğin, link paylaşımı)
                                  _showMessage(
                                    'Paylaşım özelliği yakında eklenecek!',
                                  );
                                },
                                icon: const Icon(Icons.share, size: 24),
                                color: AppTheme.primaryBlue,
                                tooltip: 'Paylaş',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Rapor Et Butonu
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            // Rapor etme fonksiyonu (örneğin, bir dialog açılabilir)
                            _showMessage(
                              'Rapor etme özelliği yakında eklenecek!',
                            );
                          },
                          icon: const Icon(
                            Icons.report_problem_outlined,
                            size: 20,
                          ),
                          label: const Text('Sorun Bildir'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red.shade600,
                            textStyle: AppTheme.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      print('Bottom sheet kapandı'); // Hata ayıklama için log
    });
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

class RouteWaypoint {
  final LatLng location;
  final String type; // 'rampa', 'asansör', etc.
  final String direction; // 'sağ', 'sol', 'düz'
  final String reason; // Neden bu yön tercih edildi
  final double distanceFromStart;
  final double distanceToEnd; // Metre cinsinden

  RouteWaypoint({
    required this.location,
    required this.type,
    required this.direction,
    required this.reason,
    required this.distanceFromStart,
    required this.distanceToEnd,
  });
}
