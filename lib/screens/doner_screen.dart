import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Doner tab — mirrors the web admin panel's Doner section
/// (working-site/admin/index.html, "doner").
/// Field names + payloads match the panel exactly; the admin Worker
/// proxies to the Doner Worker, which validates every field itself.
///
/// In-charges: {id, name, email, phone, province, district, designation,
/// photo}. New in-charges also send email + password (>= 6 chars); on
/// edit the email is locked and no password is sent.
/// Office-bearers: {id, post, name, phone, showPhone, order, photo}.
/// Donors: {key, name, group, district, area, phone, photo}.
/// Photos are kept as-is on edit; new entries send ''. Photo upload
/// (pick + compress) is web-panel only — no image picker in this app.
class DonerScreen extends StatefulWidget {
  const DonerScreen({super.key});

  @override
  State<DonerScreen> createState() => _DonerScreenState();
}

const _provinces = <String>[
  'Punjab',
  'Sindh',
  'Khyber Pakhtunkhwa',
  'Balochistan',
  'Gilgit-Baltistan',
  'Azad Jammu & Kashmir',
  'Islamabad',
];

class _DonerScreenState extends State<DonerScreen> {
  final _api = AdminApi.instance;

  bool _loading = true;
  String? _error;
  bool _connected = false;
  int _donorCount = 0;
  bool _workerUp = false;

  List<Map<String, dynamic>> _incharges = [];
  List<Map<String, dynamic>> _office = [];
  List<Map<String, dynamic>> _donors = [];
  String? _incError;
  String? _officeError;
  String? _donorsError;

  String _donorQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  static List<Map<String, dynamic>> _maps(List<dynamic> raw) =>
      raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  static String _s(Map<String, dynamic> m, String key) =>
      (m[key] ?? '').toString();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final h = await _api.donerHealth();
      if (!mounted) return;
      setState(() {
        _connected = h['connected'] == true;
        _donorCount = (h['donors'] is num) ? (h['donors'] as num).toInt() : 0;
        _workerUp = h['workerUp'] == true;
      });
      if (!_connected) {
        setState(() => _loading = false);
        return;
      }
    } on UnauthorizedException {
      if (mounted) {
        setState(() {
          _error = 'Session khatam — dobara login karein';
          _loading = false;
        });
      }
      return;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Load nahi ho saka — internet check karein';
          _loading = false;
        });
      }
      return;
    }
    await _loadLists();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLists() async {
    try {
      final list = await _api.incharges();
      if (mounted) {
        setState(() {
          _incharges = _maps(list);
          _incError = null;
        });
      }
    } on UnauthorizedException {
      if (mounted) {
        setState(() => _error = 'Session khatam — dobara login karein');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _incError = e.message);
    } catch (_) {
      if (mounted) setState(() => _incError = 'Load nahi ho saka');
    }
    try {
      final list = await _api.officeBearers();
      if (mounted) {
        setState(() {
          _office = _maps(list);
          _officeError = null;
        });
      }
    } on UnauthorizedException {
      if (mounted) {
        setState(() => _error = 'Session khatam — dobara login karein');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _officeError = e.message);
    } catch (_) {
      if (mounted) setState(() => _officeError = 'Load nahi ho saka');
    }
    try {
      final list = await _api.donors();
      if (mounted) {
        setState(() {
          _donors = _maps(list);
          _donorsError = null;
        });
      }
    } on UnauthorizedException {
      if (mounted) {
        setState(() => _error = 'Session khatam — dobara login karein');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _donorsError = e.message);
    } catch (_) {
      if (mounted) setState(() => _donorsError = 'Load nahi ho saka');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        children: [
          SectionCard(
            title: 'Doner — district teams & office-bearers',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(
                  'Status',
                  _connected
                      ? 'Connected — $_donorCount donors on record'
                      : 'Not connected',
                ),
                _row('Doner Worker', _workerUp ? 'Up' : 'Down / unreachable'),
                if (!_connected)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'The Doner admin PIN is not set in the admin Worker yet. '
                      'Give the PIN to the agent in the Muse chat — it will be '
                      'stored as a Worker secret and will never appear here.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          if (_connected) ...[
            _inchargeSection(),
            _officeSection(),
            _donorSection(),
          ],
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

  // ---------- in-charges ----------

  Widget _inchargeSection() {
    return SectionCard(
      title: 'District in-charges — ضلعی انچارج',
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add'),
          onPressed: () => _showInchargeForm(null),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'One in-charge per district. The in-charge adds donors for their '
            'own district from the Doner app. Phone numbers are admin-only.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_incError != null)
            _sectionError(_incError!)
          else if (_incharges.isEmpty)
            const Text(
              'No in-charge yet.',
              style: TextStyle(color: Colors.black54),
            )
          else
            ..._incharges.map((inc) {
              final contact = [
                _s(inc, 'email'),
                _s(inc, 'phone'),
              ].where((e) => e.isNotEmpty).join(' · ');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _avatar(inc),
                title: Text(_s(inc, 'name')),
                subtitle: Text(
                  '${_s(inc, 'district')} (${_s(inc, 'designation').isEmpty ? 'In-charge' : _s(inc, 'designation')})'
                  '${contact.isEmpty ? '' : '\n$contact'}',
                ),
                isThreeLine: contact.isNotEmpty,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () => _showInchargeForm(inc),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFEF0017),
                      ),
                      tooltip: 'Delete',
                      onPressed: () => _deleteIncharge(inc),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showInchargeForm(Map<String, dynamic>? existing) async {
    final isNew = existing == null;
    final src = existing ?? <String, dynamic>{};
    final nameC = TextEditingController(text: _s(src, 'name'));
    final emailC = TextEditingController(text: _s(src, 'email'));
    final passC = TextEditingController();
    final phoneC = TextEditingController(text: _s(src, 'phone'));
    final desigC = TextEditingController(text: _s(src, 'designation'));
    final districtC = TextEditingController(text: _s(src, 'district'));
    var province = _s(src, 'province');
    if (!_provinces.contains(province)) province = 'Punjab';
    var saving = false;
    var formError = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            isNew
                ? 'Add in-charge — انچارج شامل کریں'
                : 'Edit in-charge — انچارج میں ترمیم',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name — نام *'),
                ),
                TextField(
                  controller: emailC,
                  enabled: isNew,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (login) — ای میل',
                  ),
                ),
                if (isNew)
                  TextField(
                    controller: passC,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password (at least 6 characters) *',
                    ),
                  ),
                TextField(
                  controller: phoneC,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (admin-only) — فون',
                  ),
                ),
                TextField(
                  controller: desigC,
                  decoration: const InputDecoration(
                    labelText: 'Designation — عہدہ',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: province,
                  decoration: const InputDecoration(
                    labelText: 'Province — صوبہ',
                  ),
                  items: _provinces
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setDialog(() => province = v ?? 'Punjab'),
                ),
                TextField(
                  controller: districtC,
                  decoration: const InputDecoration(
                    labelText: 'District / city — ضلع / شہر *',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Photo can be added or changed from the web admin panel. '
                  'An existing photo is kept.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
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
                      final district = districtC.text.trim();
                      if (name.isEmpty) {
                        setDialog(() => formError = 'Name is required.');
                        return;
                      }
                      if (district.isEmpty) {
                        setDialog(() => formError = 'District is required.');
                        return;
                      }
                      String? email;
                      String? password;
                      if (isNew) {
                        email = emailC.text.trim();
                        password = passC.text;
                        if (email.isEmpty) {
                          setDialog(() => formError = 'Email is required.');
                          return;
                        }
                        if (password.length < 6) {
                          setDialog(
                            () => formError =
                                'Password must be at least 6 characters.',
                          );
                          return;
                        }
                      }
                      setDialog(() {
                        saving = true;
                        formError = '';
                      });
                      final body = <String, dynamic>{
                        'name': name,
                        'phone': phoneC.text.trim(),
                        'province': province,
                        'district': district,
                        'designation': desigC.text.trim().isEmpty
                            ? 'In-charge'
                            : desigC.text.trim(),
                        'photo': _s(src, 'photo'),
                      };
                      if (isNew) {
                        body['email'] = email;
                        body['password'] = password;
                      }
                      try {
                        await _api.saveIncharge(
                          body,
                          id: isNew ? null : _s(src, 'id'),
                        );
                        if (!mounted) return;
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        showMsg(context, 'Saved.');
                        await _loadLists();
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
    emailC.dispose();
    passC.dispose();
    phoneC.dispose();
    desigC.dispose();
    districtC.dispose();
  }

  Future<void> _deleteIncharge(Map<String, dynamic> inc) async {
    final ok = await confirmDialog(
      context,
      'Delete in-charge?',
      'Delete this in-charge? Their login will stop working.',
    );
    if (!ok || !mounted) return;
    try {
      await _api.deleteIncharge(_s(inc, 'id'));
      if (!mounted) return;
      showMsg(context, 'Deleted.');
      await _loadLists();
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

  // ---------- office-bearers ----------

  Widget _officeSection() {
    return SectionCard(
      title: 'Office-bearers — عہدیداران',
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add'),
          onPressed: () => _showOfficeForm(null),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All welfare-organisation posts. Only the founder’s phone '
            'number is shown publicly — never tick “show phone” for '
            'anyone else.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_officeError != null)
            _sectionError(_officeError!)
          else if (_office.isEmpty)
            const Text(
              'No office-bearer yet.',
              style: TextStyle(color: Colors.black54),
            )
          else
            ..._office.map((ob) {
              final phone = _s(ob, 'phone');
              final showPhone = ob['showPhone'] == true;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _avatar(ob),
                title: Text('${_s(ob, 'post')} — ${_s(ob, 'name')}'),
                subtitle: Text(
                  'Order ${_s(ob, 'order').isEmpty ? '0' : _s(ob, 'order')}'
                  '${showPhone && phone.isNotEmpty ? ' · $phone (public)' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () => _showOfficeForm(ob),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFEF0017),
                      ),
                      tooltip: 'Delete',
                      onPressed: () => _deleteOffice(ob),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showOfficeForm(Map<String, dynamic>? existing) async {
    final isNew = existing == null;
    final src = existing ?? <String, dynamic>{};
    final postC = TextEditingController(text: _s(src, 'post'));
    final nameC = TextEditingController(text: _s(src, 'name'));
    final phoneC = TextEditingController(text: _s(src, 'phone'));
    final orderC = TextEditingController(
      text: _s(src, 'order').isEmpty ? '0' : _s(src, 'order'),
    );
    var showPhone = src['showPhone'] == true;
    var saving = false;
    var formError = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            isNew
                ? 'Add office-bearer — عہدیدار شامل کریں'
                : 'Edit office-bearer — عہدیدار میں ترمیم',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: postC,
                  decoration: const InputDecoration(labelText: 'Post — عہدہ *'),
                ),
                TextField(
                  controller: nameC,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name — نام *'),
                ),
                TextField(
                  controller: phoneC,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (admin-only) — فون',
                  ),
                ),
                TextField(
                  controller: orderC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Order — ترتیب'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show phone publicly (founder only)'),
                  value: showPhone,
                  onChanged: (v) => setDialog(() => showPhone = v ?? false),
                ),
                const Text(
                  'Photo can be added or changed from the web admin panel. '
                  'An existing photo is kept.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
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
                      final post = postC.text.trim();
                      final name = nameC.text.trim();
                      if (post.isEmpty) {
                        setDialog(() => formError = 'Post is required.');
                        return;
                      }
                      if (name.isEmpty) {
                        setDialog(() => formError = 'Name is required.');
                        return;
                      }
                      setDialog(() {
                        saving = true;
                        formError = '';
                      });
                      final body = <String, dynamic>{
                        'post': post,
                        'name': name,
                        'phone': phoneC.text.trim(),
                        'showPhone': showPhone,
                        'order': int.tryParse(orderC.text.trim()) ?? 0,
                        'photo': _s(src, 'photo'),
                      };
                      try {
                        await _api.saveOfficeBearer(
                          body,
                          id: isNew ? null : _s(src, 'id'),
                        );
                        if (!mounted) return;
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        showMsg(context, 'Saved.');
                        await _loadLists();
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
    postC.dispose();
    nameC.dispose();
    phoneC.dispose();
    orderC.dispose();
  }

  Future<void> _deleteOffice(Map<String, dynamic> ob) async {
    final ok = await confirmDialog(
      context,
      'Delete office-bearer?',
      'Delete this office-bearer?',
    );
    if (!ok || !mounted) return;
    try {
      await _api.deleteOfficeBearer(_s(ob, 'id'));
      if (!mounted) return;
      showMsg(context, 'Deleted.');
      await _loadLists();
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

  // ---------- donors ----------

  Widget _donorSection() {
    final q = _donorQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _donors
        : _donors
              .where((d) => _s(d, 'name').toLowerCase().contains(q))
              .toList();
    final shown = filtered.take(100).toList();
    return SectionCard(
      title: 'Donors (admin view) — ڈونر',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Phone numbers are visible here only — the public never '
            'sees them.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search by name — نام سے تلاش کریں',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _donorQuery = v),
          ),
          const SizedBox(height: 8),
          if (_donorsError != null)
            _sectionError(_donorsError!)
          else if (_donors.isEmpty)
            const Text(
              'No donors yet.',
              style: TextStyle(color: Colors.black54),
            )
          else if (shown.isEmpty)
            const Text(
              'No donor matches this name.',
              style: TextStyle(color: Colors.black54),
            )
          else ...[
            Text(
              '${filtered.length} donor${filtered.length == 1 ? '' : 's'}'
              '${filtered.length > 100 ? ' (showing first 100)' : ''}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            ...shown.map((dn) {
              final group = _s(dn, 'group');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _avatar(dn),
                title: Text(
                  '${_s(dn, 'name')}${group.isEmpty ? '' : ' ($group)'}',
                ),
                subtitle: Text(
                  '${_s(dn, 'district')}${_s(dn, 'area').isEmpty ? '' : ', ${_s(dn, 'area')}'}'
                  '${_s(dn, 'phone').isEmpty ? '' : '\n${_s(dn, 'phone')}'}',
                ),
                isThreeLine: _s(dn, 'phone').isNotEmpty,
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFEF0017),
                  ),
                  tooltip: 'Delete',
                  onPressed: () => _deleteDonor(dn),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteDonor(Map<String, dynamic> dn) async {
    final ok = await confirmDialog(
      context,
      'Delete donor?',
      'Delete this donor?',
    );
    if (!ok || !mounted) return;
    final key = _s(dn, 'key');
    if (key.isEmpty) {
      showMsg(context, 'Donor key missing — delete nahi ho saka', error: true);
      return;
    }
    try {
      await _api.deleteDonor(key);
      if (!mounted) return;
      showMsg(context, 'Deleted.');
      await _loadLists();
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

  // ---------- shared bits ----------

  Widget _sectionError(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 18, color: Colors.red),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
        TextButton(onPressed: _loadLists, child: const Text('Retry')),
      ],
    ),
  );

  /// Small photo thumb when the record carries a data-URL photo,
  /// otherwise an initial avatar. Never throws on a bad value.
  Widget _avatar(Map<String, dynamic> m) {
    final photo = _s(m, 'photo');
    if (photo.startsWith('data:image')) {
      try {
        final bytes = base64Decode(photo.split(',').last);
        return CircleAvatar(backgroundImage: MemoryImage(bytes));
      } catch (_) {
        // Fall through to the initial avatar.
      }
    }
    final name = _s(m, 'name');
    return CircleAvatar(
      backgroundColor: const Color(0xFF3D5AFE),
      foregroundColor: Colors.white,
      child: Text(name.isEmpty ? '?' : name[0]),
    );
  }
}
