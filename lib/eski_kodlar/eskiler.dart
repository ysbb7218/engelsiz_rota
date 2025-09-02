// // // import 'dart:async';
// // // import 'dart:math' as math;
// // // import 'package:engelsiz_rota/model/marker_model.dart';
// // // import 'package:flutter/material.dart';
// // // import 'package:flutter_map/flutter_map.dart';
// // // import 'package:latlong2/latlong.dart';
// // // import 'package:cloud_firestore/cloud_firestore.dart';
// // // import 'package:geolocator/geolocator.dart';
// // // import 'package:intl/intl.dart';
// // // import 'package:http/http.dart' as http;
// // // import 'dart:convert';
// // // import 'package:flutter_map_marker_cluster_plus/flutter_map_marker_cluster_plus.dart';
// // // import 'package:vector_map_tiles/vector_map_tiles.dart'; // Yeni paket ekleyin: vector_map_tiles

// // // class MapPage extends StatefulWidget {
// // //   const MapPage({super.key});

// // //   @override
// // //   State<MapPage> createState() => _MapPageState();
// // // }

// // // class _MapPageState extends State<MapPage> {
// // //   List<Marker> markers = [];
// // //   late final MapController _mapController = MapController();
// // //   LatLng? startPoint;
// // //   LatLng? endPoint;
// // //   List<LatLng> routePoints = [];
// // //   double? routeDistanceKm;
// // //   double? routeDurationMin;
// // //   String selectedFilter = 'hepsi';
// // //   String selectedProfile = 'foot-walking';
// // //   Timer? locationTimer;

// // //   Style? _style; // MapTiler stilini saklamak için

// // //   // Sadece marker konumunu güncelle (haritayı ortalamaz)
// // //   void updateCurrentLocationMarker(LatLng pos) {
// // //     setState(() {
// // //       startPoint = pos;
// // //     });
// // //   }

// // //   // Sadece marker'ı günceller
// // //   void updateLocationMarker(LatLng pos) {
// // //     setState(() {
// // //       startPoint = pos;
// // //     });
// // //   }

// // //   // Hem marker'ı hem de haritayı ortala
// // //   void centerOnCurrentLocation(LatLng pos) {
// // //     setState(() {
// // //       startPoint = pos;
// // //       _mapController.move(pos, 17);
// // //     });
// // //   }

// // //   Future<LatLng?> _getCurrentLocation() async {
// // //     try {
// // //       bool enabled = await Geolocator.isLocationServiceEnabled();
// // //       if (!enabled) {
// // //         _showMessage("Konum servisi kapalı");
// // //         return null;
// // //       }

// // //       LocationPermission permission = await Geolocator.checkPermission();
// // //       if (permission == LocationPermission.denied) {
// // //         permission = await Geolocator.requestPermission();
// // //         if (permission == LocationPermission.denied) {
// // //           _showMessage("Konum izni reddedildi");
// // //           return null;
// // //         }
// // //       }

// // //       if (permission == LocationPermission.deniedForever) {
// // //         _showMessage("Konum izni kalıcı olarak reddedildi");
// // //         return null;
// // //       }

// // //       final position = await Geolocator.getCurrentPosition(
// // //         desiredAccuracy: LocationAccuracy.high,
// // //         timeLimit: const Duration(seconds: 5),
// // //       );

// // //       return LatLng(position.latitude, position.longitude);
// // //     } catch (e) {
// // //       _showMessage("Konum alınamadı: $e");
// // //       return null;
// // //     }
// // //   }

// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     fetchMarkers();
// // //     _setInitialLocation();
// // //     _loadStyle(); // MapTiler stilini yükle

// // //     // 2 saniyede bir sadece marker güncelle
// // //     locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
// // //       final pos = await _getCurrentLocation();
// // //       if (pos != null) {
// // //         updateLocationMarker(pos); // Haritayı ortalamaz
// // //       }
// // //     });
// // //   }

// // //   @override
// // //   void dispose() {
// // //     locationTimer?.cancel();
// // //     super.dispose();
// // //   }

// // //   void currentLocationPoint(LatLng pos) {
// // //     setState(() {
// // //       startPoint = pos;
// // //       _mapController.move(pos, 17);
// // //     });
// // //   }

// // //   Future<void> _setInitialLocation() async {
// // //     final pos = await _getCurrentLocation();
// // //     if (pos != null) {
// // //       setState(() {
// // //         startPoint = pos;
// // //       });
// // //       _mapController.move(pos, 15.0);
// // //     }
// // //   }

// // //   // MapTiler stilini yükle
// // //   Future<void> _loadStyle() async {
// // //     try {
// // //       final style = await StyleReader(
// // //         uri:
// // //             'https://api.maptiler.com/maps/openstreetmap/style.json?key=RUlFyEFNM0RNo0FrC3ch', // JSON stil URL'si
// // //         // logger: const Logger.console(),
// // //       ).read();

// // //       setState(() {
// // //         _style = style;
// // //       });
// // //     } catch (e) {
// // //       _showMessage('Stil yüklenemedi: $e');
// // //     }
// // //   }

// // //   Future<void> fetchMarkers() async {
// // //     final snapshot = await FirebaseFirestore.instance
// // //         .collection('markers')
// // //         .orderBy('createdAt', descending: true)
// // //         .limit(50)
// // //         .get();

// // //     final newMarkers = snapshot.docs
// // //         .map((doc) {
// // //           final marker = MarkerModel.fromMap(doc.data());
// // //           if (selectedFilter != 'hepsi' && marker.type != selectedFilter) {
// // //             return null;
// // //           }
// // //           return Marker(
// // //             width: 45,
// // //             height: 45,
// // //             point: LatLng(marker.latitude, marker.longitude),
// // //             child: GestureDetector(
// // //               onTap: () {
// // //                 _showMarkerDetails(marker, doc.id);
// // //               },
// // //               child: Tooltip(
// // //                 message: '${_typeToLabel(marker.type)}\n${marker.description}',
// // //                 child: AnimatedScale(
// // //                   scale:
// // //                       (startPoint != null &&
// // //                           startPoint!.latitude == marker.latitude &&
// // //                           startPoint!.longitude == marker.longitude)
// // //                       ? 1.3 // seçiliyse büyüt
// // //                       : 1.0,
// // //                   duration: const Duration(milliseconds: 200),
// // //                   child: Container(
// // //                     decoration: BoxDecoration(
// // //                       color: Colors.white,
// // //                       shape: BoxShape.circle,
// // //                       boxShadow: [
// // //                         BoxShadow(
// // //                           color: Colors.black26,
// // //                           blurRadius: 4,
// // //                           offset: Offset(0, 2),
// // //                         ),
// // //                       ],
// // //                     ),
// // //                     padding: const EdgeInsets.all(4),
// // //                     child: Icon(
// // //                       _getIcon(marker.type),
// // //                       color: _getMarkerColor(marker.type),
// // //                       size: 28,
// // //                     ),
// // //                   ),
// // //                 ),
// // //               ),
// // //             ),
// // //           );
// // //         })
// // //         .whereType<Marker>()
// // //         .toList();

// // //     setState(() {
// // //       markers = newMarkers;
// // //     });
// // //   }

// // //   Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
// // //     const apiKey =
// // //         'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4MGE1MzhlMWIwNTRiOGZiOTE5YTg3M2NmYzQ3MzJjIiwiaCI6Im11cm11cjY0In0=';
// // //     final url =
// // //         'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

// // //     // Önce normal (kısa) rotayı hesapla
// // //     List<LatLng> initialRoutePoints = await _getInitialRoute(start, end);

// // //     // Kısa rotaya yakın erişilebilir waypoint'leri topla
// // //     List<LatLng> waypoints = await _getAccessibleWaypointsAlongRoute(
// // //       start,
// // //       end,
// // //       initialRoutePoints,
// // //     );

// // //     // Eğer waypoint yoksa ve profil wheelchair ise, rota bulunamadı
// // //     if (selectedProfile == 'wheelchair' && waypoints.isEmpty) {
// // //       _showMessage('Rota bulunamadı: Erişilebilir nokta yok');
// // //       return [];
// // //     }

// // //     try {
// // //       final response = await http.post(
// // //         Uri.parse(url),
// // //         headers: {'Authorization': apiKey, 'Content-Type': 'application/json'},
// // //         body: jsonEncode({
// // //           'coordinates': [
// // //             [start.longitude, start.latitude],
// // //             ...waypoints.map((wp) => [wp.longitude, wp.latitude]),
// // //             [end.longitude, end.latitude],
// // //           ],
// // //           'options': {
// // //             // Wheelchair profili için ekstra seçenekler ekleyebilirsin
// // //             if (selectedProfile == 'wheelchair')
// // //               'profile_params': {
// // //                 'restrictions': {'wheelchair': true},
// // //               },
// // //           },
// // //         }),
// // //       );

// // //       if (response.statusCode == 200) {
// // //         final data = jsonDecode(response.body);
// // //         final coords = data['features'][0]['geometry']['coordinates'] as List;
// // //         final props = data['features'][0]['properties']['summary'];
// // //         routeDistanceKm = props['distance'] / 1000;
// // //         routeDurationMin = props['duration'] / 60;
// // //         return coords.map((c) => LatLng(c[1], c[0])).toList();
// // //       } else {
// // //         throw Exception('Rota alınamadı: ${response.statusCode}');
// // //       }
// // //     } catch (e) {
// // //       _showMessage('Rota alınamadı: $e');
// // //       return [];
// // //     }
// // //   }

// // //   // Kısa rotayı hesapla (waypoint'siz)
// // //   Future<List<LatLng>> _getInitialRoute(LatLng start, LatLng end) async {
// // //     const apiKey =
// // //         'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4MGE1MzhlMWIwNTRiOGZiOTE5YTg3M2NmYzQ3MzJjIiwiaCI6Im11cm11cjY0In0=';
// // //     final url =
// // //         'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

// // //     try {
// // //       final response = await http.post(
// // //         Uri.parse(url),
// // //         headers: {'Authorization': apiKey, 'Content-Type': 'application/json'},
// // //         body: jsonEncode({
// // //           'coordinates': [
// // //             [start.longitude, start.latitude],
// // //             [end.longitude, end.latitude],
// // //           ],
// // //         }),
// // //       );

// // //       if (response.statusCode == 200) {
// // //         final data = jsonDecode(response.body);
// // //         final coords = data['features'][0]['geometry']['coordinates'] as List;
// // //         return coords.map((c) => LatLng(c[1], c[0])).toList();
// // //       } else {
// // //         return [];
// // //       }
// // //     } catch (e) {
// // //       return [];
// // //     }
// // //   }

// // //   // Kısa rotaya yakın waypoint'leri seç
// // //   Future<List<LatLng>> _getAccessibleWaypointsAlongRoute(
// // //     LatLng start,
// // //     LatLng end,
// // //     List<LatLng> initialRoute,
// // //   ) async {
// // //     // Tüm marker'ları al
// // //     final snapshot = await FirebaseFirestore.instance
// // //         .collection('markers')
// // //         .get();

// // //     final accessibleTypes = ['rampa', 'yaya_gecidi', 'asansör', 'ust_gecit'];

// // //     List<LatLng> potentialWaypoints = snapshot.docs
// // //         .map((doc) => MarkerModel.fromMap(doc.data()))
// // //         .where((m) => accessibleTypes.contains(m.type))
// // //         .map((m) => LatLng(m.latitude, m.longitude))
// // //         .toList();

// // //     // Rotaya yakın olanları filtrele (örneğin 50 metre buffer)
// // //     const double bufferDistance = 50.0; // metre

// // //     List<LatLng> filtered = potentialWaypoints.where((wp) {
// // //       // Waypoint'in rotadaki en yakın noktaya uzaklığını hesapla
// // //       double minDist = double.infinity;
// // //       for (var routePoint in initialRoute) {
// // //         double dist = Geolocator.distanceBetween(
// // //           wp.latitude,
// // //           wp.longitude,
// // //           routePoint.latitude,
// // //           routePoint.longitude,
// // //         );
// // //         if (dist < minDist) minDist = dist;
// // //       }
// // //       return minDist <= bufferDistance;
// // //     }).toList();

// // //     // Filtrelenen waypoint'leri başlangıçtan hedefe doğru sırala (start'tan uzaklığa göre)
// // //     filtered.sort((a, b) {
// // //       double distA = Geolocator.distanceBetween(
// // //         start.latitude,
// // //         start.longitude,
// // //         a.latitude,
// // //         a.longitude,
// // //       );
// // //       double distB = Geolocator.distanceBetween(
// // //         start.latitude,
// // //         start.longitude,
// // //         b.latitude,
// // //         b.longitude,
// // //       );
// // //       return distA.compareTo(distB);
// // //     });

// // //     // En fazla 5 waypoint seç (API limitleri için)
// // //     return filtered.take(5).toList();
// // //   }

// // //   Future<void> drawRoute() async {
// // //     if (startPoint == null || endPoint == null) return;

// // //     final points = await getRoute(startPoint!, endPoint!);
// // //     if (points.isNotEmpty) {
// // //       setState(() {
// // //         routePoints = points;
// // //       });
// // //     } else {
// // //       // Eğer rota boş döndüyse ve mesaj zaten gösterilmediyse göster
// // //       // (getRoute içinde zaten gösteriliyor ama ekstra kontrol)
// // //       if (routePoints.isEmpty) {
// // //         _showMessage('Rota bulunamadı');
// // //       }
// // //     }
// // //   }

// // //   void clearRoute() {
// // //     setState(() {
// // //       startPoint = null;
// // //       endPoint = null;
// // //       routePoints.clear();
// // //       routeDistanceKm = null;
// // //       routeDurationMin = null;
// // //     });
// // //   }

// // //   IconData _getIcon(String type) {
// // //     switch (type) {
// // //       case 'rampa':
// // //         return Icons.accessible_forward;
// // //       case 'asansör':
// // //         return Icons.elevator;
// // //       case 'yaya_gecidi':
// // //         return Icons.directions_walk;
// // //       case 'trafik_isigi':
// // //         return Icons.traffic;
// // //       case 'ust_gecit':
// // //         return Icons.alt_route;
// // //       default:
// // //         return Icons.location_on;
// // //     }
// // //   }

// // //   Color _getMarkerColor(String type) {
// // //     switch (type) {
// // //       case 'rampa':
// // //         return Colors.green;
// // //       case 'asansör':
// // //         return Colors.orange;
// // //       case 'yaya_gecidi':
// // //         return Colors.blue;
// // //       case 'trafik_isigi':
// // //         return Colors.red;
// // //       case 'ust_gecit':
// // //         return Colors.purple;
// // //       default:
// // //         return Colors.grey;
// // //     }
// // //   }

// // //   void _showMarkerDetails(MarkerModel marker, String docId) {
// // //     showModalBottomSheet(
// // //       context: context,
// // //       shape: const RoundedRectangleBorder(
// // //         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
// // //       ),
// // //       backgroundColor: const Color(0xFF1976D2),
// // //       builder: (context) {
// // //         return Padding(
// // //           padding: const EdgeInsets.all(20),
// // //           child: DefaultTextStyle(
// // //             style: const TextStyle(color: Colors.white),
// // //             child: Column(
// // //               mainAxisSize: MainAxisSize.min,
// // //               crossAxisAlignment: CrossAxisAlignment.start,
// // //               children: [
// // //                 Center(
// // //                   child: Container(
// // //                     width: 40,
// // //                     height: 4,
// // //                     margin: const EdgeInsets.only(bottom: 16),
// // //                     decoration: BoxDecoration(
// // //                       color: Colors.white54,
// // //                       borderRadius: BorderRadius.circular(2),
// // //                     ),
// // //                   ),
// // //                 ),
// // //                 Row(
// // //                   children: [
// // //                     const Icon(
// // //                       Icons.warning_amber_rounded,
// // //                       color: Colors.white,
// // //                     ),
// // //                     const SizedBox(width: 8),
// // //                     Text(
// // //                       _typeToLabel(marker.type),
// // //                       style: const TextStyle(
// // //                         fontSize: 20,
// // //                         fontWeight: FontWeight.bold,
// // //                       ),
// // //                     ),
// // //                   ],
// // //                 ),
// // //                 const SizedBox(height: 12),

// // //                 Row(
// // //                   crossAxisAlignment: CrossAxisAlignment.start,
// // //                   children: [
// // //                     const Icon(Icons.description, color: Colors.white),
// // //                     const SizedBox(width: 8),
// // //                     Expanded(
// // //                       child: Text(
// // //                         marker.description,
// // //                         style: const TextStyle(fontSize: 16),
// // //                       ),
// // //                     ),
// // //                   ],
// // //                 ),
// // //                 const SizedBox(height: 12),

// // //                 Row(
// // //                   children: [
// // //                     const Icon(Icons.location_on, color: Colors.white),
// // //                     const SizedBox(width: 8),
// // //                     Text(
// // //                       "${marker.latitude.toStringAsFixed(5)}, ${marker.longitude.toStringAsFixed(5)}",
// // //                       style: const TextStyle(fontSize: 16),
// // //                     ),
// // //                   ],
// // //                 ),
// // //                 if (marker.createdAt != null) ...[
// // //                   const SizedBox(height: 12),
// // //                   Row(
// // //                     children: [
// // //                       const Icon(Icons.access_time, color: Colors.white),
// // //                       const SizedBox(width: 8),
// // //                       Text(
// // //                         DateFormat(
// // //                           'dd.MM.yyyy HH:mm',
// // //                         ).format(marker.createdAt!),
// // //                         style: const TextStyle(fontSize: 16),
// // //                       ),
// // //                     ],
// // //                   ),
// // //                 ],

// // //                 const SizedBox(height: 24),
// // //                 Row(
// // //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                   children: [
// // //                     ElevatedButton.icon(
// // //                       onPressed: () async {
// // //                         await FirebaseFirestore.instance
// // //                             .collection('markers')
// // //                             .doc(docId)
// // //                             .update({'likes': marker.likes + 1});
// // //                         Navigator.pop(context);
// // //                         fetchMarkers();
// // //                       },
// // //                       icon: const Icon(Icons.thumb_up),
// // //                       label: const Text('Faydalı'),
// // //                       style: ElevatedButton.styleFrom(
// // //                         backgroundColor: Colors.green[400],
// // //                         foregroundColor: Colors.white,
// // //                       ),
// // //                     ),
// // //                     Text(
// // //                       "${marker.likes} kişi faydalı buldu",
// // //                       style: const TextStyle(
// // //                         fontStyle: FontStyle.italic,
// // //                         fontSize: 14,
// // //                       ),
// // //                     ),
// // //                   ],
// // //                 ),
// // //               ],
// // //             ),
// // //           ),
// // //         );
// // //       },
// // //     );
// // //   }

// // //   String _typeToLabel(String type) {
// // //     switch (type) {
// // //       case 'rampa':
// // //         return 'Rampa';
// // //       case 'asansör':
// // //         return 'Asansör';
// // //       case 'yaya_gecidi':
// // //         return 'Yaya Geçidi';
// // //       case 'trafik_isigi':
// // //         return 'Trafik Işığı';
// // //       case 'ust_gecit':
// // //         return 'Üst/Alt Geçit';
// // //       default:
// // //         return type;
// // //     }
// // //   }

// // //   void _showMessage(String msg) {
// // //     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
// // //   }

// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return Scaffold(
// // //       appBar: AppBar(
// // //         title: const Text(
// // //           "Harita",
// // //           style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
// // //         ),
// // //         backgroundColor: const Color(0xFF1976D2),
// // //         elevation: 4,
// // //         actions: [
// // //           IconButton(
// // //             icon: const Icon(Icons.refresh),
// // //             onPressed: clearRoute,
// // //             tooltip: 'Rota Sıfırla',
// // //           ),
// // //         ],
// // //       ),
// // //       body: Container(
// // //         color: Colors.white,
// // //         child: Column(
// // //           children: [
// // //             // Filtre ve Profil Seçimi için üst bar
// // //             Padding(
// // //               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
// // //               child: Row(
// // //                 children: [
// // //                   Expanded(
// // //                     child: Card(
// // //                       color: const Color(0xFF1976D2),
// // //                       elevation: 2,
// // //                       shape: RoundedRectangleBorder(
// // //                         borderRadius: BorderRadius.circular(16),
// // //                       ),
// // //                       child: Padding(
// // //                         padding: const EdgeInsets.symmetric(
// // //                           horizontal: 12,
// // //                           vertical: 4,
// // //                         ),
// // //                         child: DropdownButtonHideUnderline(
// // //                           child: DropdownButton<String>(
// // //                             value: selectedFilter,
// // //                             dropdownColor: const Color(0xFF1976D2),
// // //                             iconEnabledColor: Colors.white,
// // //                             style: const TextStyle(
// // //                               color: Colors.white,
// // //                               fontWeight: FontWeight.bold,
// // //                             ),
// // //                             items: const [
// // //                               DropdownMenuItem(
// // //                                 value: 'hepsi',
// // //                                 child: Text('Hepsi'),
// // //                               ),
// // //                               DropdownMenuItem(
// // //                                 value: 'rampa',
// // //                                 child: Text('Rampa'),
// // //                               ),
// // //                               DropdownMenuItem(
// // //                                 value: 'asansör',
// // //                                 child: Text('Asansör'),
// // //                               ),
// // //                               DropdownMenuItem(
// // //                                 value: 'yaya_gecidi',
// // //                                 child: Text('Yaya Geçidi'),
// // //                               ),
// // //                               DropdownMenuItem(
// // //                                 value: 'trafik_isigi',
// // //                                 child: Text('Trafik Işığı'),
// // //                               ),
// // //                               DropdownMenuItem(
// // //                                 value: 'ust_gecit',
// // //                                 child: Text('Üst/Alt Geçit'),
// // //                               ),
// // //                             ],
// // //                             onChanged: (value) {
// // //                               setState(() {
// // //                                 selectedFilter = value!;
// // //                               });
// // //                               fetchMarkers();
// // //                             },
// // //                           ),
// // //                         ),
// // //                       ),
// // //                     ),
// // //                   ),
// // //                   const SizedBox(width: 12),
// // //                   Expanded(
// // //                     child: Card(
// // //                       color: const Color(0xFF64B5F6),
// // //                       elevation: 2,
// // //                       shape: RoundedRectangleBorder(
// // //                         borderRadius: BorderRadius.circular(16),
// // //                       ),
// // //                       child: Padding(
// // //                         padding: const EdgeInsets.symmetric(
// // //                           horizontal: 12,
// // //                           vertical: 4,
// // //                         ),
// // //                         child: DropdownButtonHideUnderline(
// // //                           child: DropdownButton<String>(
// // //                             value: selectedProfile,
// // //                             isExpanded: true,
// // //                             dropdownColor: const Color(0xFF64B5F6),
// // //                             iconEnabledColor: Colors.white,
// // //                             style: const TextStyle(
// // //                               color: Colors.white,
// // //                               fontWeight: FontWeight.bold,
// // //                             ),
// // //                             items: const [
// // //                               DropdownMenuItem(
// // //                                 value: 'foot-walking',
// // //                                 child: Text('Yürüyüş'),
// // //                               ),
// // //                               DropdownMenuItem(
// // //                                 value: 'wheelchair',
// // //                                 child: Text('Tekerlekli Sandalye'),
// // //                               ),
// // //                             ],
// // //                             onChanged: (value) {
// // //                               setState(() => selectedProfile = value!);
// // //                               if (startPoint != null && endPoint != null) {
// // //                                 drawRoute();
// // //                               }
// // //                             },
// // //                           ),
// // //                         ),
// // //                       ),
// // //                     ),
// // //                   ),
// // //                 ],
// // //               ),
// // //             ),
// // //             // Rota Bilgisi Kartı
// // //             if (routeDistanceKm != null && routeDurationMin != null)
// // //               Padding(
// // //                 padding: const EdgeInsets.symmetric(
// // //                   horizontal: 16,
// // //                   vertical: 4,
// // //                 ),
// // //                 child: Card(
// // //                   color: const Color(0xFF1976D2),
// // //                   elevation: 2,
// // //                   shape: RoundedRectangleBorder(
// // //                     borderRadius: BorderRadius.circular(16),
// // //                   ),
// // //                   child: Padding(
// // //                     padding: const EdgeInsets.all(12.0),
// // //                     child: Row(
// // //                       children: [
// // //                         const Icon(Icons.directions, color: Colors.white),
// // //                         const SizedBox(width: 12),
// // //                         Text(
// // //                           "Mesafe: ${routeDistanceKm!.toStringAsFixed(2)} km | Süre: ${routeDurationMin!.toStringAsFixed(0)} dk",
// // //                           style: const TextStyle(
// // //                             color: Colors.white,
// // //                             fontWeight: FontWeight.bold,
// // //                             fontSize: 16,
// // //                           ),
// // //                         ),
// // //                       ],
// // //                     ),
// // //                   ),
// // //                 ),
// // //               ),
// // //             // Harita
// // //             Expanded(
// // //               child: Card(
// // //                 margin: const EdgeInsets.all(16),
// // //                 elevation: 6,
// // //                 shape: RoundedRectangleBorder(
// // //                   borderRadius: BorderRadius.circular(24),
// // //                 ),
// // //                 clipBehavior: Clip.antiAlias,
// // //                 child: _style == null
// // //                     ? const Center(
// // //                         child: CircularProgressIndicator(),
// // //                       ) // Stil yüklenirken göster
// // //                     : FlutterMap(
// // //                         mapController: _mapController,
// // //                         options: MapOptions(
// // //                           initialCenter: LatLng(38.7569, 30.5387),
// // //                           initialZoom: 15,
// // //                           onLongPress: (tap, latlng) {
// // //                             setState(() {
// // //                               endPoint = latlng;
// // //                             });
// // //                             drawRoute();
// // //                           },
// // //                         ),
// // //                         children: [
// // //                           VectorTileLayer(
// // //                             theme: _style!.theme,
// // //                             sprites: _style!.sprites,
// // //                             tileProviders: _style!.providers,
// // //                           ),
// // //                           PolylineLayer(
// // //                             polylines: routePoints.isNotEmpty
// // //                                 ? [
// // //                                     Polyline<Object>(
// // //                                       points: routePoints,
// // //                                       color: Colors.deepPurple,
// // //                                       strokeWidth: 5,
// // //                                     ),
// // //                                   ]
// // //                                 : <Polyline<Object>>[],
// // //                           ),
// // //                           MarkerClusterLayerWidget(
// // //                             options: MarkerClusterLayerOptions(
// // //                               maxClusterRadius: 45,
// // //                               size: const Size(40, 40),
// // //                               alignment: Alignment.center,
// // //                               padding: const EdgeInsets.all(
// // //                                 50,
// // //                               ), // <-- burası (fitBoundsOptions yerine)
// // //                               maxZoom: 15,
// // //                               markers: [
// // //                                 ...markers,
// // //                                 if (startPoint != null)
// // //                                   Marker(
// // //                                     point: startPoint!,
// // //                                     width: 40,
// // //                                     height: 40,
// // //                                     child: const Icon(
// // //                                       Icons.navigation_outlined,
// // //                                       color: Colors.green,
// // //                                       size: 36,
// // //                                     ),
// // //                                   ),
// // //                                 if (endPoint != null)
// // //                                   Marker(
// // //                                     point: endPoint!,
// // //                                     width: 40,
// // //                                     height: 40,
// // //                                     child: const Icon(
// // //                                       Icons.location_pin,
// // //                                       color: Colors.red,
// // //                                       size: 36,
// // //                                     ),
// // //                                   ),
// // //                               ],
// // //                               builder: (context, cluster) {
// // //                                 return Container(
// // //                                   decoration: BoxDecoration(
// // //                                     color: Colors.blue[800],
// // //                                     shape: BoxShape.circle,
// // //                                   ),
// // //                                   alignment: Alignment.center,
// // //                                   child: Text(
// // //                                     cluster.length.toString(),
// // //                                     style: const TextStyle(
// // //                                       color: Colors.white,
// // //                                       fontWeight: FontWeight.bold,
// // //                                     ),
// // //                                   ),
// // //                                 );
// // //                               },
// // //                             ),
// // //                           ),
// // //                         ],
// // //                       ),
// // //               ),
// // //             ),
// // //           ],
// // //         ),
// // //       ),
// // //       // ...existing code...
// // //       floatingActionButton: Column(
// // //         mainAxisSize: MainAxisSize.min,
// // //         crossAxisAlignment: CrossAxisAlignment.end,
// // //         children: [
// // //           FloatingActionButton(
// // //             heroTag: 'konum',
// // //             onPressed: () async {
// // //               final pos = await _getCurrentLocation();
// // //               if (pos != null) {
// // //                 setState(() {
// // //                   startPoint = pos;
// // //                   _mapController.move(pos, 17); // Haritayı ortala
// // //                 });
// // //               }
// // //             },
// // //             backgroundColor: const Color(0xFF64B5F6),
// // //             child: const Icon(Icons.my_location),
// // //             tooltip: "Konumuma Git",
// // //           ),

// // //           const SizedBox(height: 12),
// // //           FloatingActionButton(
// // //             heroTag: 'markerEkle',
// // //             onPressed: () async {
// // //               String? selectedType = await showModalBottomSheet<String>(
// // //                 context: context,
// // //                 builder: (context) {
// // //                   return Column(
// // //                     mainAxisSize: MainAxisSize.min,
// // //                     children: [
// // //                       ListTile(
// // //                         leading: Icon(Icons.accessible_forward),
// // //                         title: Text('Rampa'),
// // //                         onTap: () => Navigator.pop(context, 'rampa'),
// // //                       ),
// // //                       ListTile(
// // //                         leading: Icon(Icons.elevator),
// // //                         title: Text('Asansör'),
// // //                         onTap: () => Navigator.pop(context, 'asansör'),
// // //                       ),
// // //                       ListTile(
// // //                         leading: Icon(Icons.directions_walk),
// // //                         title: Text('Yaya Geçidi'),
// // //                         onTap: () => Navigator.pop(context, 'yaya_gecidi'),
// // //                       ),
// // //                       ListTile(
// // //                         leading: Icon(Icons.traffic),
// // //                         title: Text('Trafik Işığı'),
// // //                         onTap: () => Navigator.pop(context, 'trafik_isigi'),
// // //                       ),
// // //                       ListTile(
// // //                         leading: Icon(Icons.alt_route),
// // //                         title: Text('Üst/Alt Geçit'),
// // //                         onTap: () => Navigator.pop(context, 'ust_gecit'),
// // //                       ),
// // //                     ],
// // //                   );
// // //                 },
// // //               );
// // //               if (selectedType != null) {
// // //                 final pos = await _getCurrentLocation();
// // //                 if (pos != null) {
// // //                   // Açıklama almak için dialog
// // //                   String? description = await showDialog<String>(
// // //                     context: context,
// // //                     builder: (context) {
// // //                       TextEditingController controller =
// // //                           TextEditingController();
// // //                       return AlertDialog(
// // //                         title: Text("Açıklama Girin"),
// // //                         content: TextField(
// // //                           controller: controller,
// // //                           decoration: InputDecoration(
// // //                             hintText: "Kısa açıklama",
// // //                           ),
// // //                         ),
// // //                         actions: [
// // //                           TextButton(
// // //                             onPressed: () => Navigator.pop(context, null),
// // //                             child: Text("İptal"),
// // //                           ),
// // //                           TextButton(
// // //                             onPressed: () =>
// // //                                 Navigator.pop(context, controller.text),
// // //                             child: Text("Ekle"),
// // //                           ),
// // //                         ],
// // //                       );
// // //                     },
// // //                   );
// // //                   if (description != null && description.isNotEmpty) {
// // //                     // Firestore'a ekle
// // //                     await FirebaseFirestore.instance
// // //                         .collection('markers')
// // //                         .add(
// // //                           MarkerModel(
// // //                             type: selectedType,
// // //                             latitude: pos.latitude,
// // //                             longitude: pos.longitude,
// // //                             description: description,
// // //                             likes: 0,
// // //                             createdAt: DateTime.now(),
// // //                           ).toMap(),
// // //                         );
// // //                     fetchMarkers();
// // //                     _showMessage("Engel başarıyla eklendi!");
// // //                   }
// // //                 }
// // //               }
// // //             },
// // //             backgroundColor: Colors.green,
// // //             child: const Icon(Icons.add_location_alt),
// // //             tooltip: "Engel/Marker Ekle",
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // // }

// // // maplibre_map_page.dart
// // // Flutter example using maplibre_gl + MapTiler style JSON + Firestore markers + polyline (route)

// // /*
// //   - Add these to pubspec.yaml:
// //     maplibre_gl: ^0.14.0
// //     firebase_core: ^2.10.0
// //     cloud_firestore: ^4.8.0
// //     geolocator: ^9.0.2

// //   - Enable Google/MapTiler keys and Firebase initialization in your app (main.dart)
// //   - Replace MAPTILER_KEY with your key or pass it from secure storage
// // */

// // import 'dart:async';

// // import 'package:cloud_firestore/cloud_firestore.dart';
// // import 'package:flutter/material.dart';
// // import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
// // // import 'package:maplibre_gl/mapbox_gl.dart' as maplibre;

// // class MapPage extends StatefulWidget {
// //   const MapPage({super.key});

// //   @override
// //   State<MapPage> createState() => _MapPageState();
// // }

// // class _MapPageState extends State<MapPage> {
// //   static const String _mapTilerKey =
// //       'RUlFyEFNM0RNo0FrC3ch'; // replace or inject securely
// //   final String _styleUrl =
// //       'https://api.maptiler.com/maps/openstreetmap/style.json?key=${_mapTilerKey}';

// //   maplibre.MaplibreMapController? _controller;
// //   StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _markerSub;

// //   // Keep track of created symbol and line ids to update/remove them
// //   final Map<String, maplibre.Symbol> _symbols = {}; // docId -> Symbol
// //   maplibre.Line? _routeLine;

// //   @override
// //   void initState() {
// //     super.initState();
// //     _listenFirestoreMarkers();
// //   }

// //   @override
// //   void dispose() {
// //     _markerSub?.cancel();
// //     _controller?.dispose();
// //     super.dispose();
// //   }

// //   void _onMapCreated(maplibre.MaplibreMapController controller) {
// //     _controller = controller;
// //     // Optional: set debug options or gesture settings here
// //   }

// //   void _onStyleLoaded() async {
// //     // Called when the style JSON and tiles are loaded. Useful to add layers/sources if needed.
// //     // If there are already cached markers, add them now (stream listener will handle realtime updates).
// //   }

// //   void _listenFirestoreMarkers() {
// //     final coll = FirebaseFirestore.instance.collection('markers');
// //     _markerSub = coll.snapshots().listen((snap) async {
// //       if (_controller == null) return; // wait until map ready

// //       // Handle removed docs
// //       final currentIds = snap.docs.map((d) => d.id).toSet();
// //       final knownIds = _symbols.keys.toSet();

// //       for (final removedId in knownIds.difference(currentIds)) {
// //         final sym = _symbols.remove(removedId);
// //         if (sym != null) {
// //           try {
// //             await _controller!.removeSymbol(sym);
// //           } catch (_) {}
// //         }
// //       }

// //       // Upsert markers from snapshot
// //       for (final doc in snap.docs) {
// //         final data = doc.data();
// //         final lat = (data['lat'] is num)
// //             ? (data['lat'] as num).toDouble()
// //             : null;
// //         final lng = (data['lng'] is num)
// //             ? (data['lng'] as num).toDouble()
// //             : null;
// //         final title = (data['title'] as String?) ?? '';

// //         if (lat == null || lng == null) continue;

// //         final docId = doc.id;

// //         if (_symbols.containsKey(docId)) {
// //           // update symbol position / data
// //           final existing = _symbols[docId]!;
// //           await _controller!.updateSymbol(
// //             existing,
// //             maplibre.SymbolOptions(
// //               geometry: maplibre.LatLng(lat, lng),
// //               // you can update iconSize/title etc here if needed
// //             ),
// //           );
// //         } else {
// //           // add new symbol
// //           final symbol = await _controller!.addSymbol(
// //             maplibre.SymbolOptions(
// //               geometry: maplibre.LatLng(lat, lng),
// //               iconSize: 1.6,
// //               iconImage:
// //                   'marker-15', // built-in sprite name; you can add custom images to style
// //               textField: title,
// //               textOffset: const Offset(0, 1.5),
// //             ),
// //           );
// //           _symbols[docId] = symbol;
// //         }
// //       }
// //     });
// //   }

// //   /// Draw a route polyline on the map.
// //   /// `route` is a list of LatLng pairs: [LatLng( ), LatLng( ), ...]
// //   Future<void> drawRoute(List<maplibre.LatLng> route) async {
// //     if (_controller == null) return;

// //     // remove previous line if exists
// //     if (_routeLine != null) {
// //       try {
// //         await _controller!.removeLine(_routeLine!);
// //       } catch (_) {}
// //       _routeLine = null;
// //     }

// //     if (route.length < 2) return;

// //     final line = await _controller!.addLine(
// //       maplibre.LineOptions(
// //         geometry: route,
// //         lineWidth: 4.0,
// //         lineColor: '#ff0000',
// //         lineOpacity: 0.9,
// //       ),
// //     );

// //     _routeLine = line;

// //     // Optional: move camera to fit the route
// //     final bounds = _boundsFromLatLngList(route);
// //     if (bounds != null) {
// //       await _controller!.animateCamera(
// //         maplibre.CameraUpdate.newLatLngBounds(
// //           bounds,
// //           left: 40,
// //           top: 40,
// //           right: 40,
// //           bottom: 40,
// //         ),
// //       );
// //     }
// //   }

// //   maplibre.LatLngBounds? _boundsFromLatLngList(List<maplibre.LatLng> coords) {
// //     if (coords.isEmpty) return null;
// //     double minLat = coords.first.latitude, maxLat = coords.first.latitude;
// //     double minLng = coords.first.longitude, maxLng = coords.first.longitude;
// //     for (final c in coords) {
// //       if (c.latitude < minLat) minLat = c.latitude;
// //       if (c.latitude > maxLat) maxLat = c.latitude;
// //       if (c.longitude < minLng) minLng = c.longitude;
// //       if (c.longitude > maxLng) maxLng = c.longitude;
// //     }
// //     return maplibre.LatLngBounds(
// //       southwest: maplibre.LatLng(minLat, minLng),
// //       northeast: maplibre.LatLng(maxLat, maxLng),
// //     );
// //   }

// //   // Example helper to convert a list of simple maps (e.g. from your D* output) to maplibre.LatLng
// //   List<maplibre.LatLng> _convertRoute(List<Map<String, dynamic>> routePoints) {
// //     return routePoints.map((p) {
// //       final lat = (p['lat'] as num).toDouble();
// //       final lng = (p['lng'] as num).toDouble();
// //       return maplibre.LatLng(lat, lng);
// //     }).toList();
// //   }

// //   // Example test route - you would replace this with your D* output
// //   final List<maplibre.LatLng> _testRoute = const [
// //     maplibre.LatLng(20.38884, 16.44338),
// //     maplibre.LatLng(20.5, 16.5),
// //     maplibre.LatLng(20.7, 16.7),
// //   ];

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(title: const Text('MapLibre + MapTiler')),
// //       body: Stack(
// //         children: [
// //           maplibre.MaplibreMap(
// //             styleString: _styleUrl,
// //             initialCameraPosition: const maplibre.CameraPosition(
// //               target: maplibre.LatLng(20.38884, 16.44338),
// //               zoom: 5.0,
// //             ),
// //             onMapCreated: _onMapCreated,
// //             onStyleLoadedCallback: _onStyleLoaded,
// //             myLocationEnabled: false,
// //             rotateGesturesEnabled: true,
// //             tiltGesturesEnabled: true,
// //           ),

// //           // Floating buttons for quick actions (add test route / clear)
// //           Positioned(
// //             right: 12,
// //             top: 12,
// //             child: Column(
// //               children: [
// //                 FloatingActionButton.small(
// //                   heroTag: 'route',
// //                   onPressed: () async {
// //                     await drawRoute(_testRoute);
// //                   },
// //                   child: const Icon(Icons.alt_route),
// //                 ),
// //                 const SizedBox(height: 8),
// //                 FloatingActionButton.small(
// //                   heroTag: 'clear',
// //                   onPressed: () async {
// //                     if (_routeLine != null) {
// //                       try {
// //                         await _controller?.removeLine(_routeLine!);
// //                       } catch (_) {}
// //                       _routeLine = null;
// //                     }
// //                   },
// //                   child: const Icon(Icons.clear),
// //                 ),
// //               ],
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }

//   static const String _mapTilerKey = 'RUlFyEFNM0RNo0FrC3ch';
//   final String _styleUrl =
//       'https://api.maptiler.com/maps/openstreetmap/style.json?key=$_mapTilerKey';

//   maplibre.MaplibreMapController? _controller;
//   StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _markerSub;
//   Timer? locationTimer;

//   // Store symbols and route line
//   final Map<String, maplibre.Symbol> _symbols = {};
//   maplibre.Symbol? _currentLocationSymbol;
//   maplibre.Symbol? _endPointSymbol;
//   maplibre.Line? _routeLine;

//   LatLng? startPoint;
//   LatLng? endPoint;
//   List<LatLng> routePoints = [];
//   double? routeDistanceKm;
//   double? routeDurationMin;
//   String selectedFilter = 'hepsi';
//   String selectedProfile = 'foot-walking';

//   @override
//   void initState() {
//     super.initState();
//     _listenFirestoreMarkers();
//     _setInitialLocation();

//     // Update current location every 2 seconds
//     locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
//       final pos = await _getCurrentLocation();
//       if (pos != null) {
//         updateCurrentLocationMarker(pos);
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _markerSub?.cancel();
//     locationTimer?.cancel();
//     _controller?.dispose();
//     super.dispose();
//   }

//   void _onMapCreated(maplibre.MaplibreMapController controller) {
//     _controller = controller;
//   }

//   void _onStyleLoaded() async {
//     // Called when the style JSON and tiles are loaded
//   }

//   Future<LatLng?> _getCurrentLocation() async {
//     try {
//       bool enabled = await Geolocator.isLocationServiceEnabled();
//       if (!enabled) {
//         _showMessage("Konum servisi kapalı");
//         return null;
//       }

//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//         if (permission == LocationPermission.denied) {
//           _showMessage("Konum izni reddedildi");
//           return null;
//         }
//       }

//       if (permission == LocationPermission.deniedForever) {
//         _showMessage("Konum izni kalıcı olarak reddedildi");
//         return null;
//       }

//       final position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//         timeLimit: const Duration(seconds: 5),
//       );

//       return LatLng(position.latitude, position.longitude);
//     } catch (e) {
//       _showMessage("Konum alınamadı: $e");
//       return null;
//     }
//   }

//   void updateCurrentLocationMarker(LatLng pos) async {
//     setState(() {
//       startPoint = pos;
//     });

//     if (_controller == null) return;

//     if (_currentLocationSymbol != null) {
//       await _controller!.updateSymbol(
//         _currentLocationSymbol!,
//         maplibre.SymbolOptions(
//           geometry: maplibre.LatLng(pos.latitude, pos.longitude),
//         ),
//       );
//     } else {
//       final symbol = await _controller!.addSymbol(
//         maplibre.SymbolOptions(
//           geometry: maplibre.LatLng(pos.latitude, pos.longitude),
//           iconImage: 'marker-15',
//           iconSize: 1.6,
//           textField: 'Konumum',
//           textOffset: const Offset(0, 1.5),
//           iconColor: '#00FF00',
//         ),
//       );
//       _currentLocationSymbol = symbol;
//     }
//   }

//   void centerOnCurrentLocation(LatLng pos) async {
//     setState(() {
//       startPoint = pos;
//     });

//     if (_controller != null) {
//       await _controller!.animateCamera(
//         maplibre.CameraUpdate.newLatLngZoom(
//           maplibre.LatLng(pos.latitude, pos.longitude),
//           17,
//         ),
//       );
//       updateCurrentLocationMarker(pos);
//     }
//   }

//   Future<void> _setInitialLocation() async {
//     final pos = await _getCurrentLocation();
//     if (pos != null && _controller != null) {
//       setState(() {
//         startPoint = pos;
//       });
//       await _controller!.animateCamera(
//         maplibre.CameraUpdate.newLatLngZoom(
//           maplibre.LatLng(pos.latitude, pos.longitude),
//           15,
//         ),
//       );
//       updateCurrentLocationMarker(pos);
//     }
//   }

//   void _listenFirestoreMarkers() {
//     final coll = FirebaseFirestore.instance
//         .collection('markers')
//         .orderBy('createdAt', descending: true)
//         .limit(50);

//     _markerSub = coll.snapshots().listen((snap) async {
//       if (_controller == null) return;

//       final currentIds = snap.docs.map((d) => d.id).toSet();
//       final knownIds = _symbols.keys.toSet();

//       for (final removedId in knownIds.difference(currentIds)) {
//         final sym = _symbols.remove(removedId);
//         if (sym != null) {
//           try {
//             await _controller!.removeSymbol(sym);
//           } catch (_) {}
//         }
//       }

//       for (final doc in snap.docs) {
//         final marker = MarkerModel.fromMap(doc.data());
//         if (selectedFilter != 'hepsi' && marker.type != selectedFilter) {
//           continue;
//         }

//         final lat = marker.latitude;
//         final lng = marker.longitude;
//         final docId = doc.id;

//         if (_symbols.containsKey(docId)) {
//           await _controller!.updateSymbol(
//             _symbols[docId]!,
//             maplibre.SymbolOptions(
//               geometry: maplibre.LatLng(lat, lng),
//               textField: _typeToLabel(marker.type),
//             ),
//           );
//         } else {
//           final symbol = await _controller!.addSymbol(
//             maplibre.SymbolOptions(
//               geometry: maplibre.LatLng(lat, lng),
//               iconImage: 'marker-15',
//               iconSize: 1.6,
//               textField: _typeToLabel(marker.type),
//               textOffset: const Offset(0, 1.5),
//               iconColor: _getMarkerColor(marker.type).value.toRadixString(16),
//             ),
//           );
//           _symbols[docId] = symbol;

//           _controller!.onSymbolTapped.add((symbol) {
//             if (symbol == _symbols[docId]) {
//               _showMarkerDetails(marker, docId);
//             }
//           });
//         }
//       }
//     });
//   }

//   Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
//     const apiKey =
//         'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4MGE1MzhlMWIwNTRiOGZiOTE5YTg3M2NmYzQ3MzJjIiwiaCI6Im11cm11cjY0In0=';
//     final url =
//         'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

//     List<LatLng> initialRoutePoints = await _getInitialRoute(start, end);

//     List<LatLng> waypoints = await _getAccessibleWaypointsAlongRoute(
//       start,
//       end,
//       initialRoutePoints,
//     );

//     if (selectedProfile == 'wheelchair' && waypoints.isEmpty) {
//       _showMessage('Rota bulunamadı: Erişilebilir nokta yok');
//       return [];
//     }

//     try {
//       final response = await http.post(
//         Uri.parse(url),
//         headers: {'Authorization': apiKey, 'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'coordinates': [
//             [start.longitude, start.latitude],
//             ...waypoints.map((wp) => [wp.longitude, wp.latitude]),
//             [end.longitude, end.latitude],
//           ],
//           'options': {
//             if (selectedProfile == 'wheelchair')
//               'profile_params': {
//                 'restrictions': {'wheelchair': true},
//               },
//           },
//         }),
//       );

//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         final coords = data['features'][0]['geometry']['coordinates'] as List;
//         final props = data['features'][0]['properties']['summary'];
//         setState(() {
//           routeDistanceKm = props['distance'] / 1000;
//           routeDurationMin = props['duration'] / 60;
//         });
//         return coords.map((c) => LatLng(c[1], c[0])).toList();
//       } else {
//         throw Exception('Rota alınamadı: ${response.statusCode}');
//       }
//     } catch (e) {
//       _showMessage('Rota alınamadı: $e');
//       return [];
//     }
//   }

//   Future<List<LatLng>> _getInitialRoute(LatLng start, LatLng end) async {
//     const apiKey =
//         'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4MGE1MzhlMWIwNTRiOGZiOTE5YTg3M2NmYzQ3MzJjIiwiaCI6Im11cm11cjY0In0=';
//     final url =
//         'https://api.openrouteservice.org/v2/directions/$selectedProfile/geojson';

//     try {
//       final response = await http.post(
//         Uri.parse(url),
//         headers: {'Authorization': apiKey, 'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'coordinates': [
//             [start.longitude, start.latitude],
//             [end.longitude, end.latitude],
//           ],
//         }),
//       );

//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         final coords = data['features'][0]['geometry']['coordinates'] as List;
//         return coords.map((c) => LatLng(c[1], c[0])).toList();
//       } else {
//         return [];
//       }
//     } catch (e) {
//       return [];
//     }
//   }

//   Future<List<LatLng>> _getAccessibleWaypointsAlongRoute(
//     LatLng start,
//     LatLng end,
//     List<LatLng> initialRoute,
//   ) async {
//     final snapshot = await FirebaseFirestore.instance
//         .collection('markers')
//         .get();

//     final accessibleTypes = ['rampa', 'yaya_gecidi', 'asansör', 'ust_gecit'];

//     List<LatLng> potentialWaypoints = snapshot.docs
//         .map((doc) => MarkerModel.fromMap(doc.data()))
//         .where((m) => accessibleTypes.contains(m.type))
//         .map((m) => LatLng(m.latitude, m.longitude))
//         .toList();

//     const double bufferDistance = 50.0;

//     List<LatLng> filtered = potentialWaypoints.where((wp) {
//       double minDist = double.infinity;
//       for (var routePoint in initialRoute) {
//         double dist = Geolocator.distanceBetween(
//           wp.latitude,
//           wp.longitude,
//           routePoint.latitude,
//           routePoint.longitude,
//         );
//         if (dist < minDist) minDist = dist;
//       }
//       return minDist <= bufferDistance;
//     }).toList();

//     filtered.sort((a, b) {
//       double distA = Geolocator.distanceBetween(
//         start.latitude,
//         start.longitude,
//         a.latitude,
//         a.longitude,
//       );
//       double distB = Geolocator.distanceBetween(
//         start.latitude,
//         start.longitude,
//         b.latitude,
//         b.longitude,
//       );
//       return distA.compareTo(distB);
//     });

//     return filtered.take(5).toList();
//   }

//   Future<void> drawRoute() async {
//     if (startPoint == null || endPoint == null || _controller == null) return;

//     final points = await getRoute(startPoint!, endPoint!);
//     if (points.isNotEmpty) {
//       setState(() {
//         routePoints = points;
//       });

//       if (_routeLine != null) {
//         try {
//           await _controller!.removeLine(_routeLine!);
//         } catch (_) {}
//         _routeLine = null;
//       }

//       final line = await _controller!.addLine(
//         maplibre.LineOptions(
//           geometry: points
//               .map((p) => maplibre.LatLng(p.latitude, p.longitude))
//               .toList(),
//           lineWidth: 5.0,
//           lineColor: '#800080',
//           lineOpacity: 0.9,
//         ),
//       );

//       _routeLine = line;

//       final bounds = _boundsFromLatLngList(points);
//       if (bounds != null) {
//         await _controller!.animateCamera(
//           maplibre.CameraUpdate.newLatLngBounds(
//             bounds,
//             left: 40,
//             top: 40,
//             right: 40,
//             bottom: 40,
//           ),
//         );
//       }
//     } else {
//       if (routePoints.isEmpty) {
//         _showMessage('Rota bulunamadı');
//       }
//     }
//   }

//   void clearRoute() async {
//     if (_routeLine != null && _controller != null) {
//       try {
//         await _controller!.removeLine(_routeLine!);
//       } catch (_) {}
//       _routeLine = null;
//     }
//     if (_endPointSymbol != null && _controller != null) {
//       try {
//         await _controller!.removeSymbol(_endPointSymbol!);
//       } catch (_) {}
//       _endPointSymbol = null;
//     }
//     setState(() {
//       startPoint = null;
//       endPoint = null;
//       routePoints.clear();
//       routeDistanceKm = null;
//       routeDurationMin = null;
//     });
//   }

//   maplibre.LatLngBounds? _boundsFromLatLngList(List<LatLng> coords) {
//     if (coords.isEmpty) return null;
//     double minLat = coords.first.latitude, maxLat = coords.first.latitude;
//     double minLng = coords.first.longitude, maxLng = coords.first.longitude;
//     for (final c in coords) {
//       if (c.latitude < minLat) minLat = c.latitude;
//       if (c.latitude > maxLat) maxLat = c.latitude;
//       if (c.longitude < minLng) minLng = c.longitude;
//       if (c.longitude > maxLng) maxLng = c.longitude;
//     }
//     return maplibre.LatLngBounds(
//       southwest: maplibre.LatLng(minLat, minLng),
//       northeast: maplibre.LatLng(maxLat, maxLng),
//     );
//   }

//   IconData _getIcon(String type) {
//     switch (type) {
//       case 'rampa':
//         return Icons.accessible_forward;
//       case 'asansör':
//         return Icons.elevator;
//       case 'yaya_gecidi':
//         return Icons.directions_walk;
//       case 'trafik_isigi':
//         return Icons.traffic;
//       case 'ust_gecit':
//         return Icons.alt_route;
//       default:
//         return Icons.location_on;
//     }
//   }

//   Color _getMarkerColor(String type) {
//     switch (type) {
//       case 'rampa':
//         return Colors.green;
//       case 'asansör':
//         return Colors.orange;
//       case 'yaya_gecidi':
//         return Colors.blue;
//       case 'trafik_isigi':
//         return Colors.red;
//       case 'ust_gecit':
//         return Colors.purple;
//       default:
//         return Colors.grey;
//     }
//   }

//   String _typeToLabel(String type) {
//     switch (type) {
//       case 'rampa':
//         return 'Rampa';
//       case 'asansör':
//         return 'Asansör';
//       case 'yaya_gecidi':
//         return 'Yaya Geçidi';
//       case 'trafik_isigi':
//         return 'Trafik Işığı';
//       case 'ust_gecit':
//         return 'Üst/Alt Geçit';
//       default:
//         return type;
//     }
//   }
