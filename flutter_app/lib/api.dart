import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBase = 'https://lealtad.ambarrojo.com';

class AppConfig {
  final String business;
  final int goal;
  final String rewardText;
  final Color primaryColor;
  final String logoUrl;

  const AppConfig({
    required this.business,
    required this.goal,
    required this.rewardText,
    required this.primaryColor,
    required this.logoUrl,
  });

  static AppConfig fallback() => const AppConfig(
        business: 'Tarjeta de lealtad',
        goal: 8,
        rewardText: 'Premio gratis',
        primaryColor: Color(0xFFE23B3B),
        logoUrl: '',
      );

  static AppConfig fromJson(Map<String, dynamic> j) {
    Color color = const Color(0xFFE23B3B);
    final raw = (j['primary_color'] as String? ?? '').replaceAll('#', '');
    if (raw.length == 6) {
      color = Color(int.parse('FF$raw', radix: 16));
    }
    return AppConfig(
      business: j['business'] ?? 'Mi Negocio',
      goal: j['goal'] ?? 8,
      rewardText: j['reward_text'] ?? 'Premio gratis',
      primaryColor: color,
      logoUrl: j['logo_url'] ?? '',
    );
  }
}

class Api {
  static Future<String> join(String phone, String name) async {
    final r = await http.post(
      Uri.parse('$apiBase/api/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'name': name}),
    );
    final d = jsonDecode(r.body);
    if (r.statusCode != 200) throw d['error'] ?? 'Error';
    return d['token'];
  }

  static Future<Map<String, dynamic>> card(String token) async {
    final r = await http.get(Uri.parse('$apiBase/api/card?t=$token'));
    if (r.statusCode != 200) throw 'No encontrado';
    return jsonDecode(r.body);
  }

  static Future<AppConfig> config() async {
    final r = await http.get(Uri.parse('$apiBase/api/config'));
    return AppConfig.fromJson(jsonDecode(r.body));
  }

  static Future<Map<String, dynamic>> adminStats(String pass) async {
    final r = await http.get(Uri.parse('$apiBase/api/stats'),
        headers: {'Authorization': 'Bearer $pass'});
    if (r.statusCode == 401) throw 'Clave incorrecta';
    return jsonDecode(r.body);
  }

  static Future<List<dynamic>> adminCustomers(String pass) async {
    final r = await http.get(Uri.parse('$apiBase/api/customers'),
        headers: {'Authorization': 'Bearer $pass'});
    if (r.statusCode == 401) throw 'Clave incorrecta';
    return jsonDecode(r.body);
  }

  static Future<Map<String, dynamic>> stamp(String token, String pass) async {
    final r = await http.post(
      Uri.parse('$apiBase/api/stamp'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $pass',
      },
      body: jsonEncode({'token': token}),
    );
    final d = jsonDecode(r.body);
    if (r.statusCode == 401) throw 'Clave incorrecta';
    if (r.statusCode != 200) throw d['error'] ?? 'Error';
    return d;
  }
}
