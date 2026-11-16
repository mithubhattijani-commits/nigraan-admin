// Agent Access tab (ADMIN_APP_SPEC.md §9) — user order 16 Nov ~09:10.
//
// A future agent connects with its OWN token (created here). It can NEVER
// read anything directly: each request becomes a PENDING item and the user
// taps Allow or Deny. Approval is ONE-TIME per request — no standing
// access, no "always allow". An approved request is consumed on first
// read. Every request + decision is audit-logged server-side.
//
// The full token is shown ONCE at creation (dialog + Copy button) and
// never again — afterwards only the last 4 characters are shown.
// The token value is never printed, logged, or stored on the phone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});
  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _audit = [];
  String? _error;
  bool _loading = true;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh every 15s while this tab is visible so a new
    // permission request appears without a manual pull.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AdminApi.instance.agents(),
        AdminApi.instance.agentRequests(status: 'pending'),
        AdminApi.instance.agentAudit(),
      ]);
      if (!mounted) return;
      setState(() {
        _agents = results[0];
        _pending = results[1];
        _audit = results[2];
        _error = null;
        _loading = false;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() {
        _error = 'Session khatam — dobara login karein';
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Load nahi ho saka — internet check karein';
        _loading = false;
      });
    }
  }

  Future<void> _createAgent() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showMsg(context, 'Agent ka naam likhein', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await AdminApi.instance.createAgent(name);
      final token = (data['token'] ?? '').toString();
      if (!mounted) return;
      _nameCtrl.clear();
      if (token.isEmpty) {
        showMsg(context, 'Token nahi mila — dobara koshish karein', error: true);
      } else {
        await _showTokenOnce(name, token);
      }
    } on UnauthorizedException {
      if (mounted) showMsg(context, 'Session khatam — dobara login karein', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Agent nahi ban saka', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load(silent: true);
  }

  /// Shows the token ONCE. It is never stored on the phone and never
  /// shown again — only the last 4 characters appear in the list.
  Future<void> _showTokenOnce(String name, String token) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text('Agent token — $name'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ye token sirf us agent ko dein — dobara nahi dikhega.',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF0017)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  token,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy token'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (c.mounted) {
                ScaffoldMessenger.of(c).showSnackBar(
                  const SnackBar(content: Text('Token copy ho gaya')),
                );
              }
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Samajh gaya'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(String id, String name) async {
    final ok = await confirmDialog(
      context,
      'Revoke agent?',
      '"$name" ka token khatam kar dein? Is ke baad ye agent koi maloomat nahi maang sakega.',
    );
    if (!ok) return;
    try {
      await AdminApi.instance.revokeAgent(id);
      if (mounted) showMsg(context, 'Agent revoked — ٹوکن ختم کر دیا گیا');
    } on UnauthorizedException {
      if (mounted) showMsg(context, 'Session khatam — dobara login karein', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Revoke nahi ho saka', error: true);
    }
    await _load(silent: true);
  }

  Future<void> _review(String id, String action, String scope) async {
    try {
      await AdminApi.instance.reviewAgentRequest(id, action);
      if (mounted) {
        showMsg(
          context,
          action == 'approve'
              ? 'Allow kar diya — aik dafa ke liye'
              : 'Deny kar diya',
        );
      }
    } on UnauthorizedException {
      if (mounted) showMsg(context, 'Session khatam — dobara login karein', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Jawab nahi ja saka', error: true);
    }
    await _load(silent: true);
  }

  /// Scope string → plain words, e.g. `vault:ID` → "Vault secret".
  String _scopeWords(String scope) {
    final i = scope.indexOf(':');
    final base = i < 0 ? scope : scope.substring(0, i);
    final arg = i < 0 ? '' : scope.substring(i + 1);
    switch (base) {
      case 'overview':
        return 'Website overview — ویب سائٹ کی حالت';
      case 'handover':
        return 'Daily handover — روزانہ کی تفصیل';
      case 'ticker':
        return 'Breaking ticker — بریکنگ ٹکر';
      case 'articles':
        return 'Articles list — خبروں کی فہرست';
      case 'article':
        return arg.isEmpty ? 'Full article' : 'Full article: $arg';
      case 'app-config':
        return arg.isEmpty ? 'App config' : 'App config: $arg';
      case 'queue':
        return 'Change queue — تبدیلیوں کی قطار';
      case 'sb-stats':
        return 'TJ Earn stats — اعداد و شمار';
      case 'sb-referrals':
        return 'Referrals list — ریفرل کی فہرست';
      case 'sb-withdrawals':
        return 'Withdrawals list — رقم نکلوانے کی فہرست';
      case 'sb-config':
        return 'TJ Earn reward config — انعام کی سیٹنگ';
      case 'doner-incharges':
        return 'Doner in-charges — ڈونر انچارج';
      case 'doner-office-bearers':
        return 'Doner office-bearers — عہدیداران';
      case 'doner-donors':
        return 'Donors list — ڈونرز کی فہرست';
      case 'vault':
        return arg.isEmpty ? 'Vault secret — خفیہ چیز' : 'Vault secret — $arg';
      default:
        return scope.isEmpty ? '—' : scope;
    }
  }

  String _when(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _actionWords(String action) {
    switch (action.toLowerCase()) {
      case 'request':
        return 'Request — درخواست';
      case 'approve':
        return 'Approved — منظور';
      case 'deny':
        return 'Denied — مسترد';
      case 'consumed':
        return 'Read — پڑھ لیا';
      case 'revoked':
        return 'Revoked — ٹوکن ختم';
      case 'agent-created':
        return 'Agent created — ایجنٹ بنایا';
      default:
        return action.isEmpty ? '—' : action;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _agents.isEmpty && _pending.isEmpty && _audit.isEmpty) {
      return ErrorView(message: _error!, onRetry: () => _load());
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Koi bhi naya agent is app se jud sakta hai — lekin har maloomat ke liye aap ki permission lazmi hai. Approval sirf aik dafa ke liye hoti hai, "always allow" ka option nahi hai.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          SectionCard(
            title: 'Connect a new agent — نیا ایجنٹ جوڑیں',
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Agent name',
                    hintText: 'e.g. Jaani 2, New Agent',
                  ),
                  onSubmitted: (_) => _createAgent(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create agent token'),
                    onPressed: _busy ? null : _createAgent,
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Connected agents — جڑے ہوئے ایجنٹ',
            child: _agents.isEmpty
                ? const Text('Koi agent connected nahi hai.',
                    style: TextStyle(color: Colors.black54))
                : Column(
                    children: _agents.map((a) {
                      final id = (a['id'] ?? '').toString();
                      final name = (a['name'] ?? '').toString();
                      final last4 = (a['token_last4'] ?? '').toString();
                      final revoked = a['revoked'] == true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.smart_toy_outlined,
                          color: revoked ? Colors.grey : const Color(0xFF3D5AFE),
                        ),
                        title: Text(name.isEmpty ? '—' : name),
                        subtitle: Text(
                          [
                            if (last4.isNotEmpty) 'Token …$last4',
                            'Created: ${_when((a['created_at'] ?? '').toString())}',
                            if ((a['last_used_at'] ?? '').toString().isNotEmpty)
                              'Last used: ${_when((a['last_used_at'] ?? '').toString())}',
                            if (revoked) 'REVOKED',
                          ].join('\n'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        isThreeLine: true,
                        trailing: revoked
                            ? null
                            : TextButton(
                                onPressed: id.isEmpty ? null : () => _revoke(id, name),
                                child: const Text('Revoke',
                                    style: TextStyle(color: Color(0xFFEF0017))),
                              ),
                      );
                    }).toList(),
                  ),
          ),
          SectionCard(
            title: 'Permission requests — اجازت کی درخواستیں',
            actions: [
              if (_pending.isNotEmpty)
                Chip(
                  label: Text('${_pending.length}'),
                  backgroundColor: const Color(0xFFEF0017),
                  labelStyle: const TextStyle(color: Colors.white),
                  padding: EdgeInsets.zero,
                ),
            ],
            child: _pending.isEmpty
                ? const Text('Koi pending request nahi hai.',
                    style: TextStyle(color: Colors.black54))
                : Column(
                    children: _pending.map((r) {
                      final id = (r['id'] ?? '').toString();
                      final agentName = (r['agent_name'] ?? '').toString();
                      final scope = (r['scope'] ?? '').toString();
                      final detail = (r['detail'] ?? '').toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                agentName.isEmpty ? 'Agent' : agentName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(_scopeWords(scope),
                                  style: const TextStyle(fontSize: 14)),
                              if (detail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Reason: $detail',
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.black54)),
                              ],
                              Text(
                                _when((r['created_at'] ?? '').toString()),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FilledButton.icon(
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Allow — اجازت دیں'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                    onPressed: id.isEmpty
                                        ? null
                                        : () => _review(id, 'approve', scope),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.close, size: 18),
                                    label: const Text('Deny — منع کریں'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFEF0017),
                                    ),
                                    onPressed: id.isEmpty
                                        ? null
                                        : () => _review(id, 'deny', scope),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          SectionCard(
            title: 'Access log — رسائی کا ریکارڈ',
            child: _audit.isEmpty
                ? const Text('Abhi tak koi record nahi hai.',
                    style: TextStyle(color: Colors.black54))
                : Column(
                    children: _audit.take(30).map((e) {
                      final action = (e['action'] ?? '').toString();
                      final agentName = (e['agent_name'] ?? '').toString();
                      final scope = (e['scope'] ?? '').toString();
                      final ts = e['ts'];
                      final when = ts is num
                          ? _when(DateTime.fromMillisecondsSinceEpoch(
                                  ts.toInt())
                              .toIso8601String())
                          : _when((e['created_at'] ?? '').toString());
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(_actionWords(action),
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          [
                            if (agentName.isNotEmpty) agentName,
                            if (scope.isNotEmpty) _scopeWords(scope),
                            if (when.isNotEmpty) when,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12),
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
