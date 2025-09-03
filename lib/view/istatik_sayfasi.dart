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
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _verileriGetir();
  }

  Future<void> _verileriGetir() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final snapshot = await FirebaseFirestore.instance
          .collection('markers')
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
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Veriler yüklenirken hata oluştu: ${e.toString()}';
        isLoading = false;
      });
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _verileriGetir,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'İstatistikler yükleniyor...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _verileriGetir,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (toplamKatki == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Henüz hiç marker eklenmemiş',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'İstatistikler görüntülemek için önce haritaya marker ekleyin',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
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
    final maxValue = gunlukKatkilar.isNotEmpty
        ? gunlukKatkilar.reduce((a, b) => a > b ? a : b)
        : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxValue > 0 ? (maxValue + 2).toDouble() : 5.0,
            barTouchData: BarTouchData(enabled: true),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() >= 0 && value.toInt() < days.length) {
                      return Text(
                        days[value.toInt()],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(7, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: gunlukKatkilar[i].toDouble(),
                    color: gunlukKatkilar[i] > 0
                        ? Colors.blueAccent
                        : Colors.grey.shade300,
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
    if (turDagilimi.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Veri bulunamadı',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

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
                title: "${entry.key}\n(${entry.value})",
                color: color,
                titleStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                radius: 80,
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
