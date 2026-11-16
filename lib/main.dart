// Nigraan Admin — the Nigraan TV website + all apps, in one phone app.
// Login is the admin panel password (nigraan-admin-api Bearer token,
// 12h session). Every tab mirrors a section of the web admin panel at
// nigraantv.xyz/admin/. The Vault tab is additionally gated behind a
// local PIN (see screens/vault_screen.dart).
library;

import 'package:flutter/material.dart';

import 'screens/agent_screen.dart';
import 'screens/apps_screen.dart';
import 'screens/coins_screen.dart';
import 'screens/doner_screen.dart';
import 'screens/earn_screen.dart';
import 'screens/handover_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vault_screen.dart';
import 'screens/website_screen.dart';
import 'services/admin_api.dart';

void main() => runApp(const NigraanAdminApp());

class NigraanAdminApp extends StatelessWidget {
  const NigraanAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nigraan Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEF0017),
          primary: const Color(0xFFEF0017),
          secondary: const Color(0xFF3D5AFE),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F6F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A1E),
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          elevation: 1,
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const _Gate(),
    );
  }
}

/// Decides login vs home based on a stored session token.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    AdminApi.instance.isLoggedIn.then((v) {
      if (mounted) setState(() => _loggedIn = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (!_loggedIn!) {
      return LoginScreen(onLoggedIn: () => setState(() => _loggedIn = true));
    }
    return HomeScreen(onLoggedOut: () => setState(() => _loggedIn = false));
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn});
  final VoidCallback onLoggedIn;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    if (_pw.text.isEmpty) {
      setState(() => _error = 'Password likhein');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminApi.instance.login(_pw.text.trim());
      widget.onLoggedIn();
    } on UnauthorizedException {
      setState(() => _error = 'Ghalat password');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Login nahi ho saka — internet check karein ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'نگران ایڈمن',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF0017)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Nigraan TV — website aur tamam apps, aik app mein',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _pw,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Admin password',
                    hintText: 'Website admin panel wala password',
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Login'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Session 12 ghante ke liye valid rehta hai. Password sirf aap jante hain — ye app usay kahin save nahi karti.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onLoggedOut});
  final VoidCallback onLoggedOut;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nigraan Admin'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: () async {
                await AdminApi.instance.logout();
                widget.onLoggedOut();
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: const Color(0xFFEF0017),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: _tabs
                .map((t) => Tab(icon: t.icon, text: t.label))
                .toList(),
          ),
        ),
        body: TabBarView(
          children: _tabs.map((t) => t.screen).toList(),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.screen);
  final String label;
  final Icon icon;
  final Widget screen;
}

const List<_Tab> _tabs = [
  _Tab('Overview', Icon(Icons.dashboard_outlined), OverviewScreen()),
  _Tab('Website', Icon(Icons.web_outlined), WebsiteScreen()),
  _Tab('Apps', Icon(Icons.apps_outlined), AppsScreen()),
  _Tab('Earn', Icon(Icons.monetization_on_outlined), EarnScreen()),
  _Tab('Coins', Icon(Icons.toll_outlined), CoinsScreen()),
  _Tab('Doner', Icon(Icons.bloodtype_outlined), DonerScreen()),
  _Tab('Vault', Icon(Icons.lock_outline), VaultScreen()),
  _Tab('Agent', Icon(Icons.support_agent_outlined), AgentScreen()),
  _Tab('Handover', Icon(Icons.event_note_outlined), HandoverScreen()),
  _Tab('Queue', Icon(Icons.queue_outlined), QueueScreen()),
  _Tab('Settings', Icon(Icons.settings_outlined), SettingsScreen()),
];
