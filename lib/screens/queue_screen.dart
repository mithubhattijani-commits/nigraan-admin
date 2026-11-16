import 'dart:async';

import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Queue tab (ADMIN_APP_SPEC.md §7) — mirrors the web panel's queue
/// section (working-site/admin/index.html ~line 2746).
///
/// `AdminApi.queueList()` returns the newest 50 items, newest first.
/// The Worker only returns a payload for `ticker` and `app-config`
/// items (and a bare {id, title} for `article`); `change-password` and
/// `homepage-refresh` items carry no payload, so every summary falls
/// back to a static label and never crashes on missing fields.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});
  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;
  bool _refreshing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh every 30s while this tab is visible.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await AdminApi.instance.queueList();
      final raw = (data['items'] as List? ?? const []);
      final items = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() {
        _error = 'Session khatam — dobara login karein';
        _loading = false;
      });
      if (_items.isNotEmpty) showMsg(context, _error!, error: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      if (_items.isNotEmpty) showMsg(context, _error!, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Load nahi ho saka — internet check karein';
        _loading = false;
      });
      if (_items.isNotEmpty) showMsg(context, _error!, error: true);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _retry(String id) async {
    try {
      await AdminApi.instance.queueRetry(id);
      if (mounted) showMsg(context, 'Retry queued — dobara koshish ki ja rahi hai');
    } on UnauthorizedException {
      if (mounted) showMsg(context, 'Session khatam — dobara login karein', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Retry nahi ho saka', error: true);
    }
    await _load(silent: true);
  }

  Future<void> _delete(String id) async {
    final ok = await confirmDialog(
      context,
      'Delete queue item?',
      'Ye queue item delete kar dein? (Yeh queue item حذف کر دیں؟)',
    );
    if (!ok) return;
    try {
      await AdminApi.instance.queueDelete(id);
      if (mounted) showMsg(context, 'Deleted — حذف کر دیا گیا');
    } on UnauthorizedException {
      if (mounted) showMsg(context, 'Session khatam — dobara login karein', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'Delete nahi ho saka', error: true);
    }
    await _load(silent: true);
  }

  /// One-line summary by type, exactly as the panel renders it.
  /// Every field is optional — the Worker strips most payloads.
  String _summary(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString();
    final payload = item['payload'];
    final p = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    switch (type) {
      case 'article': {
        // Panel shape: payload {action, article: {id, title}}.
        // Worker shape: payload {id, title} (both may be missing).
        final article = p['article'];
        final a = article is Map ? Map<String, dynamic>.from(article) : <String, dynamic>{};
        final action = (p['action'] ?? '').toString();
        final id = (a['id'] ?? p['id'] ?? '').toString();
        final title = (a['title'] ?? p['title'] ?? '').toString();
        final parts = <String>[
          if (action.isNotEmpty) action,
          if (id.isNotEmpty) id,
          if (title.isNotEmpty) title,
        ];
        return parts.isEmpty ? 'article' : parts.join(' — ');
      }
      case 'ticker': {
        final items = p['items'];
        final n = items is List ? items.length : 0;
        return '$n items — $n خبریں';
      }
      case 'app-config': {
        final app = (p['app'] ?? '').toString();
        return app.isEmpty ? 'app config' : app;
      }
      case 'change-password':
        return 'password change — پاس ورڈ تبدیلی';
      case 'homepage-refresh':
        return 'refresh — ہوم پیج ریفریش';
      default:
        return type.isEmpty ? 'queue item' : type;
    }
  }

  String _created(Map<String, dynamic> item) {
    final raw = (item['created'] ?? '').toString();
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  Widget _badge(String status) {
    final s = status.toLowerCase();
    final Color color;
    final String label;
    switch (s) {
      case 'pending':
        color = Colors.orange;
        label = 'Pending — زیرِ التوا';
      case 'failed':
        color = const Color(0xFFEF0017);
        label = 'Failed — ناکام';
      case 'done':
        color = Colors.green;
        label = 'Done — مکمل';
      default:
        color = Colors.grey;
        label = status.isEmpty ? '—' : status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: () => _load());
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Queue is empty — قطار خالی ہے')),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'All changes sent to the queue appear here. Every 5 minutes the sync job applies them to the website. — قطار میں بھیجی گئی تمام تبدیلیاں یہاں نظر آتی ہیں۔',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  );
                }
                final item = _items[index - 1];
                final status = (item['status'] ?? '').toString();
                // Panel rule: Retry/Delete only for pending or failed
                // (the Worker rejects deleting done items).
                final canAct = status == 'pending' || status == 'failed';
                final id = (item['id'] ?? '').toString();
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (item['type'] ?? '').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            _badge(status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _summary(item),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [if (id.isNotEmpty) id, _created(item)]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                        if (canAct) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry — دوبارہ کوشش کریں'),
                                onPressed: id.isEmpty ? null : () => _retry(id),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text('Delete — حذف کریں'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFEF0017),
                                ),
                                onPressed: id.isEmpty ? null : () => _delete(id),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
