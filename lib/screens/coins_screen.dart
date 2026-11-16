import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Coins tab — mirrors the web admin panel's Coins section
/// (working-site/admin/index.html: sbHealth / findCoinUser / renderCoinUser
/// / adjustCoins).
///
/// Worker facts (admin-api/src/index.js):
///  * GET /api/sb/health -> {ok, connected, keyPresent}. `connected` is
///    true only when the Supabase service key is set AND reachable.
///  * GET /api/sb/user?user=`<id-or-email>` -> {ok, id, email, display_name,
///    balance, referral_code, pending_withdrawals, entries: [{id,
///    amount_coins, type, ref_id, provider, created_at}]}. 404 when the
///    user is not found.
///  * POST /api/sb/coins/adjust {user, amount, note} — amount must be a
///    non-zero integer with |amount| <= 1,000,000; note defaults to
///    'manual'. Returns {ok, user_id, display_name, email, amount,
///    balance} (the Dart client discards the body, so the new balance is
///    read back with a fresh lookup after a successful adjust).
class CoinsScreen extends StatefulWidget {
  const CoinsScreen({super.key});
  @override
  State<CoinsScreen> createState() => _CoinsScreenState();
}

class _CoinsScreenState extends State<CoinsScreen> {
  // ---- health ----
  bool? _connected;
  String? _healthError;
  bool _healthBusy = false;

  // ---- lookup ----
  final TextEditingController _lookupCtrl = TextEditingController();
  Map<String, dynamic>? _user;
  String? _lookupError;
  bool _lookupBusy = false;

  // ---- adjust ----
  final TextEditingController _adjustUserCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _adjustBusy = false;

  @override
  void initState() {
    super.initState();
    _loadHealth();
  }

  @override
  void dispose() {
    _lookupCtrl.dispose();
    _adjustUserCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHealth() async {
    setState(() {
      _healthBusy = true;
      _healthError = null;
    });
    try {
      final data = await AdminApi.instance.sbHealth();
      _connected = data['connected'] == true;
    } on UnauthorizedException {
      _healthError = 'Session khatam — dobara login karein';
    } on ApiException catch (e) {
      _healthError = e.message;
    } catch (_) {
      _healthError = 'Load nahi ho saka — internet check karein';
    } finally {
      if (mounted) setState(() => _healthBusy = false);
    }
  }

  Future<void> _findUser([String? who]) async {
    final input = (who ?? _lookupCtrl.text).trim();
    if (input.isEmpty) {
      showMsg(context, 'Enter a user ID or email first, then Find user.',
          error: true);
      return;
    }
    setState(() {
      _lookupBusy = true;
      _lookupError = null;
    });
    try {
      final data = await AdminApi.instance.lookupUser(input);
      if (!mounted) return;
      setState(() {
        _user = data;
        // Prefill the adjust form with the looked-up user's id, like the
        // panel does (it adjusts by coinUser.id).
        _adjustUserCtrl.text = (data['id'] ?? input).toString();
      });
    } on UnauthorizedException {
      if (mounted) {
        setState(() => _lookupError =
            'Session khatam — dobara login karein');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _user = null;
          _lookupError = 'User not found: ${e.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _user = null;
          _lookupError = 'Load nahi ho saka — internet check karein';
        });
      }
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }
  }

  Future<void> _adjust() async {
    final user = _adjustUserCtrl.text.trim();
    if (user.isEmpty) {
      showMsg(context, 'Enter a user ID or email first.', error: true);
      return;
    }
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount == 0) {
      showMsg(context, 'Enter a non-zero coin amount.', error: true);
      return;
    }
    if (amount.abs() > 1000000) {
      showMsg(context, 'Amount must be up to 1,000,000 coins.',
          error: true);
      return;
    }
    final note = _noteCtrl.text.trim().isEmpty
        ? 'manual'
        : _noteCtrl.text.trim();
    final who = _displayName(_user, user);
    final ok = await confirmDialog(
      context,
      amount > 0 ? 'Add coins?' : 'Remove coins?',
      amount > 0
          ? 'Add $amount coins to $who?'
          : 'Remove ${amount.abs()} coins from $who?',
    );
    if (!ok || !mounted) return;
    setState(() => _adjustBusy = true);
    try {
      await AdminApi.instance
          .adjustCoins(user: user, amount: amount, note: note);
      // Read the new balance back (adjustCoins returns no body).
      Map<String, dynamic>? fresh;
      try {
        fresh = await AdminApi.instance.lookupUser(user);
      } catch (_) {
        fresh = null;
      }
      if (!mounted) return;
      if (fresh != null) {
        setState(() {
          _user = fresh;
          _lookupCtrl.text = user;
        });
        showMsg(context,
            'Done. New balance: ${(fresh['balance'] ?? '—')} coins.');
      } else {
        showMsg(context, 'Coins adjusted.');
      }
      _amountCtrl.clear();
      _noteCtrl.clear();
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Adjust nahi ho saka', error: true);
    } finally {
      if (mounted) setState(() => _adjustBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controlsDisabled = _connected == false;
    return RefreshIndicator(
      onRefresh: () async {
        await _loadHealth();
        if (_user != null) {
          await _findUser((_user!['id'] ?? _lookupCtrl.text).toString());
        }
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _healthSection(),
          SectionCard(
            title: 'User lookup',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _lookupCtrl,
                  enabled: !controlsDisabled,
                  decoration: const InputDecoration(
                    labelText: 'User (User ID / email)',
                    hintText: 'user@example.com or user ID',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _findUser(),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  icon: _lookupBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Find user'),
                  onPressed: (controlsDisabled || _lookupBusy)
                      ? null
                      : () => _findUser(),
                ),
                if (_lookupError != null) ...[
                  const SizedBox(height: 12),
                  ErrorView(
                      message: _lookupError!, onRetry: () => _findUser()),
                ],
                if (_user != null) ...[
                  const SizedBox(height: 12),
                  _userCard(_user!),
                ],
              ],
            ),
          ),
          SectionCard(
            title: 'Adjust coins (کوائنز شامل / نکالیں)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _adjustUserCtrl,
                  enabled: !controlsDisabled,
                  decoration: const InputDecoration(
                    labelText: 'User (User ID / email)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountCtrl,
                  enabled: !controlsDisabled,
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true),
                  decoration: const InputDecoration(
                    labelText:
                        'Amount of coins (positive = add, negative = remove)',
                    hintText: 'e.g. 500 or -200',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteCtrl,
                  enabled: !controlsDisabled,
                  decoration: const InputDecoration(
                    labelText: 'Note / reason',
                    hintText: 'e.g. bonus, correction, refund',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: _adjustBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.account_balance_wallet),
                  label: const Text('Adjust coins'),
                  onPressed: (controlsDisabled || _adjustBusy)
                      ? null
                      : _adjust,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Amount must be a non-zero whole number up to 1,000,000. 100 coins = 1 PKR.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthSection() {
    Widget child;
    if (_healthBusy && _healthError == null && _connected == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_healthError != null && _connected == null) {
      child = ErrorView(message: _healthError!, onRetry: _loadHealth);
    } else {
      final connected = _connected == true;
      child = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: connected ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: connected ? Colors.green.shade200 : Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(
              connected ? Icons.check_circle : Icons.warning_amber,
              color: connected ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                connected
                    ? 'Supabase connected — service key is in place.'
                    : 'Supabase not connected — service key missing. Coins controls stay disabled until the key is connected.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Check again',
              onPressed: _healthBusy ? null : _loadHealth,
            ),
          ],
        ),
      );
    }
    return SectionCard(title: 'Supabase status', child: child);
  }

  Widget _userCard(Map<String, dynamic> d) {
    final name = _displayName(d, null);
    final balance = (d['balance'] ?? '—').toString();
    final entries = (d['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$name — Balance: $balance coins',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if ((d['email'] ?? '').toString().isNotEmpty)
          Text((d['email'] ?? '').toString()),
        if ((d['referral_code'] ?? '').toString().isNotEmpty)
          Text('Referral code: ${d['referral_code']}'),
        Text('Pending withdrawals: ${d['pending_withdrawals'] ?? 0}'),
        const SizedBox(height: 12),
        const Text('Recent ledger entries',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (entries.isEmpty)
          const Text('No ledger entries yet.',
              style: TextStyle(color: Colors.black54))
        else
          for (final x in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      _signedAmount(x['amount_coins']),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: ((x['amount_coins'] as num?) ?? 0) < 0
                            ? Colors.red
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                  Expanded(child: Text((x['type'] ?? '-').toString())),
                  Text(_dateOf(x['created_at']),
                      style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
      ],
    );
  }

  /// Panel's display name: display_name, else email, else id.
  String _displayName(Map<String, dynamic>? d, String? fallback) {
    final name = (d?['display_name'] ?? '').toString();
    if (name.isNotEmpty) return name;
    final email = (d?['email'] ?? '').toString();
    if (email.isNotEmpty) return email;
    final id = (d?['id'] ?? '').toString();
    if (id.isNotEmpty) return id;
    return fallback ?? '-';
  }

  String _signedAmount(dynamic v) {
    final n = (v as num?)?.toInt();
    if (n == null) return (v ?? '-').toString();
    return n > 0 ? '+$n' : n.toString();
  }

  String _dateOf(dynamic v) {
    final s = (v ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}
