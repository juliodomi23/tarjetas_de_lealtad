import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBase = 'https://lealtad.ambarrojostudios.cloud';

class RewardTier {
  final int id, stampsRequired;
  final String description;
  const RewardTier({required this.id, required this.stampsRequired, required this.description});
  factory RewardTier.fromJson(Map j) => RewardTier(
        id: j['id'] ?? 0,
        stampsRequired: j['stamps_required'] ?? 0,
        description: j['description'] ?? '',
      );
}

class Business {
  final int id;
  final String slug, name, logoUrl, cardBgImage, tagline;
  final Color primaryColor;
  final Color? cardBg, cardTextColor; // null = diseño por defecto
  final int cycleDays;
  final List<RewardTier> rewardTiers;

  const Business({
    required this.id,
    required this.slug,
    required this.name,
    required this.logoUrl,
    required this.primaryColor,
    this.cardBg,
    this.cardBgImage = '',
    this.cardTextColor,
    this.tagline = '',
    required this.cycleDays,
    required this.rewardTiers,
  });

  int get maxStamps => rewardTiers.isEmpty
      ? 0
      : rewardTiers.map((t) => t.stampsRequired).reduce((a, b) => a > b ? a : b);

  static Color _parseColor(String? raw) => _tryColor(raw) ?? const Color(0xFFE23B3B);

  static Color? _tryColor(String? raw) {
    final h = (raw ?? '').replaceAll('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  static String hex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  factory Business.fromJson(Map<String, dynamic> j) => Business(
        id:            j['id'] ?? 0,
        slug:          j['slug'] ?? '',
        name:          j['name'] ?? j['business'] ?? '',
        logoUrl:       j['logo_url'] ?? '',
        primaryColor:  _parseColor(j['primary_color']),
        cardBg:        _tryColor(j['card_bg']),
        cardBgImage:   j['card_bg_image'] ?? '',
        cardTextColor: _tryColor(j['card_text_color']),
        tagline:       j['tagline'] ?? '',
        cycleDays:     j['cycle_days'] ?? 30,
        rewardTiers:   (j['reward_tiers'] as List? ?? []).map((t) => RewardTier.fromJson(t)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'slug': slug, 'name': name,
        'logo_url': logoUrl,
        'primary_color': hex(primaryColor),
        'card_bg': cardBg != null ? hex(cardBg!) : '',
        'card_bg_image': cardBgImage,
        'card_text_color': cardTextColor != null ? hex(cardTextColor!) : '',
        'tagline': tagline,
        'cycle_days': cycleDays,
      };
}

// Tarjeta local: un negocio + token del cliente
class LoyaltyCard {
  final Business business;
  final String token;
  const LoyaltyCard({required this.business, required this.token});

  Map<String, dynamic> toJson() => {'business': business.toJson(), 'token': token};

  factory LoyaltyCard.fromJson(Map<String, dynamic> j) => LoyaltyCard(
        business: Business.fromJson(j['business']),
        token: j['token'],
      );
}

class Api {
  // ── Negocios ────────────────────────────────────────────────────────────────

  static Future<List<Business>> listBusinesses() async {
    final r = await http.get(Uri.parse('$apiBase/api/businesses'));
    return (jsonDecode(r.body) as List).map((b) => Business.fromJson(b)).toList();
  }

  static Future<Business> config(String slug) async {
    final r = await http.get(Uri.parse('$apiBase/api/config?b=$slug'));
    return Business.fromJson(jsonDecode(r.body));
  }

  // ── Clientes ────────────────────────────────────────────────────────────────

  static Future<LoyaltyCard> join(String slug, String phone, String name) async {
    final r = await http.post(
      Uri.parse('$apiBase/api/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'business_slug': slug, 'phone': phone, 'name': name}),
    );
    final d = jsonDecode(r.body);
    if (r.statusCode != 200) throw d['error'] ?? 'Error';
    final biz = Business.fromJson(d['business']);
    return LoyaltyCard(business: biz, token: d['token']);
  }

  static Future<Map<String, dynamic>> card(String token) async {
    final r = await http.get(Uri.parse('$apiBase/api/card?t=$token'));
    if (r.statusCode != 200) throw 'No encontrado';
    return jsonDecode(r.body);
  }

  // ── Staff ───────────────────────────────────────────────────────────────────

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

  static Future<Map<String, dynamic>> adminStats(String slug, String pass) async {
    final r = await http.get(Uri.parse('$apiBase/api/$slug/stats'),
        headers: {'Authorization': 'Bearer $pass'});
    if (r.statusCode == 401) throw 'Clave incorrecta';
    return jsonDecode(r.body);
  }

  static Future<List<dynamic>> adminCustomers(String slug, String pass) async {
    final r = await http.get(Uri.parse('$apiBase/api/$slug/customers'),
        headers: {'Authorization': 'Bearer $pass'});
    if (r.statusCode == 401) throw 'Clave incorrecta';
    return jsonDecode(r.body);
  }

  static Future<List<RewardTier>> getRewardTiers(String slug, String pass) async {
    final r = await http.get(Uri.parse('$apiBase/api/$slug/reward-tiers'),
        headers: {'Authorization': 'Bearer $pass'});
    if (r.statusCode == 401) throw 'Clave incorrecta';
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }

  static Future<List<RewardTier>> addRewardTier(String slug, String pass, int stamps, String desc) async {
    final r = await http.post(Uri.parse('$apiBase/api/$slug/reward-tiers'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $pass'},
        body: jsonEncode({'stamps_required': stamps, 'description': desc}));
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }

  static Future<List<RewardTier>> updateRewardTier(String slug, String pass, int id, int stamps, String desc) async {
    final r = await http.put(Uri.parse('$apiBase/api/$slug/reward-tiers/$id'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $pass'},
        body: jsonEncode({'stamps_required': stamps, 'description': desc}));
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }

  static Future<List<RewardTier>> deleteRewardTier(String slug, String pass, int id) async {
    final r = await http.delete(Uri.parse('$apiBase/api/$slug/reward-tiers/$id'),
        headers: {'Authorization': 'Bearer $pass'});
    return (jsonDecode(r.body) as List).map((t) => RewardTier.fromJson(t)).toList();
  }

  static Future<Map<String, dynamic>> updateSettings(String slug, String pass, Map<String, dynamic> data) async {
    final r = await http.put(Uri.parse('$apiBase/api/$slug/settings'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $pass'},
        body: jsonEncode(data));
    if (r.statusCode == 401) throw 'Clave incorrecta';
    return jsonDecode(r.body);
  }
}
