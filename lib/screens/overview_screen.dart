import 'package:flutter/material.dart';
import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Live status: site up?, TJ Earn version, articles file size, queue depth.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});
  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _data = await AdminApi.instance.overview();
    } on UnauthorizedException {
      setState(() => _error = 'Session khatam — dobara login karein');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Load nahi ho saka — internet check karein');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SectionCard(
            title: 'Website status',
            child: Column(
              children: [
                _row('Site', (d['site200'] == true) ? 'Live (200)' : 'Down / error'),
                _row('TJ Earn version', (d['earnVersion'] ?? '-').toString()),
                _row('Articles file', '${(d['articlesJsBytes'] ?? 0)} bytes'),
                _row('Queue pending', '${(d['queuePending'] ?? 0)} items'),
              ],
            ),
          ),
          SectionCard(
            title: 'Quick action',
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Homepage refresh (queue)'),
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        await AdminApi.instance.homepageRefresh();
                        if (!context.mounted) return;
                        showMsg(context, 'Homepage refresh queue mein daal diya');
                      } on ApiException catch (e) {
                        if (!context.mounted) return;
                        showMsg(context, e.message, error: true);
                      }
                    },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Har tab website admin panel ka aik section hai. Jo change karein woh queue mein jata hai aur ~5 minute mein site par lagta hai.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
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
}
