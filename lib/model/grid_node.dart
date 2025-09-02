import 'package:latlong2/latlong.dart';

class GridNode {
  final int x, y;
  final LatLng? position;
  double cost;
  bool isObstacle;
  
  // A* algoritması için gerekli alanlar
  double gCost; // Başlangıçtan bu noktaya olan maliyet
  double hCost; // Bu noktadan hedefe olan tahmini maliyet (heuristic)
  GridNode? parent; // Yol rekonstrüksiyonu için parent node

  GridNode({
    required this.x,
    required this.y,
    this.position,
    this.cost = 1.0,
    this.isObstacle = false,
    this.gCost = 0.0,
    this.hCost = 0.0,
    this.parent,
  });

  // Toplam maliyet (fCost = gCost + hCost)
  double get fCost => gCost + hCost;
}
