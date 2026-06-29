import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBase = 'https://lealtad.ambarrojostudios.cloud';

class RewardTier {
  final int id;
  final int stampsRequired;
  final String description;
  const RewardTier({required this.id, required this.stampsRequired, required this.description});

  factory RewardTier.fromJson(Map j) => RewardTier(
        id: j['id'] ?? 0,
        stampsRequired: j['stamps_required'] ?? 0,
        description: j['description'] ?? '',
      );
}

class AppConfig {
  final String business;
  final List<RewardTier> rewardTiers;
  final int cycleDays;
  final Color primaryColor;
  final String logoUrl;

  const AppConfig({
    required this.business,
    required this.rewardTiers,
    required this.cycleDays,
    required this.primaryColor,
    required this.logoUrl,
  });

  static AppConfig fallback() => const AppConfig(
        business: 'Tarjeta de lealtad',
        rewardTiers: [],
        cycleDays: 30,
        primaryColor: Color(0xFFE23B3B),
        logoUrl: '',
      );

  static AppConfig fromJson(Map<String, dynamic> j) {
    Color color = const Color(0xFFE23B3B);
    final raw = (j['primary_color'] as String? ?? '').replaceAll('#', '');
    if (raw.length == 6) color = Color(int.parse('FF$raw', radix: 16));
    final tiers = (j['reward_tiers'] as List? ?? []).map((t) => RewardTier.fromJson(t)).toList();
    return AppConfig(
      business: j['business'] ?? 'Mi Negocio',
      rewardTiers: tiers,
      cycleDays: j['cycle_days'] ?? 30,
      primaryColor: color,
      logoUrl: j['logo_url'] ?? '',
    );
  }

  int get maxStamps => rewardTiers.isEmpty ? 0 : rewardTiers.map((t) => t.stampsRequired).reduce((a, b) => a > b ? a : b);
  RewardTier? nextTier(int stamps) {
    final pending = rewardTiers.where((t) => t.stampsRequired > stamps).toList();
    return pending.isEmpty ? null : pending.first;
  }
}

class Api {
  static Future<AppConfig> config() async {
    final r = await http.get(Uri.parse('$apiBase/api/config'));
    return AppConfig.fromJson(jsonDecode(r.body));
  }

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

  static Future<Map<String, dynamic>> stamp(String token, String pass) async {
    final r = await http.post(
      Uri.parse('$apiBase/api/stamp'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $pass'},
      body: jsonEncode({'token': token}),
    );
    final d = jsonDecode(r.body);
    if (r.statusCode == 401) throw 'Clave incorrecta';
    if (r.statusCode != 200) throw d['error'] ?? 'Error';
    return d;
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

  static Future<List<RewardTier>> getRewardTiers(String pass) async {
    final r = await http.get(Uri.parse('$apiBase/api/reward-tiers'),
        headers: {'Authorization': 'Bearer $pass'});
    if (r.statusCode == 401) throw 'Clave incorrecta';
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }

  static Future<List<RewardTier>> addRewardTier(String pass, int stamps, String desc) async {
    final r = await http.post(Uri.parse('$apiBase/api/reward-tiers'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $pass'},
        body: jsonEncode({'stamps_required': stamps, 'description': desc}));
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }

  static Future<List<RewardTier>> updateRewardTier(String pass, int id, int stamps, String desc) async {
    final r = await http.put(Uri.parse('$apiBase/api/reward-tiers/$id'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $pass'},
        body: jsonEncode({'stamps_required': stamps, 'description': desc}));
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }

  static Future<List<RewardTier>> deleteRewardTier(String pass, int id) async {
    final r = await http.delete(Uri.parse('$apiBase/api/reward-tiers/$id'),
        headers: {'Authorization': 'Bearer $pass'});
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }
}
