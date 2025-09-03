import 'package:flutter/material.dart';
import 'package:engelsiz_rota/theme/app_theme.dart';

class RouteDetailsPage extends StatelessWidget {
  final List<Map<String, dynamic>> navigationSteps;
  final List<dynamic> routeWaypoints;
  final double? routeDistanceKm;
  final double? routeDurationMin;

  const RouteDetailsPage({
    super.key,
    required this.navigationSteps,
    required this.routeWaypoints,
    this.routeDistanceKm,
    this.routeDurationMin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text(
          "Rota Detayları",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rota Özeti
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.route,
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
                              "Rota Özeti",
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (routeDistanceKm != null &&
                                routeDurationMin != null)
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatItem(
                        Icons.straighten,
                        "Toplam Adım",
                        "${navigationSteps.length}",
                        AppTheme.primaryBlue,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        Icons.accessible,
                        "Erişilebilir Nokta",
                        "${routeWaypoints.length}",
                        AppTheme.secondaryGreen,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Waypoint'ler
            if (routeWaypoints.isNotEmpty) ...[
              Text("Erişilebilir Noktalar", style: AppTheme.headingSmall),
              const SizedBox(height: 12),
              ...routeWaypoints.asMap().entries.map((entry) {
                final index = entry.key + 1;
                final waypoint = entry.value;
                return _buildWaypointCard(index, waypoint);
              }).toList(),
              const SizedBox(height: 16),
            ],

            // Navigasyon Adımları
            Text("Adım Adım Yönlendirme", style: AppTheme.headingSmall),
            const SizedBox(height: 12),
            ...navigationSteps.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final step = entry.value;
              return _buildStepCard(index, step);
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTheme.bodyLarge.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointCard(int index, dynamic waypoint) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${waypoint.direction.toUpperCase()} yönünde ${_typeToLabel(waypoint.type)}",
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  waypoint.reason,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.straighten,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Başlangıçtan: ${_formatDistance(waypoint.distanceFromStart)}",
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.flag, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      "Hedefe: ${_formatDistance(waypoint.distanceToEnd)}",
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(int index, Map<String, dynamic> step) {
    final direction = step['direction'];
    final distance = step['distance'] as double;
    final reason = step['reason'];
    final turnDirection = step['turnDirection'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _getTurnColor(turnDirection),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getTurnIcon(turnDirection),
                      size: 20,
                      color: _getTurnColor(turnDirection),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        direction,
                        style: AppTheme.bodyLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      _formatDistance(distance),
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    reason,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getTurnColor(String turnDirection) {
    switch (turnDirection) {
      case 'sağa':
        return AppTheme.secondaryGreen;
      case 'sola':
        return AppTheme.secondaryOrange;
      case 'geri':
        return AppTheme.error;
      default:
        return AppTheme.primaryBlue;
    }
  }

  IconData _getTurnIcon(String turnDirection) {
    switch (turnDirection) {
      case 'sağa':
        return Icons.turn_right;
      case 'sola':
        return Icons.turn_left;
      case 'geri':
        return Icons.u_turn_left;
      default:
        return Icons.straight;
    }
  }

  String _formatDistance(double distance) {
    if (distance < 1000) {
      return '${distance.toInt()}m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)}km';
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
}
