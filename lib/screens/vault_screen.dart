import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Vault tab — server-encrypted secrets (Worker AES-GCM, VAULT_KEY),
/// gated locally by a 6-digit PIN that never leaves the phone.
///
/// PIN: SHA-256 hex of the PIN is stored in flutter_secure_storage
/// under 'vault_pin_hash'. 5 wrong tries -> 60s lockout (fail count +
/// lockout time also kept in secure storage so a restart does not
/// reset them). Optional biometric unlock via local_auth when the
/// device supports it.
///
/// Secrets list never shows values. Reveal calls AdminApi.vaultReveal
/// (server audit-logs every reveal) and shows the value once with a
/// Copy button; it auto-hides after 30s, on Hide, on lock, or when
/// this screen is disposed.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

const _kinds = <String>['api_key', 'password', 'token', 'other'];

enum _Gate { checking, setup, enter, locked, unlocked }

class _VaultScreenState extends State<VaultScreen> {
  final _api = AdminApi.instance;
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  static const _pinHashKey = 'vault_pin_hash';
  static const _failsKey = 'vault_pin_fails';
  static const _lockoutKey = 'vault_pin_lockout_until';
  static const _maxFails = 5;
  static const _lockoutSeconds = 60;
  static const _revealSeconds = 30;

  _Gate _gate = _Gate.checking;
  bool _biometricsAvailable = false;

  int _fails = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;
  int _lockoutSecondsLeft = 0;

  final _pinC = TextEditingController();
  final _pin1C = TextEditingController();
  final _pin2C = TextEditingController();
  String _gateError = '';
  bool _gateBusy = false;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _secrets = [];
  List<Map<String, dynamic>> _audit = [];
  String? _revealedId;
  String? _revealedValue;
  String? _revealingId;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    _initGate();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _revealTimer?.cancel();
    // Revealed values live only in memory; dropping them here means
    // nothing survives leaving the screen.
    _revealedValue = null;
    _revealedId = null;
    _pinC.dispose();
    _pin1C.dispose();
    _pin2C.dispose();
    super.dispose();
  }

  static String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static bool _isDigits(String s) =>
      s.isNotEmpty && s.codeUnits.every((c) => c >= 48 && c <= 57);

  static String _s(Map<String, dynamic> m, String key) =>
      (m[key] ?? '').toString();

  Future<void> _initGate() async {
    final hash = await _storage.read(key: _pinHashKey);
    final failsRaw = await _storage.read(key: _failsKey);
    final lockRaw = await _storage.read(key: _lockoutKey);
    _fails = int.tryParse(failsRaw ?? '') ?? 0;
    if (lockRaw != null) {
      final ms = int.tryParse(lockRaw);
      if (ms != null) {
        final until = DateTime.fromMillisecondsSinceEpoch(ms);
        if (until.isAfter(DateTime.now())) {
          _lockoutUntil = until;
        } else {
          await _storage.delete(key: _lockoutKey);
          await _storage.delete(key: _failsKey);
          _fails = 0;
        }
      }
    }
    var bio = false;
    try {
      if (await _auth.canCheckBiometrics && await _auth.isDeviceSupported()) {
        final available = await _auth.getAvailableBiometrics();
        bio = available.isNotEmpty;
      }
    } catch (_) {
      bio = false;
    }
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = bio;
      if (hash == null || hash.isEmpty) {
        _gate = _Gate.setup;
      } else if (_lockoutUntil != null) {
        _gate = _Gate.locked;
        _startLockoutTimer();
      } else {
        _gate = _Gate.enter;
      }
    });
  }

  // ---------- PIN gate ----------

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _updateLockoutLeft();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_lockoutUntil == null || !_lockoutUntil!.isAfter(DateTime.now())) {
        _lockoutTimer?.cancel();
        _lockoutUntil = null;
        _fails = 0;
        unawaited(_storage.delete(key: _failsKey));
        unawaited(_storage.delete(key: _lockoutKey));
        setState(() {
          _lockoutSecondsLeft = 0;
          _gate = _Gate.enter;
        });
      } else {
        setState(_updateLockoutLeft);
      }
    });
  }

  void _updateLockoutLeft() {
    if (_lockoutUntil == null) {
      _lockoutSecondsLeft = 0;
      return;
    }
    _lockoutSecondsLeft =
        _lockoutUntil!.difference(DateTime.now()).inSeconds + 1;
    if (_lockoutSecondsLeft < 0) _lockoutSecondsLeft = 0;
  }

  Future<void> _setPin() async {
    final p1 = _pin1C.text.trim();
    final p2 = _pin2C.text.trim();
    if (p1.length != 6 || !_isDigits(p1)) {
      setState(() => _gateError = 'PIN must be exactly 6 digits.');
      return;
    }
    if (p1 != p2) {
      setState(() => _gateError = 'PINs do not match — dobara likhein.');
      return;
    }
    setState(() {
      _gateBusy = true;
      _gateError = '';
    });
    await _storage.write(key: _pinHashKey, value: _sha256Hex(p1));
    _pin1C.clear();
    _pin2C.clear();
    if (!mounted) return;
    setState(() {
      _gateBusy = false;
      _gate = _Gate.unlocked;
    });
    await _loadAll();
  }

  Future<void> _submitPin() async {
    final pin = _pinC.text.trim();
    if (pin.length != 6 || !_isDigits(pin)) {
      setState(() => _gateError = 'Enter the 6-digit PIN.');
      return;
    }
    setState(() {
      _gateBusy = true;
      _gateError = '';
    });
    final stored = await _storage.read(key: _pinHashKey);
    if (!mounted) return;
    if (stored != null && stored == _sha256Hex(pin)) {
      _pinC.clear();
      _fails = 0;
      await _storage.delete(key: _failsKey);
      setState(() {
        _gateBusy = false;
        _gate = _Gate.unlocked;
      });
      await _loadAll();
      return;
    }
    _fails += 1;
    await _storage.write(key: _failsKey, value: _fails.toString());
    if (_fails >= _maxFails) {
      _lockoutUntil = DateTime.now().add(
        const Duration(seconds: _lockoutSeconds),
      );
      await _storage.write(
        key: _lockoutKey,
        value: _lockoutUntil!.millisecondsSinceEpoch.toString(),
      );
      if (!mounted) return;
      setState(() {
        _gateBusy = false;
        _gate = _Gate.locked;
        _gateError = '';
      });
      _startLockoutTimer();
    } else {
      setState(() {
        _gateBusy = false;
        _gateError = 'Wrong PIN — ${_maxFails - _fails} tries left.';
      });
    }
  }

  Future<void> _tryBiometric() async {
    setState(() {
      _gateBusy = true;
      _gateError = '';
    });
    var ok = false;
    try {
      ok = await _auth.authenticate(
        localizedReason: 'Unlock the Nigraan Vault',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      _pinC.clear();
      setState(() {
        _gateBusy = false;
        _gate = _Gate.unlocked;
      });
      await _loadAll();
    } else {
      setState(() {
        _gateBusy = false;
        _gateError = 'Biometric unlock failed — PIN use karein.';
      });
    }
  }

  void _lock() {
    _clearReveal();
    _pinC.clear();
    setState(() {
      _gate = _Gate.enter;
      _secrets = [];
      _audit = [];
      _error = null;
    });
  }

  // ---------- vault data ----------

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_api.vaultList(), _api.vaultAudit()]);
      if (!mounted) return;
      setState(() {
        _secrets = results[0].map((e) => Map<String, dynamic>.from(e)).toList();
        _audit = results[1].map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } on UnauthorizedException {
      if (mounted) {
        setState(() {
          _error = 'Session khatam — dobara login karein';
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Load nahi ho saka — internet check karein';
          _loading = false;
        });
      }
    }
  }

  void _clearReveal() {
    _revealTimer?.cancel();
    _revealedId = null;
    _revealedValue = null;
  }

  Future<void> _reveal(Map<String, dynamic> secret) async {
    final id = _s(secret, 'id');
    if (id.isEmpty) return;
    _clearReveal();
    setState(() => _revealingId = id);
    try {
      final value = await _api.vaultReveal(id);
      if (!mounted) return;
      setState(() {
        _revealingId = null;
        _revealedId = id;
        _revealedValue = value;
      });
      _revealTimer?.cancel();
      _revealTimer = Timer(const Duration(seconds: _revealSeconds), () {
        if (mounted) {
          setState(() {
            _revealedId = null;
            _revealedValue = null;
          });
        }
      });
    } on UnauthorizedException {
      if (mounted) {
        setState(() {
          _revealingId = null;
          _error = 'Session khatam — dobara login karein';
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _revealingId = null);
        showMsg(context, e.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _revealingId = null);
        showMsg(context, 'Reveal nahi ho saka', error: true);
      }
    }
  }

  Future<void> _deleteSecret(Map<String, dynamic> secret) async {
    final ok = await confirmDialog(
      context,
      'Delete secret?',
      'Delete "${_s(secret, 'name')}"? This cannot be undone.',
    );
    if (!ok || !mounted) return;
    try {
      await _api.vaultDelete(_s(secret, 'id'));
      if (!mounted) return;
      if (_revealedId == _s(secret, 'id')) _clearReveal();
      showMsg(context, 'Deleted.');
      await _loadAll();
    } on UnauthorizedException {
      if (mounted) {
        setState(() => _error = 'Session khatam — dobara login karein');
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Delete nahi ho saka', error: true);
    }
  }

  Future<void> _showAddSecret() async {
    final nameC = TextEditingController();
    final valueC = TextEditingController();
    var kind = 'api_key';
    var obscure = true;
    var saving = false;
    var formError = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Add secret'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Kind'),
                  items: _kinds
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) => setDialog(() => kind = v ?? 'other'),
                ),
                TextField(
                  controller: valueC,
                  obscureText: obscure,
                  maxLines: obscure ? 1 : 4,
                  decoration: InputDecoration(
                    labelText: 'Value *',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setDialog(() => obscure = !obscure),
                    ),
                  ),
                ),
                if (formError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      formError,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameC.text.trim();
                      final value = valueC.text;
                      if (name.isEmpty) {
                        setDialog(() => formError = 'Name is required.');
                        return;
                      }
                      if (value.isEmpty) {
                        setDialog(() => formError = 'Value is required.');
                        return;
                      }
                      setDialog(() {
                        saving = true;
                        formError = '';
                      });
                      try {
                        await _api.vaultAdd(
                          name: name,
                          kind: kind,
                          value: value,
                        );
                        if (!mounted) return;
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        showMsg(context, 'Saved.');
                        await _loadAll();
                      } on UnauthorizedException {
                        if (!mounted) return;
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        setState(
                          () => _error = 'Session khatam — dobara login karein',
                        );
                      } on ApiException catch (e) {
                        setDialog(() {
                          saving = false;
                          formError = e.message;
                        });
                      } catch (_) {
                        setDialog(() {
                          saving = false;
                          formError = 'Save nahi ho saka';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameC.dispose();
    valueC.dispose();
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    switch (_gate) {
      case _Gate.checking:
        return const Center(child: CircularProgressIndicator());
      case _Gate.setup:
        return _gateCard(
          title: 'Set Vault PIN',
          body:
              'Set a 6-digit PIN to protect this tab. The PIN never leaves '
              'this phone — it only unlocks the Vault here.',
          children: [
            _pinTextField(
              controller: _pin1C,
              label: 'New 6-digit PIN',
              onSubmitted: (_) => _setPin(),
            ),
            const SizedBox(height: 12),
            _pinTextField(
              controller: _pin2C,
              label: 'Confirm PIN',
              onSubmitted: (_) => _setPin(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _gateBusy ? null : _setPin,
                child: _gateBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Set PIN'),
              ),
            ),
          ],
        );
      case _Gate.enter:
        return _gateCard(
          title: 'Vault locked',
          body:
              'Enter your 6-digit Vault PIN to continue.'
              '${_fails > 0 ? ' (${_maxFails - _fails} tries left before a 60s lockout.)' : ''}',
          children: [
            _pinTextField(
              controller: _pinC,
              label: '6-digit PIN',
              autofocus: true,
              onSubmitted: (_) => _submitPin(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _gateBusy ? null : _submitPin,
                child: _gateBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unlock'),
              ),
            ),
            if (_biometricsAvailable) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock with biometrics'),
                  onPressed: _gateBusy ? null : _tryBiometric,
                ),
              ),
            ],
          ],
        );
      case _Gate.locked:
        return _gateCard(
          title: 'Vault locked',
          body:
              'Too many wrong PINs. Try again in '
              '$_lockoutSecondsLeft seconds.',
          children: const [
            Icon(Icons.lock_clock_outlined, size: 48, color: Color(0xFFEF0017)),
            SizedBox(height: 12),
            Text(
              '5 wrong tries lock the Vault for 60 seconds.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case _Gate.unlocked:
        return _buildUnlocked();
    }
  }

  Widget _gateCard({
    required String title,
    required String body,
    required List<Widget> children,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, color: Color(0xFFEF0017)),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(body, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 16),
                  ...children,
                  if (_gateError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _gateError,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinTextField({
    required TextEditingController controller,
    required String label,
    bool autofocus = false,
    required void Function(String) onSubmitted,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      onSubmitted: onSubmitted,
    );
  }

  Widget _buildUnlocked() {
    if (_loading && _secrets.isEmpty && _audit.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _loadAll);
    }
    final revealed = _revealedId == null
        ? null
        : _secrets.firstWhere(
            (s) => _s(s, 'id') == _revealedId,
            orElse: () => <String, dynamic>{},
          );
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        children: [
          SectionCard(
            title: 'Secrets',
            actions: [
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Lock vault',
                onPressed: _lock,
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: _showAddSecret,
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Values are never shown in this list — tap the eye '
                  'icon to reveal one secret at a time.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (_revealedId != null && _revealedValue != null)
                  _revealedCard(revealed),
                if (_secrets.isEmpty)
                  const Text(
                    'No secrets yet.',
                    style: TextStyle(color: Colors.black54),
                  )
                else
                  ..._secrets.map((s) {
                    final id = _s(s, 'id');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF3D5AFE),
                        foregroundColor: Colors.white,
                        child: Icon(_kindIcon(_s(s, 'kind'))),
                      ),
                      title: Text(_s(s, 'name')),
                      subtitle: Text(
                        '${_s(s, 'kind').isEmpty ? 'other' : _s(s, 'kind')}'
                        ' • ${_fmtIso(_s(s, 'created_at'))}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_revealingId == id)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.visibility_outlined),
                              tooltip: 'Reveal (logged)',
                              onPressed: () => _reveal(s),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFEF0017),
                            ),
                            tooltip: 'Delete',
                            onPressed: () => _deleteSecret(s),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          SectionCard(
            title: 'Audit log — newest first',
            child: _audit.isEmpty
                ? const Text(
                    'No audit entries yet.',
                    style: TextStyle(color: Colors.black54),
                  )
                : Column(
                    children: _audit.map((e) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_outlined),
                        title: Text(
                          '${_actionLabel(_s(e, 'action'))} — ${_s(e, 'secret_name')}',
                        ),
                        subtitle: Text(_fmtTs(e['ts'])),
                      );
                    }).toList(),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'The PIN is stored only on this phone and never sent to the '
              'server. Every reveal is recorded in the audit log.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _revealedCard(Map<String, dynamic>? secret) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEF0017)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.red.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _s(secret ?? {}, 'name'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _revealedValue ?? '',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _revealedValue ?? ''));
                  showMsg(context, 'Copied.');
                },
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(_clearReveal),
                child: const Text('Hide'),
              ),
            ],
          ),
          const Text(
            'Har dafa dekhne ka record banta hai. Value 30 seconds '
            'mein khud chhup jayegi.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case 'api_key':
        return Icons.key_outlined;
      case 'password':
        return Icons.password_outlined;
      case 'token':
        return Icons.confirmation_number_outlined;
      default:
        return Icons.lock_outline;
    }
  }

  static String _actionLabel(String action) {
    switch (action) {
      case 'store':
        return 'Stored';
      case 'reveal':
        return 'Revealed';
      case 'delete':
        return 'Deleted';
      default:
        return action.isEmpty ? '—' : action;
    }
  }

  static String _fmtIso(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  static String _fmtTs(dynamic ts) {
    if (ts is num) {
      return _fmtIso(
        DateTime.fromMillisecondsSinceEpoch(ts.toInt()).toIso8601String(),
      );
    }
    if (ts is String) {
      final n = int.tryParse(ts);
      if (n != null) return _fmtTs(n);
      return _fmtIso(ts);
    }
    return '-';
  }
}
