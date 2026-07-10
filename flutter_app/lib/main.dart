import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';

List<LoyaltyCard> _cards = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('cards');
  if (raw != null) {
    try {
      _cards = (jsonDecode(raw) as List).map((c) => LoyaltyCard.fromJson(c)).toList();
    } catch (_) {}
  }
  if (_cards.isNotEmpty) brand = _cards.first.business.primaryColor;
  runApp(const App());
}

Future<void> _saveCards(List<LoyaltyCard> cards) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('cards', jsonEncode(cards.map((c) => c.toJson()).toList()));
  _cards = cards;
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarjetas de lealtad',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}

// ─── Home ─────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LoyaltyCard> _localCards = List.from(_cards);
  final _page = PageController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _addCard(LoyaltyCard lcard) {
    final updated = [..._localCards, lcard];
    _saveCards(updated);
    setState(() => _localCards = updated);
    brand = lcard.business.primaryColor;
  }

  void _removeCard(int index) {
    final updated = List<LoyaltyCard>.from(_localCards)..removeAt(index);
    _saveCards(updated);
    setState(() => _localCards = updated);
  }

  Future<void> _goAddBusiness() async {
    final lcard = await Navigator.push<LoyaltyCard>(
        context, MaterialPageRoute(builder: (_) => const BusinessPickerScreen()));
    if (lcard != null) _addCard(lcard);
  }

  @override
  Widget build(BuildContext context) {
    if (_localCards.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: brand, borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: brand.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
                    ),
                    child: const Icon(Icons.loyalty, color: Colors.white, size: 42),
                  ),
                  const SizedBox(height: 24),
                  const Text('Tus tarjetas de lealtad', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('Regístrate en un negocio para empezar a acumular sellos y ganar premios.', textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.5)),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _goAddBusiness,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar negocio'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen())),
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

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text('Mis tarjetas (${_localCards.length})', style: const TextStyle(fontSize: 16)),
        actions: [
          // El acceso del personal va escondido en el menú para no confundir al cliente
          PopupMenuButton<String>(
            onSelected: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen())),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'staff',
                child: Row(children: [
                  Icon(Icons.qr_code_scanner, size: 20, color: muted),
                  SizedBox(width: 10),
                  Text('Soy del personal'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: _localCards.length,
        itemBuilder: (_, i) => _CardPage(
          lcard: _localCards[i],
          onRemove: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Eliminar tarjeta'),
                content: Text('¿Quieres eliminar tu tarjeta de ${_localCards[i].business.name}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  FilledButton(
                    onPressed: () { Navigator.pop(context); _removeCard(i); },
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _localCards.length > 1
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_localCards.length, (i) => AnimatedBuilder(
                  animation: _page,
                  builder: (_, __) {
                    final cur = _page.hasClients ? (_page.page ?? 0).round() : 0;
                    return Container(
                      width: cur == i ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: cur == i ? brand : line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                )),
              ),
            )
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: _goAddBusiness,
        backgroundColor: brand,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── CardPage ─────────────────────────────────────────────────────────────────

class _CardPage extends StatefulWidget {
  final LoyaltyCard lcard;
  final VoidCallback onRemove;
  const _CardPage({required this.lcard, required this.onRemove});
  @override
  State<_CardPage> createState() => _CardPageState();
}

class _CardPageState extends State<_CardPage> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _offline = false;

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
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.card(widget.lcard.token);
      if (mounted) setState(() { _data = d; _offline = false; });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    // El endpoint /api/card trae el branding fresco; ahí 'name' es el cliente
    // y 'business' es el nombre del negocio — corregimos la clave antes de parsear.
    final biz = d != null
        ? Business.fromJson({...d, 'name': d['business']})
        : widget.lcard.business;
    final stamps = d?['stamps'] as int? ?? 0;
    final tiers = biz.rewardTiers;
    final cycleDays = biz.cycleDays;
    final cycleStart = DateTime.tryParse(d?['cycle_start'] ?? '') ?? DateTime.now();
    final cycleEnd = cycleStart.add(Duration(days: cycleDays));
    final maxStamps = tiers.isEmpty ? 0 : tiers.map((t) => t.stampsRequired).reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        // Padding inferior extra para que el FAB no tape la última recompensa
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        children: [
          _VisualCard(
            biz: biz,
            name: d?['name'] ?? '',
            token: widget.lcard.token,
            stamps: stamps,
            maxStamps: maxStamps,
          ),
          if (_offline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.wifi_off_rounded, size: 18, color: Color(0xFFB45309)),
                SizedBox(width: 8),
                Expanded(child: Text('Sin conexión — tu QR sigue funcionando, pero los sellos pueden no estar al día.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB45309)))),
              ]),
            ),
          ],
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
                    Text('${d == null ? '—' : stamps}${maxStamps > 0 ? ' / $maxStamps' : ''}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: biz.primaryColor)),
                  ],
                ),
                if (maxStamps > 0) ...[
                  const SizedBox(height: 12),
                  _StampGrid(stamps: stamps, maxStamps: maxStamps, tiers: tiers, color: biz.primaryColor),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _RewardList(tiers: tiers, stamps: stamps, color: biz.primaryColor),
          const SizedBox(height: 16),
          TextButton(
            onPressed: widget.onRemove,
            child: const Text('Eliminar esta tarjeta', style: TextStyle(color: muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─── Business Picker ──────────────────────────────────────────────────────────

class BusinessPickerScreen extends StatefulWidget {
  const BusinessPickerScreen({super.key});
  @override
  State<BusinessPickerScreen> createState() => _BusinessPickerScreenState();
}

class _BusinessPickerScreenState extends State<BusinessPickerScreen> {
  List<Business>? _businesses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Api.listBusinesses();
      setState(() { _businesses = list; _error = null; });
    } catch (_) {
      setState(() => _error = 'No se pudo cargar la lista de negocios.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elige un negocio')),
      body: _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, style: TextStyle(color: brand)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ]))
          : _businesses == null
              ? const Center(child: CircularProgressIndicator())
              : _businesses!.isEmpty
                  ? const Center(child: Text('No hay negocios disponibles.', style: TextStyle(color: muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _businesses!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final b = _businesses![i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final lcard = await Navigator.push<LoyaltyCard>(
                                context, MaterialPageRoute(builder: (_) => JoinScreen(business: b)));
                            if (lcard != null && mounted) Navigator.pop(context, lcard);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line),
                            ),
                            child: Row(children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(color: b.primaryColor, borderRadius: BorderRadius.circular(14)),
                                child: b.logoUrl.isNotEmpty
                                    ? ClipRRect(borderRadius: BorderRadius.circular(14),
                                        child: Image.network(b.logoUrl, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.loyalty, color: Colors.white)))
                                    : const Icon(Icons.loyalty, color: Colors.white),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Text(b.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                              const Icon(Icons.chevron_right, color: muted),
                            ]),
                          ),
                        );
                      },
                    ),
    );
  }
}

// ─── Join ─────────────────────────────────────────────────────────────────────

class JoinScreen extends StatefulWidget {
  final Business business;
  const JoinScreen({super.key, required this.business});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() { _name.dispose(); _phone.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Escribe tu nombre.');
    if (phone.length != 10) return setState(() => _error = 'El WhatsApp debe tener 10 dígitos.');
    setState(() { _busy = true; _error = null; });
    try {
      final lcard = await Api.join(widget.business.slug, phone, name);
      if (mounted) Navigator.pop(context, lcard);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: b.primaryColor, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: b.primaryColor.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: b.logoUrl.isNotEmpty
                      ? ClipRRect(borderRadius: BorderRadius.circular(20),
                          child: Image.network(b.logoUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.loyalty, color: Colors.white, size: 38)))
                      : const Icon(Icons.loyalty, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 20),
                Text(b.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Regístrate para empezar a juntar sellos.', textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.5)),
                const SizedBox(height: 24),
                _WhiteCard(child: Column(children: [
                  TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Tu nombre', prefixIcon: Icon(Icons.person_outline, color: muted))),
                  const SizedBox(height: 14),
                  TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration: const InputDecoration(hintText: 'WhatsApp (10 dígitos)', prefixIcon: Icon(Icons.phone_outlined, color: muted))),
                  if (_error != null) ...[const SizedBox(height: 14), _ErrorBanner(_error!)],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.card_membership),
                    label: Text(_busy ? 'Creando...' : 'Crear mi tarjeta'),
                  ),
                ])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Scanner ──────────────────────────────────────────────────────────────────

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  static const _vault = FlutterSecureStorage();
  final _camera = MobileScannerController();
  String? _pass;
  String? _staffSlug;
  List<RewardTier> _earned = [];
  String _error = '';
  bool _scanning = false;
  bool _showResult = false;
  bool _reset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLogin());
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _saveStaff(String slug, String pass) async {
    await _vault.write(key: 'staffSlug', value: slug);
    await _vault.write(key: 'staffPass', value: pass);
    _staffSlug = slug;
    _pass = pass;
  }

  Future<void> _clearStaff() async {
    await _vault.delete(key: 'staffPass');
    await _vault.delete(key: 'staffSlug');
    _pass = null;
    _staffSlug = null;
  }

  Future<void> _ensureLogin() async {
    _pass = await _vault.read(key: 'staffPass');
    _staffSlug = await _vault.read(key: 'staffSlug');
    // Migración: sesiones guardadas antes en SharedPreferences (texto plano)
    if (_pass == null || _staffSlug == null) {
      final p = await SharedPreferences.getInstance();
      final oldPass = p.getString('staffPass'), oldSlug = p.getString('staffSlug');
      if (oldPass != null && oldSlug != null) {
        await _saveStaff(oldSlug, oldPass);
        await p.remove('staffPass');
        await p.remove('staffSlug');
      }
    }
    if (_pass == null || _staffSlug == null) {
      await _askLogin();
    } else {
      setState(() {});
    }
  }

  Future<void> _askLogin() async {
    List<Business> businesses = [];
    try { businesses = await Api.listBusinesses(); } catch (_) {}
    if (!mounted) return;

    String? selectedSlug = _staffSlug ?? (businesses.isNotEmpty ? businesses.first.slug : null);
    final passCtrl = TextEditingController(text: _pass ?? '');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Acceso del personal'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (businesses.isNotEmpty)
              DropdownButtonFormField<String>(
                value: selectedSlug,
                decoration: const InputDecoration(hintText: 'Negocio'),
                items: businesses.map((b) => DropdownMenuItem(value: b.slug, child: Text(b.name))).toList(),
                onChanged: (v) => setSt(() => selectedSlug = v),
              ),
            if (businesses.isEmpty)
              TextField(
                decoration: const InputDecoration(hintText: 'Slug del negocio'),
                onChanged: (v) => selectedSlug = v,
              ),
            const SizedBox(height: 12),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(hintText: 'Clave del personal')),
          ]),
          actions: [
            TextButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (selectedSlug == null || passCtrl.text.isEmpty) return;
                await _saveStaff(selectedSlug!, passCtrl.text);
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_scanning || _showResult || _pass == null) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() => _scanning = true);
    try {
      final d = await Api.stamp(raw, _pass!);
      final earnedList = (d['earned'] as List? ?? []).map((t) => RewardTier.fromJson(t)).toList();
      setState(() { _earned = earnedList; _reset = d['reset'] == true; _error = ''; _showResult = true; });
    } catch (e) {
      if (e.toString() == 'Clave incorrecta') await _clearStaff();
      setState(() { _error = e.toString(); _showResult = true; });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _next() => setState(() { _showResult = false; _earned = []; _error = ''; _reset = false; });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Sellar tarjeta', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            tooltip: 'Linterna',
            onPressed: () => _camera.toggleTorch(),
          ),
          if (_pass != null && _staffSlug != null)
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: 'Panel del negocio',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AdminScreen(slug: _staffSlug!, pass: _pass!))),
            ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: 'Cambiar negocio',
            onPressed: () async {
              await _clearStaff();
              setState(() {});
              _askLogin();
            },
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _camera, onDetect: _onDetect),
          if (!_showResult) ...[
            Container(
              width: 240, height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const Positioned(
              bottom: 80,
              child: Text('Apunta al código del cliente', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
          if (_showResult)
            Container(
              color: Colors.black.withValues(alpha: 0.92),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _error.isNotEmpty ? Icons.error_outline : Icons.check_circle,
                    color: _error.isNotEmpty ? brand : success, size: 72,
                  ),
                  const SizedBox(height: 16),
                  if (_error.isNotEmpty)
                    Text(_error, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))
                  else if (_earned.isEmpty && !_reset)
                    const Text('Sello agregado', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white))
                  else ...[
                    if (_reset)
                      const Text('Ciclo completado', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (_earned.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Premios ganados:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 8),
                      ..._earned.map((t) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 20),
                              const SizedBox(width: 8),
                              Text(t.description, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                            ]),
                          )),
                    ],
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _next,
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

// ─── Admin ────────────────────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  final String slug, pass;
  const AdminScreen({super.key, required this.slug, required this.pass});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _stats;
  List<dynamic>? _customers;
  List<RewardTier> _tiers = [];
  Business? _biz;
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
        Api.adminStats(widget.slug, widget.pass),
        Api.adminCustomers(widget.slug, widget.pass),
        Api.getRewardTiers(widget.slug, widget.pass),
        Api.config(widget.slug),
      ]);
      setState(() {
        _stats     = results[0] as Map<String, dynamic>;
        _customers = results[1] as List<dynamic>;
        _tiers     = results[2] as List<RewardTier>;
        _biz       = results[3] as Business;
        _loading   = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showTierDialog({RewardTier? tier}) {
    final stampsCtrl = TextEditingController(text: tier != null ? '${tier.stampsRequired}' : '');
    final descCtrl = TextEditingController(text: tier?.description ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tier == null ? 'Nueva recompensa' : 'Editar recompensa'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: stampsCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Sellos requeridos')),
          const SizedBox(height: 12),
          TextField(controller: descCtrl, decoration: const InputDecoration(hintText: 'Descripción del premio')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final stamps = int.tryParse(stampsCtrl.text) ?? 0;
              final desc = descCtrl.text.trim();
              if (stamps <= 0 || desc.isEmpty) return;
              Navigator.pop(context);
              final tiers = tier == null
                  ? await Api.addRewardTier(widget.slug, widget.pass, stamps, desc)
                  : await Api.updateRewardTier(widget.slug, widget.pass, tier.id, stamps, desc);
              setState(() => _tiers = tiers);
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
        title: Text(_biz?.name ?? widget.slug),
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
                      if (_biz != null)
                        _SettingsForm(
                          biz: _biz!,
                          slug: widget.slug,
                          pass: widget.pass,
                          onSaved: (updated) => setState(() => _biz = updated),
                        ),
                      const SizedBox(height: 20),
                      _TiersManager(
                        tiers: _tiers,
                        onAdd: () => _showTierDialog(),
                        onEdit: (t) => _showTierDialog(tier: t),
                        onDelete: (t) => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Eliminar recompensa'),
                            content: Text('¿Eliminar "${t.description}" (${t.stampsRequired} sellos)? Los clientes dejarán de verla.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                              FilledButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  final tiers = await Api.deleteRewardTier(widget.slug, widget.pass, t.id);
                                  setState(() => _tiers = tiers);
                                },
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        ),
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

// ─── Settings Form ────────────────────────────────────────────────────────────

class _SettingsForm extends StatefulWidget {
  final Business biz;
  final String slug, pass;
  final void Function(Business) onSaved;
  const _SettingsForm({required this.biz, required this.slug, required this.pass, required this.onSaved});
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final TextEditingController _name;
  late final TextEditingController _color;
  late final TextEditingController _logo;
  late final TextEditingController _cardBg;
  late final TextEditingController _cardBgImg;
  late final TextEditingController _cardText;
  late final TextEditingController _tagline;
  late final TextEditingController _cycle;
  bool _saving = false;
  String? _msg;

  static String _hexOf(Color? c) => c == null ? '' : Business.hex(c);

  @override
  void initState() {
    super.initState();
    _name     = TextEditingController(text: widget.biz.name);
    _color    = TextEditingController(text: _hexOf(widget.biz.primaryColor));
    _logo     = TextEditingController(text: widget.biz.logoUrl);
    _cardBg    = TextEditingController(text: _hexOf(widget.biz.cardBg));
    _cardBgImg = TextEditingController(text: widget.biz.cardBgImage);
    _cardText = TextEditingController(text: _hexOf(widget.biz.cardTextColor));
    _tagline  = TextEditingController(text: widget.biz.tagline);
    _cycle    = TextEditingController(text: '${widget.biz.cycleDays}');
  }

  @override
  void dispose() {
    _name.dispose(); _color.dispose(); _logo.dispose();
    _cardBg.dispose(); _cardBgImg.dispose(); _cardText.dispose(); _tagline.dispose(); _cycle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _msg = null; });
    try {
      final raw = await Api.updateSettings(widget.slug, widget.pass, {
        'name':            _name.text.trim(),
        'primary_color':   _color.text.trim(),
        'logo_url':        _logo.text.trim(),
        'card_bg':         _cardBg.text.trim(),
        'card_bg_image':   _cardBgImg.text.trim(),
        'card_text_color': _cardText.text.trim(),
        'tagline':         _tagline.text.trim(),
        'cycle_days':      int.tryParse(_cycle.text) ?? 30,
      });
      final updated = Business.fromJson(raw);
      widget.onSaved(updated);
      setState(() => _msg = 'Guardado');
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Configuración del negocio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        _Field(ctrl: _name,  label: 'Nombre del negocio',       icon: Icons.store_outlined),
        const SizedBox(height: 10),
        _Field(ctrl: _color, label: 'Color principal (hex)',     icon: Icons.palette_outlined),
        const SizedBox(height: 10),
        _Field(ctrl: _logo,  label: 'URL del logo (opcional)',   icon: Icons.image_outlined),
        const SizedBox(height: 10),
        _Field(ctrl: _cardBg,   label: 'Fondo de la tarjeta (hex, vacío = default)', icon: Icons.format_paint_outlined),
        const SizedBox(height: 10),
        _Field(ctrl: _cardBgImg, label: 'URL de foto de fondo (opcional)',           icon: Icons.wallpaper_outlined),
        const SizedBox(height: 10),
        _Field(ctrl: _cardText, label: 'Color del texto (hex, vacío = blanco)',      icon: Icons.text_fields_outlined),
        const SizedBox(height: 10),
        _Field(ctrl: _tagline,  label: 'Frase de la tarjeta (opcional)',             icon: Icons.short_text),
        const SizedBox(height: 10),
        _Field(ctrl: _cycle, label: 'Duración del ciclo (días)', icon: Icons.timer_outlined, keyboardType: TextInputType.number),
        if (_msg != null) ...[
          const SizedBox(height: 10),
          Text(_msg!, style: TextStyle(fontSize: 13,
              color: _msg!.contains('Guardado') ? success : brand, fontWeight: FontWeight.w500)),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
        ),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  const _Field({required this.ctrl, required this.label, required this.icon, this.keyboardType});
  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: label,
          prefixIcon: Icon(icon, color: muted, size: 20),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: child,
      );
}

class _VisualCard extends StatelessWidget {
  final Business biz;
  final String name, token;
  final int stamps, maxStamps;
  const _VisualCard({required this.biz, required this.name, required this.token,
      required this.stamps, required this.maxStamps});

  @override
  Widget build(BuildContext context) {
    final txt = biz.cardTextColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: biz.cardBg,
        gradient: biz.cardBg == null ? cardGradient : null,
        // Foto de fondo con velo oscuro para que el texto siga siendo legible
        image: biz.cardBgImage.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(biz.cardBgImage),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.45), BlendMode.darken),
                onError: (_, __) {}, // foto caída → queda el color/gradiente de fondo
              )
            : null,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF111528).withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(biz.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: txt, fontSize: 18, fontWeight: FontWeight.w700)),
            if (biz.tagline.isNotEmpty)
              Text(biz.tagline, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: txt.withValues(alpha: 0.7), fontSize: 12)),
            if (name.isNotEmpty)
              Text('Hola, $name', style: TextStyle(color: txt.withValues(alpha: 0.6), fontSize: 13)),
          ])),
          if (biz.logoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(biz.logoUrl, width: 42, height: 42, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.loyalty, color: biz.primaryColor, size: 26)),
            )
          else
            Icon(Icons.loyalty, color: biz.primaryColor, size: 26),
        ]),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: QrImageView(data: token, size: 180),
        ),
        const SizedBox(height: 14),
        Text('Muestra este código en el local para sellar',
            textAlign: TextAlign.center, style: TextStyle(color: txt.withValues(alpha: 0.7), fontSize: 12)),
      ]),
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
      child: Row(children: [
        Icon(Icons.timer_outlined, size: 18, color: expired ? brand : success),
        const SizedBox(width: 8),
        Expanded(child: Text(
          expired ? 'Ciclo vencido — se reiniciará con el próximo sello'
              : days == 0 ? 'El ciclo vence hoy'
              : 'Ciclo vence en $days día${days == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 13, color: expired ? brand : success, fontWeight: FontWeight.w500),
        )),
      ]),
    );
  }
}

class _StampGrid extends StatelessWidget {
  final int stamps, maxStamps;
  final List<RewardTier> tiers;
  final Color color;
  const _StampGrid({required this.stamps, required this.maxStamps, required this.tiers, required this.color});

  @override
  Widget build(BuildContext context) {
    final tierSet = tiers.map((t) => t.stampsRequired).toSet();
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: List.generate(maxStamps, (i) {
        final pos = i + 1;
        final on = pos <= stamps;
        final isTier = tierSet.contains(pos);
        return Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? color : const Color(0xFFF1F5F9),
            border: Border.all(color: isTier ? color : (on ? color : line), width: isTier ? 2.5 : 1.5),
          ),
          child: Icon(
            isTier ? (on ? Icons.star_rounded : Icons.star_outline_rounded) : (on ? Icons.circle : Icons.circle_outlined),
            color: on ? Colors.white : (isTier ? color.withValues(alpha: 0.4) : const Color(0xFFCBD5E1)),
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
  final Color color;
  const _RewardList({required this.tiers, required this.stamps, required this.color});

  @override
  Widget build(BuildContext context) {
    if (tiers.isEmpty) return const SizedBox.shrink();
    return _WhiteCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Recompensas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...tiers.map((t) {
          final earned = stamps >= t.stampsRequired;
          final remaining = t.stampsRequired - stamps;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: earned ? success.withValues(alpha: 0.12) : color.withValues(alpha: 0.08),
                ),
                child: Icon(earned ? Icons.check_circle_rounded : Icons.workspace_premium_outlined,
                    color: earned ? success : color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.description, style: TextStyle(fontWeight: FontWeight.w600, color: earned ? success : ink)),
                Text(earned ? 'Ganado' : 'Faltan $remaining sello${remaining == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: earned ? success : muted)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: earned ? success.withValues(alpha: 0.1) : color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${t.stampsRequired} ★',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: earned ? success : color)),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

class _TiersManager extends StatelessWidget {
  final List<RewardTier> tiers;
  final VoidCallback onAdd;
  final void Function(RewardTier) onEdit;
  final void Function(RewardTier) onDelete;
  const _TiersManager({required this.tiers, required this.onAdd, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Recompensas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Agregar'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
          ),
        ]),
        if (tiers.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Sin recompensas configuradas', style: TextStyle(color: muted)))
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
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: muted), onPressed: () => onEdit(t)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 20, color: brand), onPressed: () => onDelete(t)),
                ]),
              )),
        ],
      ]),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _KpiGrid({required this.stats});
  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: 1.6, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        children: [
          _KpiCard('Clientes',     '${stats['customers']}', Icons.people_outline),
          _KpiCard('Visitas',      '${stats['visits']}',    Icons.loyalty),
          _KpiCard('Premios dados','${stats['rewards']}',   Icons.workspace_premium_outlined),
          _KpiCard('Nuevos hoy',   '${stats['new_today']}', Icons.person_add_outlined),
        ],
      );
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _KpiCard(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, color: brand, size: 22),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
            Text(label, style: const TextStyle(fontSize: 11, color: muted)),
          ]),
        ]),
      );
}

class _ActivityChart extends StatelessWidget {
  final List<Map> daily;
  const _ActivityChart({required this.daily});
  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final maxN = daily.map((d) => d['n'] as int).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Actividad (14 días)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: daily.map((d) {
              final n = d['n'] as int;
              final frac = maxN > 0 ? n / maxN : 0.0;
              final date = (d['d'] as String).substring(5);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (n > 0) Text('$n', style: const TextStyle(fontSize: 9, color: muted)),
                    const SizedBox(height: 2),
                    FractionallySizedBox(
                      heightFactor: frac < 0.05 ? 0.05 : frac,
                      child: Container(decoration: BoxDecoration(
                          color: brand.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4))),
                    ),
                    const SizedBox(height: 4),
                    Text(date, style: const TextStyle(fontSize: 8, color: muted)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
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
    final q = search.toLowerCase();
    final filtered = search.isEmpty
        ? customers
        : customers.where((c) =>
            (c['name'] as String).toLowerCase().contains(q) ||
            (c['phone'] as String).contains(q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Clientes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      TextField(
        onChanged: onSearch,
        decoration: const InputDecoration(hintText: 'Buscar por nombre o teléfono',
            prefixIcon: Icon(Icons.search, color: muted)),
      ),
      const SizedBox(height: 10),
      ...filtered.map((c) => _CustomerTile(c: c)),
    ]);
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
      child: Row(children: [
        CircleAvatar(
          backgroundColor: brand.withValues(alpha: 0.12), radius: 20,
          child: Text(
            (c['name'] as String).isNotEmpty ? (c['name'] as String)[0].toUpperCase() : '?',
            style: TextStyle(color: brand, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text(c['phone'] ?? '', style: const TextStyle(color: muted, fontSize: 12)),
        ])),
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
      ]),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: brand.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.error_outline, color: brand, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: brand, fontSize: 13))),
        ]),
      );
}
