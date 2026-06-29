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
    brand = _cfg.primaryColor; // aplica color antes de construir el tema
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

/// Decide pantalla inicial: si ya hay tarjeta guardada, muéstrala.
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
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    // Validación local: evita un viaje al servidor por errores obvios.
    if (name.isEmpty) return setState(() => _error = 'Escribe tu nombre.');
    if (phone.length != 10) {
      return setState(() => _error = 'El WhatsApp debe tener 10 dígitos.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await Api.join(phone, name);
      final p = await SharedPreferences.getInstance();
      await p.setString('token', token);
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => CardScreen(token: token)));
      }
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
                Text(_biz,
                    textAlign: TextAlign.center,
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
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.card_membership),
                        label: Text(_busy ? 'Creando...' : 'Crear mi tarjeta'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ScannerScreen())),
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
    if (state == AppLifecycleState.resumed) _load(); // refresca tras sellar
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
    final int goal = d['goal'], stamps = d['stamps'], rewards = d['rewards'];
    final faltan = goal - stamps;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _LoyaltyCard(
                business: d['business'],
                name: d['name'] ?? '',
                token: widget.token,
                stamps: stamps,
                goal: goal,
              ),
              const SizedBox(height: 20),
              _WhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tus sellos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    // Dato protagonista (exaggerated minimalism).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('$stamps',
                            style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                letterSpacing: -2,
                                color: brand)),
                        Text(' / $goal',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w600, color: muted)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _StampGrid(stamps: stamps, goal: goal),
                    const SizedBox(height: 16),
                    Text(
                      faltan > 0
                          ? 'Te falta${faltan == 1 ? '' : 'n'} $faltan sello${faltan == 1 ? '' : 's'} para tu premio.'
                          : '¡Tarjeta completa!',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _RewardBanner(rewards: rewards, rewardText: d['reward_text']),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  String? _pass;
  String _result = '';
  bool _ok = true;
  bool _busy = false; // pausa entre escaneos

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
      setState(() {
        _ok = true;
        _result = d['earned'] == true ? '¡Premio ganado!' : 'Sello ${d['stamps']}/${d['goal']}';
      });
    } catch (e) {
      if (e == 'Clave incorrecta') {
        final p = await SharedPreferences.getInstance();
        await p.remove('staffPass');
        _pass = null;
      }
      setState(() {
        _ok = false;
        _result = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          // Marco guía para apuntar al QR.
          if (!_busy) ...[
            Container(
              width: 240,
              height: 240,
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
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _ok ? Icons.check_circle : Icons.error_outline,
                    color: _ok ? success : brand,
                    size: 72,
                  ),
                  const SizedBox(height: 16),
                  Text(_result,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      _busy = false;
                      _result = '';
                    }),
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

// ---------- Widgets reutilizables ----------

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: brand,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: brand.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: _cfg.logoUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(_cfg.logoUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.loyalty, color: Colors.white, size: 38)),
            )
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}

class _LoyaltyCard extends StatelessWidget {
  final String business, name, token;
  final int stamps, goal;
  const _LoyaltyCard({
    required this.business,
    required this.name,
    required this.token,
    required this.stamps,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF111528).withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12)),
        ],
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
                    Text(business,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    if (name.isNotEmpty)
                      Text('Hola, $name',
                          style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.loyalty, color: brand, size: 26),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration:
                BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Semantics(
              label: 'Código QR de tu tarjeta de lealtad',
              image: true,
              child: QrImageView(data: token, size: 180),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Muestra este código en el local para sellar',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StampGrid extends StatelessWidget {
  final int stamps, goal;
  const _StampGrid({required this.stamps, required this.goal});
  @override
  Widget build(BuildContext context) {
    // Respeta "reducir movimiento" del sistema (accesibilidad).
    final noMotion = MediaQuery.of(context).disableAnimations;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(goal, (i) {
        final on = i < stamps;
        return AnimatedContainer(
          duration: Duration(milliseconds: noMotion ? 0 : 250),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? brand : const Color(0xFFF1F5F9),
            border: Border.all(color: on ? brand : line, width: 1.5),
          ),
          child: Icon(
            on ? Icons.star_rounded : Icons.star_outline_rounded,
            color: on ? Colors.white : const Color(0xFFCBD5E1),
            size: 26,
          ),
        );
      }),
    );
  }
}

class _RewardBanner extends StatelessWidget {
  final int rewards;
  final String rewardText;
  const _RewardBanner({required this.rewards, required this.rewardText});
  @override
  Widget build(BuildContext context) {
    final earned = rewards > 0;
    final bg = earned ? success.withValues(alpha: 0.10) : brand.withValues(alpha: 0.08);
    final fg = earned ? success : brand;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(earned ? Icons.celebration_rounded : Icons.workspace_premium_outlined,
              color: fg, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  earned ? 'Premio listo para canjear' : 'Tu premio',
                  style: TextStyle(fontWeight: FontWeight.w700, color: fg),
                ),
                const SizedBox(height: 2),
                Text(
                  earned ? '$rewardText  ·  Ganados: $rewards' : rewardText,
                  style: const TextStyle(color: ink, fontSize: 13),
                ),
              ],
            ),
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
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
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

// ─── Panel del dueño ────────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  final String pass;
  const AdminScreen({super.key, required this.pass});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _stats;
  List<dynamic>? _customers;
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
      ]);
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _customers = results[1] as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text(_cfg.business),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
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

class _KpiGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _KpiGrid({required this.stats});
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _KpiCard('Clientes', '${stats['customers']}', Icons.people_outline),
        _KpiCard('Visitas totales', '${stats['visits']}', Icons.loyalty),
        _KpiCard('Premios dados', '${stats['rewards']}', Icons.workspace_premium_outlined),
        _KpiCard('Nuevos hoy', '${stats['new_today']}', Icons.person_add_outlined),
        _KpiCard('Casi listos', '${stats['near_reward']}', Icons.stars_outlined),
        _KpiCard('Sellos activos', '${stats['in_progress']}', Icons.pending_outlined),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: brand, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
              Text(label, style: const TextStyle(fontSize: 11, color: muted)),
            ],
          ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Actividad (14 días)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: daily.map((d) {
                final n = d['n'] as int;
                final frac = max > 0 ? n / max : 0.0;
                final date = (d['d'] as String).substring(5); // MM-DD
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (n > 0)
                          Text('$n', style: const TextStyle(fontSize: 9, color: muted)),
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
          decoration: const InputDecoration(
            hintText: 'Buscar por nombre o teléfono',
            prefixIcon: Icon(Icons.search, color: muted),
          ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(c['phone'] ?? '', style: const TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${c['stamps']} sellos', style: const TextStyle(fontSize: 12, color: muted)),
              Text('${c['rewards']} premios', style: const TextStyle(fontSize: 12, color: muted)),
            ],
          ),
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
