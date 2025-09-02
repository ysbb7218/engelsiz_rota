import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:engelsiz_rota/model/marker_model.dart';
import 'package:intl/intl.dart';

class ErisilebilirNoktalarListesi extends StatelessWidget {
  const ErisilebilirNoktalarListesi({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        centerTitle: true,
        title: const Text(
          "Topluluk Katkıları",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        iconTheme: const IconThemeData(size: 28, color: Colors.white),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('markers')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Veri yüklenemedi"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final markers = snapshot.data!.docs
              .map(
                (doc) =>
                    MarkerModel.fromMap(doc.data() as Map<String, dynamic>),
              )
              .toList();

          if (markers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    "Henüz erişilebilir nokta eklenmemiş.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Verileri türüne göre grupla
          final groupedMarkers = <String, List<MarkerModel>>{};
          for (var marker in markers) {
            groupedMarkers.putIfAbsent(marker.type, () => []).add(marker);
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: groupedMarkers.entries.map((entry) {
              final type = entry.key;
              final group = entry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    _typeToLabel(type),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...group.map(
                    (marker) => Card(
                      color: Colors.grey.shade100,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                _getIcon(marker.type),
                                color: Colors.blue.shade700,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    marker.description,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    marker.createdAt != null
                                        ? DateFormat(
                                            'dd MMMM yyyy – HH:mm',
                                          ).format(marker.createdAt!)
                                        : '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
