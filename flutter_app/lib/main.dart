import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';

AppConfig _cfg = AppConfig.fallback();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cfg = await Api.config();
    brand = _cfg.primaryColor;
  } catch (_) {}
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarjeta de lealtad',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Gate(),
    );
  }
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  String? _token;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      setState(() {
        _token = p.getString('token');
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return _token == null ? const JoinScreen() : CardScreen(token: _token!);
  }
}

// ─── Join ────────────────────────────────────────────────────────────────────

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final String _biz = _cfg.business;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Escribe tu nombre.');
    if (phone.length != 10) return setState(() => _error = 'El WhatsApp debe tener 10 dígitos.');
    setState(() { _busy = true; _error = null; });
    try {
      final token = await Api.join(phone, name);
      final p = await SharedPreferences.getInstance();
      await p.setString('token', token);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CardScreen(token: token)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BrandBadge(),
                const SizedBox(height: 24),
                Text(_biz, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Regístrate con tu WhatsApp y empieza a juntar sellos.',
                    textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.5)),
                const SizedBox(height: 28),
                _WhiteCard(
                  child: Column(
                    children: [
                      TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                              hintText: 'Tu nombre',
                              prefixIcon: Icon(Icons.person_outline, color: muted))),
                      const SizedBox(height: 14),
                      TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          onSubmitted: (_) => _busy ? null : _submit(),
                          decoration: const InputDecoration(
                              hintText: 'WhatsApp (10 dígitos)',
                              prefixIcon: Icon(Icons.phone_outlined, color: muted))),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBanner(_error!),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.card_membership),
                        label: Text(_busy ? 'Creando...' : 'Crear mi tarjeta'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ScannerScreen())),
                  icon: const Icon(Icons.qr_code_scanner, size: 18, color: muted),
                  label: const Text('Soy del personal', style: TextStyle(color: muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Card ────────────────────────────────────────────────────────────────────

class CardScreen extends StatefulWidget {
  final String token;
  const CardScreen({super.key, required this.token});
  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.card(widget.token);
      if (mounted) setState(() => _data = d);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final int stamps = d['stamps'] ?? 0;
    final tiers = (d['reward_tiers'] as List? ?? []).map((t) => RewardTier.fromJson(t)).toList();
    final int cycleDays = d['cycle_days'] ?? 30;
    final cycleStart = DateTime.tryParse(d['cycle_start'] ?? '') ?? DateTime.now();
    final cycleEnd = cycleStart.add(Duration(days: cycleDays));
    final maxStamps = tiers.isEmpty ? 0 : tiers.map((t) => t.stampsRequired).reduce((a, b) => a > b ? a : b);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _LoyaltyCard(
                business: d['business'] ?? _cfg.business,
                name: d['name'] ?? '',
                token: widget.token,
                stamps: stamps,
                maxStamps: maxStamps,
              ),
              const SizedBox(height: 16),
              _CycleInfo(cycleEnd: cycleEnd),
              const SizedBox(height: 16),
              _WhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tus sellos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text('$stamps${maxStamps > 0 ? ' / $maxStamps' : ''}',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: brand)),
                      ],
                    ),
                    if (maxStamps > 0) ...[
                      const SizedBox(height: 12),
                      _StampGrid(stamps: stamps, maxStamps: maxStamps, tiers: tiers),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _RewardList(tiers: tiers, stamps: stamps),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scanner ─────────────────────────────────────────────────────────────────

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  String? _pass;
  List<RewardTier> _earned = [];
  String _error = '';
  bool _busy = false;
  bool _reset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePass());
  }

  Future<void> _ensurePass() async {
    final p = await SharedPreferences.getInstance();
    _pass = p.getString('staffPass');
    if (_pass == null && mounted) {
      final entered = await _askPass();
      if (entered != null && entered.isNotEmpty) {
        await p.setString('staffPass', entered);
        setState(() => _pass = entered);
      } else if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<String?> _askPass() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Clave del personal'),
        content: TextField(controller: c, obscureText: true, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Entrar')),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy || _pass == null) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() => _busy = true);
    try {
      final d = await Api.stamp(raw, _pass!);
      final earnedList = (d['earned'] as List? ?? []).map((t) => RewardTier.fromJson(t)).toList();
      setState(() {
        _earned = earnedList;
        _reset = d['reset'] == true;
        _error = '';
      });
    } catch (e) {
      if (e == 'Clave incorrecta') {
        final p = await SharedPreferences.getInstance();
        await p.remove('staffPass');
        _pass = null;
      }
      setState(() { _error = e.toString(); _earned = []; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _busy;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Sellar tarjeta', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        actions: [
          if (_pass != null)
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: 'Panel del dueño',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AdminScreen(pass: _pass!))),
            ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(onDetect: _onDetect),
          if (!hasResult) ...[
            Container(
              width: 240, height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const Positioned(
              bottom: 80,
              child: Text('Apunta al código del cliente',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
          if (hasResult)
            Container(
              color: Colors.black.withValues(alpha: 0.9),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _error.isNotEmpty ? Icons.error_outline : Icons.check_circle,
                    color: _error.isNotEmpty ? brand : success,
                    size: 72,
                  ),
                  const SizedBox(height: 16),
                  if (_error.isNotEmpty)
                    Text(_error, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))
                  else if (_earned.isEmpty && !_reset)
                    const Text('¡Sello agregado!', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white))
                  else ...[
                    if (_reset)
                      const Text('¡Ciclo completado! 🎉', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (_earned.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Premios ganados:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 8),
                      ..._earned.map((t) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 20),
                                const SizedBox(width: 8),
                                Text(t.description,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )),
                    ],
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () => setState(() { _busy = false; _earned = []; _error = ''; _reset = false; }),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Siguiente cliente'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Admin ───────────────────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  final String pass;
  const AdminScreen({super.key, required this.pass});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _stats;
  List<dynamic>? _customers;
  List<RewardTier> _tiers = [];
  String? _error;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        Api.adminStats(widget.pass),
        Api.adminCustomers(widget.pass),
        Api.getRewardTiers(widget.pass),
      ]);
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _customers = results[1] as List<dynamic>;
        _tiers = results[2] as List<RewardTier>;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _refreshTiers() async {
    final tiers = await Api.getRewardTiers(widget.pass);
    setState(() => _tiers = tiers);
  }

  void _showTierDialog({RewardTier? tier}) {
    final stampsCtrl = TextEditingController(text: tier != null ? '${tier.stampsRequired}' : '');
    final descCtrl = TextEditingController(text: tier?.description ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tier == null ? 'Nueva recompensa' : 'Editar recompensa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: stampsCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Sellos requeridos')),
            const SizedBox(height: 12),
            TextField(controller: descCtrl,
                decoration: const InputDecoration(hintText: 'Descripción del premio')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final stamps = int.tryParse(stampsCtrl.text) ?? 0;
              final desc = descCtrl.text.trim();
              if (stamps <= 0 || desc.isEmpty) return;
              Navigator.pop(context);
              if (tier == null) {
                await Api.addRewardTier(widget.pass, stamps, desc);
              } else {
                await Api.updateRewardTier(widget.pass, tier.id, stamps, desc);
              }
              await _refreshTiers();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text(_cfg.business),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: brand)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _KpiGrid(stats: _stats!),
                      const SizedBox(height: 20),
                      _ActivityChart(daily: List<Map>.from(_stats!['daily'] ?? [])),
                      const SizedBox(height: 20),
                      _TiersManager(
                        tiers: _tiers,
                        pass: widget.pass,
                        onAdd: () => _showTierDialog(),
                        onEdit: (t) => _showTierDialog(tier: t),
                        onDelete: (t) async {
                          await Api.deleteRewardTier(widget.pass, t.id);
                          await _refreshTiers();
                        },
                      ),
                      const SizedBox(height: 20),
                      _CustomerList(
                        customers: _customers ?? [],
                        search: _search,
                        onSearch: (v) => setState(() => _search = v),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ─── Widgets reutilizables ───────────────────────────────────────────────────

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        color: brand,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: brand.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: _cfg.logoUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(_cfg.logoUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.loyalty, color: Colors.white, size: 38)))
          : const Icon(Icons.loyalty, color: Colors.white, size: 38),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}

class _LoyaltyCard extends StatelessWidget {
  final String business, name, token;
  final int stamps, maxStamps;
  const _LoyaltyCard({required this.business, required this.name, required this.token, required this.stamps, required this.maxStamps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF111528).withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(business, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    if (name.isNotEmpty)
                      Text('Hola, $name', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.loyalty, color: brand, size: 26),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Semantics(
              label: 'Código QR de tu tarjeta de lealtad',
              image: true,
              child: QrImageView(data: token, size: 180),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Muestra este código en el local para sellar',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CycleInfo extends StatelessWidget {
  final DateTime cycleEnd;
  const _CycleInfo({required this.cycleEnd});
  @override
  Widget build(BuildContext context) {
    final days = cycleEnd.difference(DateTime.now()).inDays;
    final expired = days < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: expired ? brand.withValues(alpha: 0.08) : success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: expired ? brand.withValues(alpha: 0.2) : success.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: expired ? brand : success),
          const SizedBox(width: 8),
          Text(
            expired ? 'Ciclo vencido — se reiniciará con el próximo sello'
                : days == 0 ? 'El ciclo vence hoy'
                : 'Ciclo vence en $days día${days == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 13, color: expired ? brand : success, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _StampGrid extends StatelessWidget {
  final int stamps, maxStamps;
  final List<RewardTier> tiers;
  const _StampGrid({required this.stamps, required this.maxStamps, required this.tiers});

  @override
  Widget build(BuildContext context) {
    final tierSet = tiers.map((t) => t.stampsRequired).toSet();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(maxStamps, (i) {
        final pos = i + 1;
        final on = pos <= stamps;
        final isTier = tierSet.contains(pos);
        return Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? brand : const Color(0xFFF1F5F9),
            border: Border.all(color: isTier ? brand : (on ? brand : line), width: isTier ? 2.5 : 1.5),
          ),
          child: Icon(
            isTier ? (on ? Icons.star_rounded : Icons.star_outline_rounded)
                   : (on ? Icons.circle : Icons.circle_outlined),
            color: on ? Colors.white : (isTier ? brand.withValues(alpha: 0.4) : const Color(0xFFCBD5E1)),
            size: isTier ? 26 : 16,
          ),
        );
      }),
    );
  }
}

class _RewardList extends StatelessWidget {
  final List<RewardTier> tiers;
  final int stamps;
  const _RewardList({required this.tiers, required this.stamps});

  @override
  Widget build(BuildContext context) {
    if (tiers.isEmpty) return const SizedBox.shrink();
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recompensas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...tiers.map((t) {
            final earned = stamps >= t.stampsRequired;
            final remaining = t.stampsRequired - stamps;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: earned ? success.withValues(alpha: 0.12) : brand.withValues(alpha: 0.08),
                    ),
                    child: Icon(
                      earned ? Icons.check_circle_rounded : Icons.workspace_premium_outlined,
                      color: earned ? success : brand, size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.description,
                            style: TextStyle(fontWeight: FontWeight.w600, color: earned ? success : ink)),
                        Text(
                          earned ? '¡Ganado!' : 'Faltan $remaining sello${remaining == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: earned ? success : muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: earned ? success.withValues(alpha: 0.1) : brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${t.stampsRequired} ★',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: earned ? success : brand)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TiersManager extends StatelessWidget {
  final List<RewardTier> tiers;
  final String pass;
  final VoidCallback onAdd;
  final void Function(RewardTier) onEdit;
  final void Function(RewardTier) onDelete;
  const _TiersManager({required this.tiers, required this.pass, required this.onAdd, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recompensas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12)),
              ),
            ],
          ),
          if (tiers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Sin recompensas configuradas', style: TextStyle(color: muted)),
            )
          else ...[
            const SizedBox(height: 10),
            ...tiers.map((t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('${t.stampsRequired}★', style: TextStyle(fontWeight: FontWeight.w700, color: brand)),
                  ),
                  title: Text(t.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: muted), onPressed: () => onEdit(t)),
                      IconButton(icon: Icon(Icons.delete_outline, size: 20, color: brand), onPressed: () => onDelete(t)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _KpiGrid({required this.stats});
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
      childAspectRatio: 1.6, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      children: [
        _KpiCard('Clientes', '${stats['customers']}', Icons.people_outline),
        _KpiCard('Visitas totales', '${stats['visits']}', Icons.loyalty),
        _KpiCard('Premios dados', '${stats['rewards']}', Icons.workspace_premium_outlined),
        _KpiCard('Nuevos hoy', '${stats['new_today']}', Icons.person_add_outlined),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _KpiCard(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: brand, size: 22),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
            Text(label, style: const TextStyle(fontSize: 11, color: muted)),
          ]),
        ],
      ),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  final List<Map> daily;
  const _ActivityChart({required this.daily});
  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final max = daily.map((d) => (d['n'] as int)).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Actividad (14 días)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: daily.map((d) {
                final n = d['n'] as int;
                final frac = max > 0 ? n / max : 0.0;
                final date = (d['d'] as String).substring(5);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (n > 0) Text('$n', style: const TextStyle(fontSize: 9, color: muted)),
                        const SizedBox(height: 2),
                        FractionallySizedBox(
                          heightFactor: frac < 0.05 ? 0.05 : frac,
                          child: Container(
                            decoration: BoxDecoration(
                              color: brand.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(date, style: const TextStyle(fontSize: 8, color: muted)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerList extends StatelessWidget {
  final List<dynamic> customers;
  final String search;
  final ValueChanged<String> onSearch;
  const _CustomerList({required this.customers, required this.search, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final filtered = search.isEmpty
        ? customers
        : customers.where((c) =>
            (c['name'] as String).toLowerCase().contains(search.toLowerCase()) ||
            (c['phone'] as String).contains(search)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Clientes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          onChanged: onSearch,
          decoration: const InputDecoration(hintText: 'Buscar por nombre o teléfono',
              prefixIcon: Icon(Icons.search, color: muted)),
        ),
        const SizedBox(height: 10),
        ...filtered.map((c) => _CustomerTile(c: c)),
      ],
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final dynamic c;
  const _CustomerTile({required this.c});

  void _openWhatsApp(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final number = clean.length == 10 ? '52$clean' : clean;
    launchUrl(Uri.parse('https://wa.me/$number'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: brand.withValues(alpha: 0.12),
            radius: 20,
            child: Text(
              (c['name'] as String).isNotEmpty ? (c['name'] as String)[0].toUpperCase() : '?',
              style: TextStyle(color: brand, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(c['phone'] ?? '', style: const TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${c['stamps']} sellos', style: const TextStyle(fontSize: 12, color: muted)),
            Text('${c['rewards']} premios', style: const TextStyle(fontSize: 12, color: muted)),
          ]),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
            onPressed: () => _openWhatsApp(c['phone'] ?? ''),
            tooltip: 'WhatsApp',
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: brand.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: brand, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: brand, fontSize: 13))),
        ],
      ),
    );
  }
}
