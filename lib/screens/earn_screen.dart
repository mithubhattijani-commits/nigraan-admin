import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// TJ Earn tab — mirrors the web admin panel's Earn section
/// (working-site/admin/index.html: loadEarn / loadEarnLists) plus the
/// reward-config editor (panel's Coins tab, REWARD_KEYS) extended to the
/// Worker's full EDITABLE_CONFIG set.
///
/// Worker facts (admin-api/src/index.js):
///  * GET /api/sb/stats -> {total_users, total_coins, pending_withdrawals,
///    pending_referrals, referral_total, referral_approved, referral_rejected}
///  * GET /api/sb/referrals?status= -> rows {id, referrer_id, referred_id,
///    referrer_name, referred_name, status, created_at}. No coins field:
///    approving credits referral_reward_coins to the referrer.
///  * GET /api/sb/withdrawals -> rows {id, user_id, user_name,
///    amount_coins, amount_pkr, rail, account_masked, status, created_at}.
///    NOTE: the Worker ignores the status query param and always lists
///    pending, so the status filter is applied client-side here.
///  * POST /api/sb/config requires `value` to be a STRING (<= 500 chars),
///    so every save sends the value as text.
class EarnScreen extends StatefulWidget {
  const EarnScreen({super.key});
  @override
  State<EarnScreen> createState() => _EarnScreenState();
}

const List<String> _kStatuses = ['pending', 'approved', 'rejected'];

/// The Worker's EDITABLE_CONFIG set, in the spec's order. Only these keys
/// are ever sent to setSbConfig — anything else is rejected by the Worker.
const List<String> _kConfigKeys = [
  'quiz_coins_per_correct',
  'quiz_questions_per_day',
  'daily_checkin_coins',
  'daily_reward_cap',
  'read_article_coins',
  'read_article_daily_cap',
  'read_min_dwell_seconds',
  'referral_reward_coins',
  'referral_l1_coins',
  'referral_l2_coins',
  'referral_l3plus_coins',
  'referral_milestone_5',
  'referral_milestone_10',
  'referral_milestone_25',
  'referral_daily_cap',
  'referral_eligibility_rule',
  'spin_daily_limit',
  'spin_rewards',
  'streak_bonus_7',
  'streak_bonus_14',
  'streak_bonus_21',
  'streak_bonus_30',
  'tool_use_coins',
  'tool_use_daily_cap',
  'tool_use_min_gap_seconds',
  'unity_reward_coins',
  'unity_reward_daily_cap',
  'onboarding_bonus',
  'max_pending_withdrawals',
];

/// Keys that are NOT plain integers: spin_rewards is a list of numbers,
/// referral_eligibility_rule is free text.
const Set<String> _kTextKeys = {'spin_rewards', 'referral_eligibility_rule'};

const Map<String, String> _kStatLabels = {
  'total_users': 'Users',
  'total_coins': 'Total coins',
  'pending_withdrawals': 'Pending withdrawals',
  'pending_referrals': 'Pending referrals',
  'referral_total': 'Referrals (total)',
  'referral_approved': 'Referrals approved',
  'referral_rejected': 'Referrals rejected',
};

class _EarnScreenState extends State<EarnScreen> {
  // ---- stats ----
  Map<String, dynamic>? _stats;
  String? _statsError;
  bool _statsBusy = false;

  // ---- referrals ----
  String _refStatus = 'pending';
  List<Map<String, dynamic>> _referrals = [];
  String? _refError;
  bool _refBusy = false;

  // ---- withdrawals ----
  String _wdStatus = 'pending';
  List<Map<String, dynamic>> _withdrawals = [];
  String? _wdError;
  bool _wdBusy = false;

  // ---- reward config ----
  Map<String, dynamic>? _config;
  String? _configError;
  bool _configBusy = false;
  final Map<String, TextEditingController> _cfgCtrls = {};
  final Map<String, String> _cfgOrig = {};
  String? _savingKey;
  bool _savingAll = false;

  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in _cfgCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadStats(),
      _loadReferrals(),
      _loadWithdrawals(),
      _loadConfig(),
    ]);
  }

  // ---------- stats ----------

  Future<void> _loadStats() async {
    setState(() {
      _statsBusy = true;
      _statsError = null;
    });
    try {
      _stats = await AdminApi.instance.sbStats();
    } on UnauthorizedException {
      _statsError = 'Session khatam — dobara login karein';
    } on ApiException catch (e) {
      _statsError = e.message;
    } catch (_) {
      _statsError = 'Load nahi ho saka — internet check karein';
    } finally {
      if (mounted) setState(() => _statsBusy = false);
    }
  }

  // ---------- referrals ----------

  Future<void> _loadReferrals() async {
    setState(() {
      _refBusy = true;
      _refError = null;
    });
    try {
      final rows = await AdminApi.instance.referrals(status: _refStatus);
      _referrals = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on UnauthorizedException {
      _refError = 'Session khatam — dobara login karein';
    } on ApiException catch (e) {
      _refError = e.message;
    } catch (_) {
      _refError = 'Load nahi ho saka — internet check karein';
    } finally {
      if (mounted) setState(() => _refBusy = false);
    }
  }

  // ---------- withdrawals ----------

  Future<void> _loadWithdrawals() async {
    setState(() {
      _wdBusy = true;
      _wdError = null;
    });
    try {
      final rows = await AdminApi.instance.withdrawals(status: _wdStatus);
      final all = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      // The Worker ignores the status param and always returns pending
      // rows, so filter client-side for the approved/rejected views.
      _withdrawals = _wdStatus == 'pending'
          ? all
          : all
              .where((w) => (w['status'] ?? '').toString() == _wdStatus)
              .toList();
    } on UnauthorizedException {
      _wdError = 'Session khatam — dobara login karein';
    } on ApiException catch (e) {
      _wdError = e.message;
    } catch (_) {
      _wdError = 'Load nahi ho saka — internet check karein';
    } finally {
      if (mounted) setState(() => _wdBusy = false);
    }
  }

  // ---------- reward config ----------

  Future<void> _loadConfig() async {
    setState(() {
      _configBusy = true;
      _configError = null;
    });
    try {
      final data = await AdminApi.instance.sbConfig();
      final cfg = (data['config'] as Map? ?? const {});
      _config = Map<String, dynamic>.from(cfg);
      _initCfgControllers();
    } on UnauthorizedException {
      _configError = 'Session khatam — dobara login karein';
    } on ApiException catch (e) {
      _configError = e.message;
    } catch (_) {
      _configError = 'Load nahi ho saka — internet check karein';
    } finally {
      if (mounted) setState(() => _configBusy = false);
    }
  }

  void _initCfgControllers() {
    for (final c in _cfgCtrls.values) {
      c.dispose();
    }
    _cfgCtrls.clear();
    _cfgOrig.clear();
    for (final key in _kConfigKeys) {
      final text = _configDisplayValue(_config?[key]);
      _cfgOrig[key] = text;
      final ctrl = TextEditingController(text: text);
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
      _cfgCtrls[key] = ctrl;
    }
  }

  /// Render a stored config value as editable text. The Worker stores
  /// values as strings, but older rows may hold numbers or a JSON list.
  String _configDisplayValue(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num) return v.toString();
    if (v is List) return v.map((e) => e.toString()).join(', ');
    return v.toString();
  }

  bool _cfgDirty(String key) {
    final ctrl = _cfgCtrls[key];
    if (ctrl == null) return false;
    return ctrl.text.trim() != (_cfgOrig[key] ?? '');
  }

  bool get _anyCfgDirty => _kConfigKeys.any(_cfgDirty);

  /// Validate one key's text and return the string to save, or null after
  /// showing the problem.
  String? _validateCfgValue(String key, String raw) {
    final text = raw.trim();
    if (key == 'spin_rewards') {
      // List of numbers: accept "[10, 20, 50]" or "10, 20, 50" — saved
      // back as the raw text, exactly like the web panel does.
      final nums = _parseNumberList(text);
      if (nums == null) {
        showMsg(context,
            'spin_rewards: enter numbers separated by commas, e.g. 10, 20, 50',
            error: true);
        return null;
      }
      return text;
    }
    if (_kTextKeys.contains(key)) return text;
    final n = int.tryParse(text);
    if (n == null) {
      showMsg(context, '$key: enter a whole number', error: true);
      return null;
    }
    if (n < 0) {
      showMsg(context, '$key: value must be 0 or more', error: true);
      return null;
    }
    return n.toString();
  }

  List<int>? _parseNumberList(String text) {
    var t = text.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('[') && t.endsWith(']')) {
      t = t.substring(1, t.length - 1);
    }
    final parts = t.split(',');
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null || n < 0) return null;
      out.add(n);
    }
    return out.isEmpty ? null : out;
  }

  Future<bool> _saveCfgKey(String key) async {
    final ctrl = _cfgCtrls[key];
    if (ctrl == null) return false;
    final value = _validateCfgValue(key, ctrl.text);
    if (value == null) return false;
    setState(() => _savingKey = key);
    try {
      await AdminApi.instance.setSbConfig(key, value);
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
      return false;
    } on ApiException catch (e) {
      if (mounted) showMsg(context, '$key: ${e.message}', error: true);
      return false;
    } catch (_) {
      if (mounted) {
        showMsg(context, '$key: save nahi ho saka', error: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _savingKey = null);
    }
    _cfgOrig[key] = value;
    if (mounted) {
      setState(() {});
      showMsg(context, '$key saved.');
    }
    return true;
  }

  Future<void> _saveAllCfg() async {
    final dirty = _kConfigKeys.where(_cfgDirty).toList();
    if (dirty.isEmpty) {
      showMsg(context, 'Reward values saved.');
      return;
    }
    setState(() => _savingAll = true);
    var saved = 0;
    for (final key in dirty) {
      final ok = await _saveCfgKey(key);
      if (!ok) break;
      saved++;
    }
    if (mounted) {
      setState(() => _savingAll = false);
      if (saved == dirty.length) showMsg(context, 'Reward values saved.');
    }
  }

  // ---------- review actions ----------

  Future<void> _reviewReferral(
      Map<String, dynamic> r, String action, String reason) async {
    final id = (r['id'] ?? '').toString();
    if (id.isEmpty) return;
    final ok = await confirmDialog(
      context,
      action == 'approve' ? 'Approve referral?' : 'Reject referral?',
      action == 'approve'
          ? 'Approve this referral? The referrer will be credited.'
          : 'Reject this referral? No coins will be credited.',
    );
    if (!ok || !mounted) return;
    setState(() => _acting = true);
    try {
      await AdminApi.instance
          .reviewReferral(id, action, reason: reason.trim());
      if (!mounted) return;
      showMsg(context,
          action == 'approve' ? 'Referral approved.' : 'Referral rejected.');
      await _loadReferrals();
      await _loadStats();
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Action nahi ho saka', error: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reviewWithdrawal(
      Map<String, dynamic> w, String action, String txId) async {
    final id = (w['id'] ?? '').toString();
    if (id.isEmpty) return;
    if (action == 'approve' && txId.trim().isEmpty) {
      showMsg(context, 'Transaction ID is required to approve a withdrawal.',
          error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      action == 'approve' ? 'Approve withdrawal?' : 'Reject withdrawal?',
      action == 'approve'
          ? 'Approve this withdrawal? The coins will be debited from the user now.'
          : 'Reject this withdrawal? No coins will be taken.',
    );
    if (!ok || !mounted) return;
    setState(() => _acting = true);
    try {
      await AdminApi.instance
          .reviewWithdrawal(id, action, txId: txId.trim());
      if (!mounted) return;
      showMsg(
          context,
          action == 'approve'
              ? 'Withdrawal approved.'
              : 'Withdrawal rejected.');
      await _loadWithdrawals();
      await _loadStats();
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Action nahi ho saka', error: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  // ---------- detail dialogs ----------

  void _showReferralDetail(Map<String, dynamic> r) {
    final reasonCtrl = TextEditingController();
    final referrer =
        (r['referrer_name'] ?? r['referrer_id'] ?? '-').toString();
    final referred =
        (r['referred_name'] ?? r['referred_id'] ?? '-').toString();
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Referral detail'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Referrer', referrer),
              _detailRow('Referrer ID', (r['referrer_id'] ?? '-').toString()),
              _detailRow('Referred', referred),
              _detailRow('Referred ID', (r['referred_id'] ?? '-').toString()),
              _detailRow('Status', (r['status'] ?? '-').toString()),
              _detailRow('Date', _dateOf(r['created_at'])),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason for rejection (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Approving credits the referrer with the referral reward from the config below.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF0017)),
            onPressed: _acting
                ? null
                : () {
                    Navigator.of(c).pop();
                    _reviewReferral(r, 'reject', reasonCtrl.text);
                  },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: _acting
                ? null
                : () {
                    Navigator.of(c).pop();
                    _reviewReferral(r, 'approve', '');
                  },
            child: const Text('Approve'),
          ),
        ],
      ),
    ).whenComplete(reasonCtrl.dispose);
  }

  void _showWithdrawalDetail(Map<String, dynamic> w) {
    final txCtrl = TextEditingController();
    final coins = (w['amount_coins'] as num?)?.toInt();
    final pkr = w['amount_pkr'] as num? ??
        (coins != null ? coins / 100 : null);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Withdrawal detail'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('User', (w['user_name'] ?? w['user_id'] ?? '-').toString()),
              _detailRow('User ID', (w['user_id'] ?? '-').toString()),
              _detailRow(
                  'Amount', coins == null ? '-' : '$coins coins'),
              _detailRow('Amount (PKR)',
                  pkr == null ? '-' : '${_trimNum(pkr)} PKR'),
              _detailRow('Rail', (w['rail'] ?? '-').toString()),
              _detailRow('Account', (w['account_masked'] ?? '-').toString()),
              _detailRow('Status', (w['status'] ?? '-').toString()),
              _detailRow('Date', _dateOf(w['created_at'])),
              const SizedBox(height: 12),
              TextField(
                controller: txCtrl,
                decoration: const InputDecoration(
                  labelText: 'Transaction ID (approve ke liye zaroori)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Approving debits the coins from the user now.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF0017)),
            onPressed: _acting
                ? null
                : () {
                    Navigator.of(c).pop();
                    _reviewWithdrawal(w, 'reject', '');
                  },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: _acting
                ? null
                : () {
                    final tx = txCtrl.text;
                    Navigator.of(c).pop();
                    _reviewWithdrawal(w, 'approve', tx);
                  },
            child: const Text('Approve'),
          ),
        ],
      ),
    ).whenComplete(txCtrl.dispose);
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _statsSection(),
          _referralsSection(),
          _withdrawalsSection(),
          _configSection(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Reward values are enforced by the Supabase Edge Functions. Minimum withdrawal (10000 coins = 100 PKR) and the coin rate (100 coins = 1 PKR) are fixed in the app code, not here.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsSection() {
    Widget child;
    if (_statsBusy && _stats == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_statsError != null && _stats == null) {
      child = ErrorView(message: _statsError!, onRetry: _loadStats);
    } else {
      final s = _stats ?? {};
      // Known keys first, in panel order, then any extra keys the
      // server returns (tolerate any shape).
      final keys = <String>[
        for (final k in _kStatLabels.keys)
          if (s.containsKey(k)) k,
        for (final k in s.keys)
          if (k != 'ok' && !_kStatLabels.containsKey(k)) k,
      ];
      if (keys.isEmpty) {
        child = const Text('No stats available.');
      } else {
        child = Column(
          children: [
            for (final k in keys)
              _row(_kStatLabels[k] ?? _prettyKey(k),
                  (s[k] ?? '—').toString()),
          ],
        );
      }
    }
    return SectionCard(
      title: 'Overview',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _statsBusy ? null : _loadStats,
          tooltip: 'Refresh',
        ),
      ],
      child: child,
    );
  }

  Widget _referralsSection() {
    Widget child;
    if (_refBusy && _referrals.isEmpty && _refError == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_refError != null && _referrals.isEmpty) {
      child = ErrorView(message: _refError!, onRetry: _loadReferrals);
    } else if (_referrals.isEmpty) {
      child = Text(_refStatus == 'pending'
          ? 'Nothing pending.'
          : 'No $_refStatus referrals.');
    } else {
      child = Column(
        children: [
          for (final r in _referrals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${(r['referrer_name'] ?? r['referrer_id'] ?? '-')} → ${(r['referred_name'] ?? r['referred_id'] ?? '-')}',
              ),
              subtitle: Text(
                  '${(r['status'] ?? '-')} · ${_dateOf(r['created_at'])}'),
              trailing: _statusChip((r['status'] ?? '').toString()),
              onTap: () => _showReferralDetail(r),
            ),
        ],
      );
    }
    return SectionCard(
      title: 'Referrals (ریفرلز)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusFilter(
            value: _refStatus,
            onChanged: (v) {
              setState(() => _refStatus = v);
              _loadReferrals();
            },
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _withdrawalsSection() {
    Widget child;
    if (_wdBusy && _withdrawals.isEmpty && _wdError == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_wdError != null && _withdrawals.isEmpty) {
      child = ErrorView(message: _wdError!, onRetry: _loadWithdrawals);
    } else if (_withdrawals.isEmpty) {
      child = Text(_wdStatus == 'pending'
          ? 'Nothing pending.'
          : 'No $_wdStatus withdrawals.');
    } else {
      child = Column(
        children: [
          for (final w in _withdrawals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                  '${(w['user_name'] ?? w['user_id'] ?? '-')} · ${(w['amount_coins'] ?? '-')} coins'),
              subtitle: Text(_wdSubtitle(w)),
              trailing: _statusChip((w['status'] ?? '').toString()),
              onTap: () => _showWithdrawalDetail(w),
            ),
        ],
      );
    }
    return SectionCard(
      title: 'Withdrawals (واپسی)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusFilter(
            value: _wdStatus,
            onChanged: (v) {
              setState(() => _wdStatus = v);
              _loadWithdrawals();
            },
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _configSection() {
    Widget child;
    if (_configBusy && _config == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_configError != null && _config == null) {
      child = ErrorView(message: _configError!, onRetry: _loadConfig);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final key in _kConfigKeys) _configField(key),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: _savingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Save reward values'),
            onPressed:
                (_savingAll || !_anyCfgDirty) ? null : _saveAllCfg,
          ),
        ],
      );
    }
    return SectionCard(
      title: 'Reward values (انعامی اقدار)',
      child: child,
    );
  }

  Widget _configField(String key) {
    final ctrl = _cfgCtrls[key];
    if (ctrl == null) return const SizedBox.shrink();
    final dirty = _cfgDirty(key);
    final saving = _savingKey == key;
    final isList = key == 'spin_rewards';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: _kTextKeys.contains(key)
                  ? TextInputType.text
                  : TextInputType.number,
              decoration: InputDecoration(
                labelText: key,
                hintText: isList ? 'e.g. 10, 20, 50' : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 48,
            child: saving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.save,
                        color: dirty ? const Color(0xFF3D5AFE) : Colors.grey),
                    tooltip: 'Save $key',
                    onPressed: dirty ? () => _saveCfgKey(key) : null,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusFilter(
      {required String value, required ValueChanged<String> onChanged}) {
    return Wrap(
      spacing: 8,
      children: [
        for (final s in _kStatuses)
          ChoiceChip(
            label: Text(s[0].toUpperCase() + s.substring(1)),
            selected: value == s,
            selectedColor: const Color(0xFFEF0017),
            labelStyle: TextStyle(
                color: value == s ? Colors.white : Colors.black87),
            onSelected: (sel) {
              if (sel) onChanged(s);
            },
          ),
      ],
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      'eligible' => Colors.blue,
      _ => Colors.orange,
    };
    return Chip(
      label: Text(status,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(value)),
          ],
        ),
      );

  String _wdSubtitle(Map<String, dynamic> w) {
    final parts = <String>[
      _pkrText(w),
      (w['rail'] ?? '-').toString(),
      (w['account_masked'] ?? '').toString(),
      _dateOf(w['created_at']),
    ].where((p) => p.isNotEmpty).toList();
    return parts.join(' · ');
  }

  String _pkrText(Map<String, dynamic> w) {
    final coins = (w['amount_coins'] as num?)?.toInt();
    final pkr = w['amount_pkr'] as num? ?? (coins != null ? coins / 100 : null);
    return pkr == null ? '' : '${_trimNum(pkr)} PKR';
  }

  String _trimNum(num n) {
    if (n == n.truncateToDouble()) return n.truncate().toString();
    return n.toString();
  }

  String _dateOf(dynamic v) {
    final s = (v ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _prettyKey(String k) {
    if (k.isEmpty) return k;
    final s = k.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }
}
