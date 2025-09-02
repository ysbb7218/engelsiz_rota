import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.likes = 0,
    this.createdAt,
  });

  factory MarkerModel.fromMap(Map<String, dynamic> data) {
    return MarkerModel(
      type: data['type'] ?? '',
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      description: data['description'] ?? '',
      likes: data['likes'] ?? 0,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
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
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
