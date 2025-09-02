import 'package:flutter/material.dart';

class HakkindaYardimPage extends StatelessWidget {
  const HakkindaYardimPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          "Hakkında & Yardım",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1976D2),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSection(
              icon: Icons.info_outline,
              title: "Engelsiz Rota Nedir?",
              bullets: [
                "Engelsiz Rota, engelli bireylerin şehir içinde güvenli ve erişilebilir yollar üzerinden seyahat etmesini sağlayan, topluluk katkılı yerli bir navigasyon uygulamasıdır.",
              ],
            ),
            _buildSection(
              icon: Icons.star,
              title: "Öne Çıkan Özellikler",
              bullets: [
                "Rampa, asansör, yaya geçidi gibi erişilebilir noktaları haritada gösterir.",
                "Kullanıcılar engelleri ve uygun yolları ekleyebilir.",
                "Anlık güncellemeler ve topluluk katkısı ile sürekli gelişir.",
              ],
            ),
            _buildSection(
              icon: Icons.help_outline,
              title: "Kullanım Rehberi",
              bullets: [
                "Harita ekranından mevcut konumunuza gidin.",
                "Uzun basarak rota başlangıç ve bitiş noktası belirleyin.",
                "Erişilebilir noktaları ekleyerek topluluğa katkı sağlayın.",
                "Filtre menüsünden görmek istediğiniz nokta türünü seçin.",
              ],
            ),
            _buildTeamSection(),
            _buildContactSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<String> bullets,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bullets.map(
            (text) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "• $text",
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamSection() {
    final members = [
      {"name": "Yavuz Selman Babacan", "role": "Takım Kaptanı (9. Sınıf)"},
      {
        "name": "Mehmet Süha Akyel",
        "role": "Uygulama Optimizasyonu (12. Sınıf)",
      },
      {
        "name": "Ahmet Günsel",
        "role": "Arayüz ve Kullanıcı Deneyimi (12. Sınıf)",
      },
      {"name": "Numan Polat", "role": "Yapay Zeka ve Veri İşleme (9. Sınıf)"},
      {
        "name": "Muhammed Hasan Tezcan",
        "role": "İletişim ve Sosyal Sorumluluk (10. Sınıf)",
      },
      {
        "name": "Mehmet Hilmi Akhan",
        "role": "Harita ve Yol Verileri Yönetimi (2024 Mezunu)",
      },
      {"name": "Ekrem Sivrikaya", "role": "Danışman"},
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.group, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                "Geliştirici Ekip",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...members.map(
            (member) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: "${member['name']}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blue,
                      ),
                    ),
                    TextSpan(
                      text: " – ${member['role']}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.email, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "📧 İletişim: beyondlimits@example.com",
              style: const TextStyle(
                fontSize: 14,
                color: Colors.blue,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
