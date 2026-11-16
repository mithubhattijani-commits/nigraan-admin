import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Apps tab: one sub-tab per app (from the live apps manifest), each with
/// a generic recursive typed editor over the app's full config JSON.
/// Mirrors the web admin panel's Apps section (admin/index.html,
/// `loadApps` / `appCardHtml` / save handler ~line 2380): edit a deep
/// copy, preserve untouched keys, stamp `updated_at` to now (ISO) on save,
/// and send the whole config via queue `app-config`.
///
/// Known keys keep their panel meaning: `download.ads_required` is a
/// number with min 0 and NO max; `advertising_banner.enabled` is a bool;
/// `sponsored_ad` has title/action_url/enabled.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});
  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<AppManifestEntry>? _apps;
  String? _manifestError;
  bool _manifestLoading = true;

  String? _selectedKey;

  /// Deep-copied configs, kept per app so unsaved edits survive switching
  /// sub-tabs (like the panel, which never re-renders cards on switch).
  final Map<String, Map<String, dynamic>> _configs = {};
  final Map<String, bool> _configLoading = {};
  final Map<String, String?> _configError = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  String _errMsg(Object e) {
    if (e is UnauthorizedException) {
      return 'Session khatam — dobara login karein';
    }
    if (e is ApiException) return e.message;
    return 'Load nahi ho saka — internet check karein';
  }

  Future<void> _loadManifest() async {
    setState(() {
      _manifestLoading = true;
      _manifestError = null;
    });
    try {
      final apps = await AdminApi.instance.appsManifest();
      if (!mounted) return;
      setState(() => _apps = apps);
      if (apps.isNotEmpty) {
        // Panel default selected app is tj-earn.
        final preferred =
            apps.any((a) => a.key == 'tj-earn') ? 'tj-earn' : apps.first.key;
        _select(preferred);
      }
    } catch (e) {
      if (mounted) setState(() => _manifestError = _errMsg(e));
    } finally {
      if (mounted) setState(() => _manifestLoading = false);
    }
  }

  Future<void> _loadConfig(String key) async {
    if (_configs.containsKey(key) || _configLoading[key] == true) return;
    setState(() {
      _configLoading[key] = true;
      _configError[key] = null;
    });
    try {
      final cfg = await AdminApi.instance.appConfig(key);
      // Deep copy: the editor mutates this; the original stays untouched.
      final copy =
          jsonDecode(jsonEncode(cfg)) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _configs[key] = copy);
      }
    } catch (e) {
      if (mounted) setState(() => _configError[key] = _errMsg(e));
    } finally {
      if (mounted) setState(() => _configLoading[key] = false);
    }
  }

  void _select(String key) {
    setState(() => _selectedKey = key);
    _loadConfig(key);
  }

  Future<void> _reloadSelected() async {
    final key = _selectedKey;
    if (key == null) return;
    setState(() {
      _configs.remove(key);
      _configError[key] = null;
    });
    await _loadConfig(key);
  }

  Future<void> _save() async {
    final key = _selectedKey;
    final config = key == null ? null : _configs[key];
    if (key == null || config == null) return;
    setState(() => _saving = true);
    try {
      config['updated_at'] = DateTime.now().toIso8601String();
      final id = await AdminApi.instance.queueSubmit('app-config', {
        'app': key,
        'config': config,
      });
      if (mounted) {
        showMsg(context, 'Queue mein daal diya — id: $id');
        setState(() {});
      }
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_manifestLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_manifestError != null) {
      return ErrorView(message: _manifestError!, onRetry: _loadManifest);
    }
    final apps = _apps ?? const <AppManifestEntry>[];
    if (apps.isEmpty) {
      return const ErrorView(message: 'Koi app nahi mili.');
    }
    final selected = _selectedKey ?? apps.first.key;
    final config = _configs[selected];
    final loading = _configLoading[selected] == true;
    final error = _configError[selected];

    return RefreshIndicator(
      onRefresh: () async {
        if (_selectedKey != null) {
          await _reloadSelected();
        }
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: apps
                  .map((a) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(a.name),
                          selected: a.key == selected,
                          onSelected: (_) => _select(a.key),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          SectionCard(
            title: _appName(apps, selected),
            actions: [
              TextButton.icon(
                onPressed: _reloadSelected,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reload'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Config change queue mein jata hai aur ~5 minute mein app par lagta hai. Jo keys edit nahi ki woh waisi ki waisi rehti hain.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                if (loading)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator())),
                if (error != null)
                  ErrorView(
                      message: error,
                      onRetry: () => _loadConfig(selected)),
                if (!loading && error == null && config != null) ...[
                  if ((config['updated_at'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Last updated: ${config['updated_at']}',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 13),
                      ),
                    ),
                  ...config.entries.map((e) => _node(
                        label: e.key,
                        value: e.value,
                        path: e.key,
                        set: (v) => config[e.key] = v,
                      )),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.send),
                    label: Text(
                        _saving ? 'Bhej rahe hain…' : 'Save (send to queue)'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _appName(List<AppManifestEntry> apps, String key) {
    AppManifestEntry? entry;
    for (final a in apps) {
      if (a.key == key) entry = a;
    }
    final name = entry?.name ?? key;
    return '$name ($key)';
  }

  /// Recursive typed editor node. Mutates the deep-copied config in place;
  /// [set] writes the new value into the parent map/list.
  Widget _node({
    required String label,
    required dynamic value,
    required String path,
    required void Function(dynamic) set,
  }) {
    if (value is bool) {
      return SwitchListTile(
        key: ValueKey(path),
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: (v) {
          set(v);
          setState(() {});
        },
      );
    }
    if (value is num) {
      return _NumberField(
        key: ValueKey(path),
        label: label,
        value: value,
        // Panel: download.ads_required has min 0 and NO max.
        min: path == 'download.ads_required' ? 0 : null,
        onChanged: (v) => set(v),
      );
    }
    if (value is String) {
      return _StringField(
        key: ValueKey(path),
        label: label,
        value: value,
        onChanged: (v) => set(v),
      );
    }
    if (value is Map<String, dynamic>) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ExpansionTile(
          title: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          childrenPadding:
              const EdgeInsets.fromLTRB(12, 0, 12, 10),
          children: value.entries
              .map((e) => _node(
                    label: e.key,
                    value: e.value,
                    path: '$path.${e.key}',
                    set: (v) => value[e.key] = v,
                  ))
              .toList(),
        ),
      );
    }
    if (value is List) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        value.add(value.isEmpty
                            ? ''
                            : _blankCopyOf(value.first));
                      });
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              ...value.asMap().entries.map((e) {
                final idx = e.key;
                final item = e.value;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _node(
                        label: item is Map ? 'Item ${idx + 1}' : '[$idx]',
                        value: item,
                        path: '$path[$idx]',
                        set: (v) => value[idx] = v,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      onPressed: () => setState(() => value.removeAt(idx)),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      );
    }
    // null or anything else: editable as text; empty string on save.
    return _StringField(
      key: ValueKey(path),
      label: label,
      value: value?.toString() ?? '',
      onChanged: (v) => set(v),
    );
  }

  /// Blank copy of a value with the same shape (for "Add" in lists):
  /// strings become '', numbers 0, bools false, maps/lists recurse.
  dynamic _blankCopyOf(dynamic v) {
    if (v is String) return '';
    if (v is num) return 0;
    if (v is bool) return false;
    if (v is Map<String, dynamic>) {
      return {
        for (final e in v.entries) e.key: _blankCopyOf(e.value),
      };
    }
    if (v is List) return <dynamic>[];
    return '';
  }
}

/// Number field that owns its controller so typing never loses focus on
/// parent rebuilds. Invalid input leaves the stored value unchanged.
class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min,
  });
  final String label;
  final num value;
  final ValueChanged<num> onChanged;
  final num? min;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static String _fmt(num v) =>
      v is int ? v.toString() : (v == v.truncateToDouble() ? v.toInt().toString() : v.toString());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(labelText: widget.label),
        keyboardType: TextInputType.numberWithOptions(
            decimal: widget.value is double),
        onChanged: (text) {
          final parsed = widget.value is double
              ? double.tryParse(text)
              : int.tryParse(text);
          if (parsed == null) return;
          var v = parsed;
          if (widget.min != null && v < widget.min!) {
            v = widget.min!;
            // Reflect the clamp in the field without moving the cursor
            // more than necessary.
            _ctrl.text = _fmt(v);
          }
          widget.onChanged(v);
        },
      ),
    );
  }
}

/// String field that owns its controller. Long strings (or ones with
/// newlines) get a multiline field.
class _StringField extends StatefulWidget {
  const _StringField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_StringField> createState() => _StringFieldState();
}

class _StringFieldState extends State<_StringField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiline =
        widget.value.length > 80 || widget.value.contains('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(labelText: widget.label),
        maxLines: multiline ? null : 1,
        minLines: multiline ? 3 : 1,
        keyboardType:
            multiline ? TextInputType.multiline : TextInputType.text,
        onChanged: widget.onChanged,
      ),
    );
  }
}
