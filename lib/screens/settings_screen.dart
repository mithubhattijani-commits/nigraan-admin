import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Settings tab (ADMIN_APP_SPEC.md §8) — mirrors the web panel's
/// settings section (working-site/admin/index.html ~line 2831).
///
/// Change-password goes through the queue, exactly like the panel:
/// `queueSubmit('change-password', {'newPassword': pw})`. The new
/// password only applies after the sync job runs (~5 min); the old
/// password — and this session — keep working until then.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _pwController = TextEditingController();
  final _pw2Controller = TextEditingController();
  bool _obscurePw = true;
  bool _obscurePw2 = true;
  bool _busy = false;
  bool _loggingOut = false;
  String? _status;

  @override
  void dispose() {
    _pwController.dispose();
    _pw2Controller.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final pw = _pwController.text;
    final pw2 = _pw2Controller.text;
    if (pw.length < 10) {
      setState(() => _status = 'The password must be at least 10 characters — پاس ورڈ کم از کم 10 حروف کا ہونا چاہیے۔');
      return;
    }
    if (pw != pw2) {
      setState(() => _status = 'The two passwords do not match — دونوں پاس ورڈ ایک جیسے نہیں ہیں۔');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Sending…';
    });
    try {
      // Never log or print the password value.
      final id = await AdminApi.instance.queueSubmit('change-password', {'newPassword': pw});
      if (!mounted) return;
      _pwController.clear();
      _pw2Controller.clear();
      setState(() {
        _status =
            'Queued — ID: $id — will go live in ~5 minutes. The old password will keep working until the next sync — قطار میں بھیج دیا گیا، ~5 منٹ میں لاگو ہوگا۔ اگلے sync تک پرانا پاس ورڈ کام کرتا رہے گا۔';
      });
      showMsg(context, 'Password change queued — id: $id');
    } on UnauthorizedException {
      if (mounted) {
        setState(() => _status = 'Session khatam — dobara login karein');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } catch (_) {
      if (mounted) setState(() => _status = 'Change nahi ho saka — internet check karein');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(
      context,
      'Logout?',
      'Session khatam kar dein? Dobara login ke liye app dobara kholni hogi.',
    );
    if (!ok) return;
    setState(() => _loggingOut = true);
    try {
      await AdminApi.instance.logout();
    } catch (_) {
      // Token delete failing locally must not block logout.
    }
    if (!mounted) return;
    setState(() => _loggingOut = false);
    // The shell (_Gate in main.dart) only checks login state at startup,
    // so it cannot show the login screen by itself — the user restarts
    // the app to log in again. Do not try to navigate there.
    showMsg(
      context,
      'Logged out — dobara login ke liye app band karke dobara kholein.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      // No server data on this tab; pull-to-refresh just settles the
      // gesture so the tab behaves like the others.
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SectionCard(
            title: 'App',
            child: Column(
              children: [
                _row('Version', '1.0.0+1'),
                _row('Session', '12h token — 12 گھنٹے کا سیشن'),
              ],
            ),
          ),
          SectionCard(
            title: 'Change password — پاس ورڈ تبدیل کریں',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This is the login password for this admin panel (admin API). It is different from the old #/admin panel password on the website.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwController,
                  obscureText: _obscurePw,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'New password (at least 10 characters) — نیا پاس ورڈ',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePw ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePw = !_obscurePw),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pw2Controller,
                  obscureText: _obscurePw2,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Repeat the new password — نیا پاس ورڈ دوبارہ لکھیں',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePw2 ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePw2 = !_obscurePw2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _changePassword,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change password — پاس ورڈ تبدیل کریں'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: const TextStyle(fontSize: 13)),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Note: a password change request also goes into the queue — the old password will keep working until the next sync. Write the new password down somewhere safe. — نوٹ: پاس ورڈ تبدیلی بھی قطار میں جاتی ہے، اگلے sync تک پرانا پاس ورڈ کام کرتا رہے گا۔',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Session — سیشن',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your login session lasts 12 hours. After that, open the app again and log in with the admin password.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF0017),
                  ),
                  onPressed: _loggingOut ? null : _logout,
                ),
                const SizedBox(height: 8),
                const Text(
                  'After logout, close the app and open it again to log in.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SectionCard(
            title: 'About — اس ایپ کے بارے میں',
            child: Text(
              'Nigraan Admin controls the Nigraan TV website and apps from your phone: the homepage ticker, articles, app configs, TJ Earn (referrals, withdrawals, coins, rewards), the Doner blood-donor lists, and the secrets vault. Every change goes into the queue and applies to the site within ~5 minutes.\n\nThis app never stores the admin password on the phone — only the session token, kept in secure storage. — یہ ایپ ایڈمن پاس ورڈ فون پر کبھی محفوظ نہیں کرتی، صرف سیشن ٹوکن secure storage میں رہتا ہے۔',
              style: TextStyle(fontSize: 14),
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
