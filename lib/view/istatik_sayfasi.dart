import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class IstatistikSayfasi extends StatefulWidget {
  const IstatistikSayfasi({super.key});

  @override
  State<IstatistikSayfasi> createState() => _IstatistikSayfasiState();
}

class _IstatistikSayfasiState extends State<IstatistikSayfasi> {
  int toplamKatki = 0;
  Map<String, int> turDagilimi = {};
  List<int> gunlukKatkilar = List.filled(7, 0); // Pazartesi → Pazar

  @override
  void initState() {
    super.initState();
    _verileriGetir();
  }

  Future<void> _verileriGetir() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('marker')
        .get();

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

    int toplam = 0;
    Map<String, int> turler = {};
    List<int> gunluk = List.filled(7, 0);

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final rawType = data['type'] ?? 'bilinmiyor';
      final tarih = (data['createdAt'] as Timestamp?)?.toDate();

      final label = _typeToLabel(rawType.trim().toLowerCase());
      toplam += 1;
      turler[label] = (turler[label] ?? 0) + 1;

      if (tarih != null && tarih.isAfter(startOfWeek)) {
        int index = tarih.weekday - 1;
        gunluk[index] += 1;
      }
    }

    setState(() {
      toplamKatki = toplam;
      turDagilimi = turler;
      gunlukKatkilar = gunluk;
    });
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
        return type[0].toUpperCase() + type.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          "İstatistikler",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1976D2),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeader("Toplam Katkı Sayısı", "$toplamKatki Nokta"),
            const SizedBox(height: 20),
            _buildBarChart(),
            const SizedBox(height: 20),
            _buildHeader("Katkı Türleri Dağılımı", ""),
            const SizedBox(height: 12),
            _buildPieChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title, String subtitle) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBarChart() {
    final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (gunlukKatkilar.reduce((a, b) => a > b ? a : b) + 2)
                .toDouble(),
            barTouchData: BarTouchData(enabled: true),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      days[value.toInt()],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(7, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: gunlukKatkilar[i].toDouble(),
                    color: Colors.blueAccent,
                    width: 16,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: AspectRatio(
        aspectRatio: 1.3,
        child: PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 40,
            sections: turDagilimi.entries.map((entry) {
              final color = _getColor(entry.key);
              return PieChartSectionData(
                value: entry.value.toDouble(),
                title: "${entry.key} (${entry.value})",
                color: color,
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Color _getColor(String label) {
    switch (label) {
      case 'Rampa':
        return Colors.green;
      case 'Asansör':
        return Colors.orange;
      case 'Yaya Geçidi':
        return Colors.purple;
      case 'Trafik Işığı':
        return Colors.red;
      case 'Üst/Alt Geçit':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}
