import 'package:latlong2/latlong.dart';
import '../model/grid_node.dart';
import '../model/marker_model.dart';

const double cellSize = 0.0002; // Yaklaşık 20 metre
const int gridWidth = 80;
const int gridHeight = 80;

// Harita üzerindeki üst sol köşe koordinatı (örnek: Isparta)
final LatLng topLeft = LatLng(38.765, 30.530);

/// Grid oluşturur (GridNode listesi döner)
List<GridNode> generateGrid() {
  List<GridNode> grid = [];
  for (int i = 0; i < gridHeight; i++) {
    for (int j = 0; j < gridWidth; j++) {
      double lat = topLeft.latitude - (i * cellSize);
      double lng = topLeft.longitude + (j * cellSize);
      grid.add(GridNode(x: j, y: i, position: LatLng(lat, lng)));
    }
  }
  return grid;
}

/// Firebase'den gelen marker verileri ile cost'ları ayarla
void applyMarkerCosts(List<GridNode> grid, List<MarkerModel> markers) {
  final Distance distance = Distance();

  for (final node in grid) {
    for (final marker in markers) {
      final double d = distance(
        node.position!,
        LatLng(marker.latitude, marker.longitude),
      );
      if (d < 20) {
        switch (marker.type) {
          case 'rampa':
          case 'asansör':
            node.cost = 0.5; // En uygun yapı
            break;
          case 'yaya_gecidi':
          case 'trafik_isigi':
          case 'ust_gecit':
            node.cost = 1.0; // Uygun
            break;
          default:
            node.cost = 5.0; // Belirsiz yapı = yüksek maliyet
        }
      }
    }
  }
}

/// Bir LatLng konumuna en yakın GridNode'u bul
GridNode? findClosestNode(List<GridNode> grid, LatLng target) {
  final Distance distance = Distance();
  GridNode? closest;
  double minDistance = double.infinity;

  for (final node in grid) {
    final d = distance(target, node.position!);
    if (d < minDistance) {
      minDistance = d;
      closest = node;
    }
  }

  return closest;
}
