import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class HesapDetaylariPage extends StatefulWidget {
  const HesapDetaylariPage({super.key});

  @override
  State<HesapDetaylariPage> createState() => _HesapDetaylariPageState();
}

class _HesapDetaylariPageState extends State<HesapDetaylariPage> {
  final _nameController = TextEditingController();
  User? user;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    _nameController.text = user?.displayName ?? "";
  }

  Future<void> _updateDisplayName() async {
    if (_nameController.text.trim().isEmpty) return;
    try {
      await user?.updateDisplayName(_nameController.text.trim());
      await user?.reload();
      user = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("İsim başarıyla güncellendi")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Güncelleme başarısız: $e")));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Hesap Detayları',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1976D2),
      ),
      body: user == null
          ? const Center(child: Text("Kullanıcı bilgisi bulunamadı."))
          : SingleChildScrollView(
              child: Center(
                child: Card(
                  color: const Color(0xFFF5F5F5),
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // EN ÜSTE: Profil İkonu
                        Center(
                          child: Column(
                            children: const [
                              Icon(
                                Icons.account_circle,
                                size: 100,
                                color: Colors.blue,
                              ),
                              SizedBox(height: 24),
                            ],
                          ),
                        ),

                        // İsim / Soyisim Güncelle
                        const Text(
                          "İsim / Soyisim Güncelle",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: "İsim Soyisim",
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _updateDisplayName,
                            child: const Text("Güncelle"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Kullanıcı Bilgileri
                        _buildDetail("📧 E-Posta", user!.email ?? "Yok"),
                        const SizedBox(height: 16),
                        _buildDetail("🆔 UID", user!.uid),
                        const SizedBox(height: 16),
                        _buildDetail(
                          "📅 Hesap Oluşturulma",
                          user!.metadata.creationTime != null
                              ? DateFormat(
                                  'dd.MM.yyyy HH:mm',
                                ).format(user!.metadata.creationTime!)
                              : "Bilinmiyor",
                        ),
                        const SizedBox(height: 16),
                        _buildDetail(
                          "🕓 Son Giriş",
                          user!.metadata.lastSignInTime != null
                              ? DateFormat(
                                  'dd.MM.yyyy HH:mm',
                                ).format(user!.metadata.lastSignInTime!)
                              : "Bilinmiyor",
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildDetail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 15, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
