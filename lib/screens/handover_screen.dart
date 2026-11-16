// Handover tab (ADMIN_APP_SPEC.md §10) — user order 16 Nov ~09:12.
//
// A rolling DAILY briefing document so a new agent never has to be taught
// anything again. Stored server-side (Worker KV `handover:current`) and
// rewritten every day at 21:30 PKT by the daily-handover job; each new day
// REPLACES the old document — yesterday's copy is deleted by design.
// The document always holds: today's work, tomorrow's plan, every cron,
// every version, open items, standing rules.
//
// Read-only in the app for v1 (the daily job writes it).
import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

class HandoverScreen extends StatefulWidget {
  const HandoverScreen({super.key});
  @override
  State<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends State<HandoverScreen> {
  Map<String, dynamic>? _doc;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await AdminApi.instance.handover();
      if (!mounted) return;
      setState(() {
        _doc = data;
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

  String _when(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// Simple markdown-ish rendering: "# " / "## " lines become bold
  /// headings, "- " lines become bullets, everything else plain text.
  /// One SelectableText.rich so the whole document stays copyable.
  List<TextSpan> _spans(String content) {
    const base = TextStyle(fontSize: 14, height: 1.5, color: Colors.black87);
    final spans = <TextSpan>[];
    for (final line in content.split('\n')) {
      final t = line.trimRight();
      if (t.startsWith('## ')) {
        spans.add(TextSpan(
          text: '${t.substring(3)}\n',
          style: base.copyWith(fontSize: 17, fontWeight: FontWeight.bold),
        ));
      } else if (t.startsWith('# ')) {
        spans.add(TextSpan(
          text: '${t.substring(2)}\n',
          style: base.copyWith(fontSize: 19, fontWeight: FontWeight.bold),
        ));
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        spans.add(TextSpan(text: '• ${t.substring(2)}\n', style: base));
      } else {
        spans.add(TextSpan(text: '$t\n', style: base));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final available = _doc?['available'] == true;
    if (!available) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Abhi tak koi handover nahi — aaj raat 21:30 par pehla banega.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
            ),
          ],
        ),
      );
    }
    final date = (_doc?['date'] ?? '').toString();
    final updated = (_doc?['updated_at'] ?? '').toString();
    final content = (_doc?['content'] ?? '').toString();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Ye rozana update hota hai — pichle din ka delete ho jata hai, agle din ki maloomat bhi is mein hoti hai. Naya agent ye parh kar sab kuch seekh jata hai.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 18, color: Color(0xFFEF0017)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          date.isEmpty ? 'Handover' : 'Handover — $date',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  if (updated.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Updated: ${_when(updated)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ],
                  const Divider(height: 20),
                  SelectableText.rich(
                    TextSpan(children: _spans(content)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
