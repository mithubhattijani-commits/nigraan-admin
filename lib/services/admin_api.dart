// Client for the Nigraan TV admin backend.
//
// Two servers:
//  * Admin Worker (nigraan-admin-api): login + overview + queue + Supabase
//    proxy (/api/sb/*) + Doner proxy (/api/doner/*) + secrets vault
//    (/api/vault/*). Bearer token, 12h session, stored in secure storage.
//  * The public site (nigraantv.xyz): app config JSONs, the apps manifest,
//    /articles.js and the homepage (BREAKING_TICKER literal).
//
// Auth failures surface as [UnauthorizedException] so screens can send
// the user back to the login screen. Every other failure is [ApiException]
// with the server's message when one exists.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'js_literal.dart';

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Article {
  Article({
    required this.id,
    required this.title,
    required this.dek,
    required this.cat,
    required this.catUr,
    required this.date,
    required this.time,
    required this.mins,
    required this.body,
    this.thumb = 'thumb-news',
    this.icon = '📰',
    this.img,
  });

  factory Article.fromMap(Map<String, dynamic> m) {
    final body = (m['body'] as List? ?? const [])
        .whereType<String>()
        .toList();
    return Article(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      dek: (m['dek'] ?? '').toString(),
      cat: (m['cat'] ?? 'news').toString(),
      catUr: (m['catUr'] ?? 'خبر').toString(),
      date: (m['date'] ?? '').toString(),
      time: (m['time'] ?? '').toString(),
      mins: (m['mins'] is num) ? (m['mins'] as num).toInt() : 4,
      body: body,
      thumb: (m['thumb'] ?? 'thumb-news').toString(),
      icon: (m['icon'] ?? '📰').toString(),
      img: m['img']?.toString(),
    );
  }

  /// Panel's exact upsert shape: {action:'upsert', article:{...}}.
  /// thumb/icon/img are preserved from the existing article on edit.
  Map<String, dynamic> toQueuePayload() {
    final a = <String, dynamic>{
      'id': id,
      'cat': cat,
      'catUr': catUr,
      'thumb': thumb,
      'icon': icon,
      'title': title,
      'dek': dek,
      'date': date,
      'time': time,
      'mins': mins,
      'body': body,
    };
    if (img != null) a['img'] = img;
    return a;
  }

  final String id;
  final String title;
  final String dek;
  final String cat;
  final String catUr;
  final String date;
  final String time;
  final int mins;
  final List<String> body;
  final String thumb;
  final String icon;
  final String? img;
}

class TickerItem {
  TickerItem({required this.id, required this.title, required this.titleEn});

  factory TickerItem.fromMap(Map<String, dynamic> m) => TickerItem(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        titleEn: (m['titleEn'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'titleEn': titleEn};

  final String id;
  final String title;
  final String titleEn;
}

class AppManifestEntry {
  AppManifestEntry({required this.key, required this.name});
  factory AppManifestEntry.fromMap(Map<String, dynamic> m) =>
      AppManifestEntry(
        key: (m['key'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
      );
  final String key;
  final String name;
}

class AdminApi {
  AdminApi._();
  static final AdminApi instance = AdminApi._();

  static const String adminBase =
      'https://nigraan-admin-api.mithubhattijani.workers.dev';
  static const String siteBase = 'https://nigraantv.xyz';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  static const String _tokenKey = 'admin_token';
  String? _token;

  Future<String?> get token async {
    _token ??= await _secure.read(key: _tokenKey);
    return _token;
  }

  Future<bool> get isLoggedIn async => await token != null;

  Future<void> _saveToken(String t) async {
    _token = t;
    await _secure.write(key: _tokenKey, value: t);
  }

  Future<void> logout() async {
    _token = null;
    await _secure.delete(key: _tokenKey);
  }

  // ---------- low level ----------

  Future<Map<String, dynamic>> _admin(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final t = await token;
      if (t == null) throw const UnauthorizedException();
      headers['Authorization'] = 'Bearer $t';
    }
    final uri = Uri.parse('$adminBase$path');
    final http.Response res;
    if (method == 'GET') {
      res = await http.get(uri, headers: headers);
    } else if (method == 'POST') {
      res = await http.post(uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body));
    } else if (method == 'DELETE') {
      res = await http.delete(uri, headers: headers);
    } else if (method == 'PUT') {
      res = await http.put(uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body));
    } else {
      throw ApiException('unsupported method $method');
    }
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 401) throw const UnauthorizedException();
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('server error (${res.statusCode})');
    }
    if (res.statusCode >= 400) {
      throw ApiException((data['error'] ?? 'request failed').toString());
    }
    return data;
  }

  // ---------- auth + overview ----------

  /// Returns true on success. Throws ApiException on wrong password.
  Future<bool> login(String password) async {
    final data = await _admin('POST', '/api/login',
        body: {'password': password}, auth: false);
    final t = data['token']?.toString();
    if (data['ok'] == true && t != null && t.isNotEmpty) {
      await _saveToken(t);
      return true;
    }
    throw ApiException((data['error'] ?? 'login failed').toString());
  }

  Future<Map<String, dynamic>> overview() => _admin('GET', '/api/overview');

  // ---------- queue ----------

  Future<Map<String, dynamic>> queueList() => _admin('GET', '/api/queue');

  Future<String> queueSubmit(String type, Map<String, dynamic> payload) async {
    final data =
        await _admin('POST', '/api/queue', body: {'type': type, 'payload': payload});
    return (data['id'] ?? '').toString();
  }

  Future<void> queueRetry(String id) =>
      _admin('POST', '/api/queue/$id/retry');
  Future<void> queueDelete(String id) =>
      _admin('POST', '/api/queue/$id/delete');

  // ---------- Supabase (TJ Earn) ----------

  Future<Map<String, dynamic>> sbHealth() => _admin('GET', '/api/sb/health');
  Future<Map<String, dynamic>> sbStats() => _admin('GET', '/api/sb/stats');

  Future<List<dynamic>> referrals({String status = 'pending'}) async {
    final data = await _admin('GET', '/api/sb/referrals?status=$status');
    return (data['referrals'] as List? ?? const []).toList();
  }

  Future<List<dynamic>> withdrawals({String status = 'pending'}) async {
    final data = await _admin('GET', '/api/sb/withdrawals?status=$status');
    return (data['withdrawals'] as List? ?? const []).toList();
  }

  Future<void> reviewReferral(String id, String action,
      {String reason = ''}) async {
    await _admin('POST', '/api/sb/referrals/$id/review',
        body: {'action': action, 'reason': reason});
  }

  Future<void> reviewWithdrawal(String id, String action,
      {String txId = ''}) async {
    await _admin('POST', '/api/sb/withdrawals/$id/review',
        body: {'action': action, 'tx_id': txId});
  }

  Future<Map<String, dynamic>> lookupUser(String user) =>
      _admin('GET', '/api/sb/user?user=${Uri.encodeComponent(user)}');

  Future<void> adjustCoins(
      {required String user,
      required int amount,
      required String note}) async {
    await _admin('POST', '/api/sb/coins/adjust',
        body: {'user': user, 'amount': amount, 'note': note});
  }

  Future<Map<String, dynamic>> sbConfig() => _admin('GET', '/api/sb/config');

  Future<void> setSbConfig(String key, dynamic value) async {
    await _admin('POST', '/api/sb/config', body: {'key': key, 'value': value});
  }

  // ---------- Doner ----------

  Future<Map<String, dynamic>> donerHealth() =>
      _admin('GET', '/api/doner/health');
  Future<List<dynamic>> incharges() async {
    final data = await _admin('GET', '/api/doner/incharges');
    return (data['incharges'] as List? ?? const []).toList();
  }

  Future<void> saveIncharge(Map<String, dynamic> body, {String? id}) async {
    if (id == null) {
      await _admin('POST', '/api/doner/incharges', body: body);
    } else {
      await _admin('PUT', '/api/doner/incharges/$id', body: body);
    }
  }

  Future<void> deleteIncharge(String id) =>
      _admin('DELETE', '/api/doner/incharges/$id');

  Future<List<dynamic>> officeBearers() async {
    final data = await _admin('GET', '/api/doner/office-bearers');
    // The Doner Worker returns camelCase `officeBearers` (worker-v2.js);
    // accept the snake_case key too, in case the proxy ever normalises it.
    final list = data['officeBearers'] ?? data['office_bearers'];
    return (list as List? ?? const []).toList();
  }

  Future<void> saveOfficeBearer(Map<String, dynamic> body,
      {String? id}) async {
    if (id == null) {
      await _admin('POST', '/api/doner/office-bearers', body: body);
    } else {
      await _admin('PUT', '/api/doner/office-bearers/$id', body: body);
    }
  }

  Future<void> deleteOfficeBearer(String id) =>
      _admin('DELETE', '/api/doner/office-bearers/$id');

  Future<List<dynamic>> donors() async {
    final data = await _admin('GET', '/api/doner/donors');
    return (data['donors'] as List? ?? const []).toList();
  }

  Future<void> deleteDonor(String key) =>
      _admin('DELETE', '/api/doner/donors/${Uri.encodeComponent(key)}');

  // ---------- Vault (server-encrypted secrets) ----------

  Future<List<Map<String, dynamic>>> vaultList() async {
    final data = await _admin('GET', '/api/vault');
    final list = (data['secrets'] as List? ?? const []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> vaultAdd(
      {required String name,
      required String kind,
      required String value}) async {
    return _admin('POST', '/api/vault',
        body: {'name': name, 'kind': kind, 'value': value});
  }

  /// Reveal a secret value. Server-side this is audit-logged.
  Future<String> vaultReveal(String id) async {
    final data = await _admin('GET', '/api/vault/${Uri.encodeComponent(id)}');
    return (data['value'] ?? '').toString();
  }

  Future<void> vaultDelete(String id) async {
    await _admin('DELETE', '/api/vault/${Uri.encodeComponent(id)}');
  }

  Future<List<Map<String, dynamic>>> vaultAudit() async {
    final data = await _admin('GET', '/api/vault/audit');
    final list = (data['audit'] as List? ?? const []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ---------- Agent access (a future agent, per-request approval) ----------
  // The app creates agent tokens, lists pending requests and approves or
  // denies each one. Approval is one-time: the agent polls its request
  // and gets the data once. No standing access exists by design.

  /// Create an agent token. The returned token is shown ONCE — the user
  /// must copy it and give it to the agent; it is never shown again.
  Future<Map<String, dynamic>> createAgent(String name) async {
    return _admin('POST', '/api/agents', body: {'name': name});
  }

  Future<List<Map<String, dynamic>>> agents() async {
    final data = await _admin('GET', '/api/agents');
    final list = (data['agents'] as List? ?? const []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> revokeAgent(String id) async {
    await _admin('DELETE', '/api/agents/${Uri.encodeComponent(id)}');
  }

  Future<List<Map<String, dynamic>>> agentRequests(
      {String status = ''}) async {
    final q = status.isEmpty ? '' : '?status=$status';
    final data = await _admin('GET', '/api/agents/requests$q');
    final list = (data['requests'] as List? ?? const []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> reviewAgentRequest(String id, String action) async {
    await _admin(
        'POST', '/api/agents/requests/${Uri.encodeComponent(id)}/review',
        body: {'action': action});
  }

  Future<List<Map<String, dynamic>>> agentAudit() async {
    final data = await _admin('GET', '/api/agents/audit');
    final list = (data['audit'] as List? ?? const []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ---------- Daily handover (the new agent's briefing) ----------

  /// The rolling daily document. Yesterday's copy is deleted when a new
  /// day is written; the document always holds today + tomorrow.
  Future<Map<String, dynamic>> handover() => _admin('GET', '/api/handover');

  // ---------- public site data ----------

  Future<List<AppManifestEntry>> appsManifest() async {
    final res = await http.get(Uri.parse('$siteBase/apps/config/apps.json'));
    if (res.statusCode != 200) {
      throw ApiException('apps manifest failed (${res.statusCode})');
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => AppManifestEntry.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> appConfig(String key) async {
    final res =
        await http.get(Uri.parse('$siteBase/apps/config/$key.json'));
    if (res.statusCode != 200) {
      throw ApiException('config $key failed (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<TickerItem>> ticker() async {
    final res = await http.get(Uri.parse('$siteBase/'));
    if (res.statusCode != 200) {
      throw ApiException('homepage failed (${res.statusCode})');
    }
    final literal = extractArrayLiteral(res.body, 'var BREAKING_TICKER');
    final items = parseJsLiteral(literal) as List;
    return items
        .whereType<Map<String, dynamic>>()
        .map(TickerItem.fromMap)
        .toList();
  }

  Future<void> publishTicker(List<TickerItem> items) async {
    await queueSubmit('ticker', {
      'items': items.map((e) => e.toJson()).toList(),
    });
  }

  Future<List<Article>> articles() async {
    final res = await http.get(Uri.parse('$siteBase/articles.js'));
    if (res.statusCode != 200) {
      throw ApiException('articles.js failed (${res.statusCode})');
    }
    final literal = extractArrayLiteral(res.body, 'window.ARTICLES_DATA');
    final data = parseJsLiteral(literal) as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map(Article.fromMap)
        .toList();
  }

  Future<void> publishArticle(Article a) async {
    await queueSubmit(
        'article', {'action': 'upsert', 'article': a.toQueuePayload()});
  }

  Future<void> deleteArticle(String id) async {
    await queueSubmit('article', {
      'action': 'delete',
      'article': {'id': id}
    });
  }

  Future<void> homepageRefresh() async {
    await queueSubmit('homepage-refresh', {'action': 'refresh'});
  }
}
