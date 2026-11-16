import 'package:flutter/material.dart';

import '../services/admin_api.dart';
import '../widgets/common_widgets.dart';

/// Website tab: breaking ticker, articles (list + editor) and homepage
/// refresh. Mirrors the web admin panel sections in
/// working-site/admin/index.html (ticker ~line 2097, articles ~line 2197).
///
/// Every save goes through the queue; the queue id is shown after each
/// successful submit. Publishing the ticker replaces the whole list.
class WebsiteScreen extends StatefulWidget {
  const WebsiteScreen({super.key});
  @override
  State<WebsiteScreen> createState() => _WebsiteScreenState();
}

/// Panel's category list (admin/index.html `<select id="art-cat">`).
const List<String> _cats = [
  'news',
  'world',
  'politics',
  'sports',
  'cricket',
  'tech',
  'science',
  'entertainment',
  'weather',
  'fitness',
  'cooking',
  'history',
  'islamic',
  'fashion',
  'fun',
];

/// Panel's CAT_UR map (admin/index.html).
const Map<String, String> _catUrMap = {
  'news': 'پاکستان',
  'world': 'دنیا',
  'politics': 'پاکستان',
  'sports': 'کھیل',
  'cricket': 'کرکٹ',
  'tech': 'ٹیکنالوجی',
  'science': 'سائنس',
  'entertainment': 'شوبز',
  'weather': 'موسم',
  'fitness': 'فٹنس',
  'cooking': 'کھانا',
  'history': 'تاریخ',
  'islamic': 'اسلامی',
  'fashion': 'فیشن',
  'fun': 'تفریح',
};

/// Urdu month names for the panel's `toLocaleDateString('ur-PK',
/// {day:'numeric', month:'long', year:'numeric'})` format, e.g.
/// "16 نومبر 2026" (Latin digits, as on the live site).
const List<String> _urduMonths = [
  'جنوری',
  'فروری',
  'مارچ',
  'اپریل',
  'مئی',
  'جون',
  'جولائی',
  'اگست',
  'ستمبر',
  'اکتوبر',
  'نومبر',
  'دسمبر',
];

String _urduDateToday() {
  final now = DateTime.now();
  return '${now.day} ${_urduMonths[now.month - 1]} ${now.year}';
}

String _timeNow() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

String _errMsg(Object e) {
  if (e is UnauthorizedException) {
    return 'Session khatam — dobara login karein';
  }
  if (e is ApiException) return e.message;
  return 'Load nahi ho saka — internet check karein';
}

class _WebsiteScreenState extends State<WebsiteScreen> {
  static const int _pageSize = 50;

  List<TickerItem> _ticker = [];
  bool _tickerLoading = true;
  String? _tickerError;

  List<Article> _articles = [];
  bool _articlesLoading = true;
  String? _articlesError;

  String _query = '';
  int _page = 0;

  bool _publishingTicker = false;
  bool _refreshing = false;
  String? _deletingArticleId;

  @override
  void initState() {
    super.initState();
    _loadTicker();
    _loadArticles();
  }

  Future<void> _loadTicker() async {
    setState(() {
      _tickerLoading = true;
      _tickerError = null;
    });
    try {
      final items = await AdminApi.instance.ticker();
      if (mounted) {
        setState(() => _ticker = items);
      }
    } catch (e) {
      if (mounted) setState(() => _tickerError = _errMsg(e));
    } finally {
      if (mounted) setState(() => _tickerLoading = false);
    }
  }

  Future<void> _loadArticles() async {
    setState(() {
      _articlesLoading = true;
      _articlesError = null;
    });
    try {
      final list = await AdminApi.instance.articles();
      if (mounted) {
        setState(() {
          _articles = list;
          _page = 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _articlesError = _errMsg(e));
    } finally {
      if (mounted) setState(() => _articlesLoading = false);
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTicker(), _loadArticles()]);
  }

  List<Article> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _articles;
    return _articles
        .where((a) =>
            a.id.toLowerCase().contains(q) ||
            a.title.toLowerCase().contains(q))
        .toList();
  }

  // ---------- ticker ----------

  Future<void> _editTickerItem([int? index]) async {
    final existing = index == null ? null : _ticker[index];
    final result = await showDialog<TickerItem>(
      context: context,
      builder: (c) => _TickerEditDialog(item: existing),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _ticker.insert(0, result);
      } else {
        _ticker[index] = result;
      }
    });
  }

  void _moveTicker(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _ticker.length) return;
    setState(() {
      final item = _ticker.removeAt(index);
      _ticker.insert(target, item);
    });
  }

  Future<void> _deleteTickerItem(int index) async {
    final ok = await confirmDialog(
      context,
      'Delete ticker item?',
      'Delete this item from the ticker?',
    );
    if (!ok) return;
    setState(() => _ticker.removeAt(index));
  }

  Future<void> _publishTicker() async {
    if (_ticker.isEmpty) {
      showMsg(context, 'Ticker khaali hai — pehle koi item shamil karein',
          error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      'Publish ticker?',
      'Publishing replaces the whole ticker list on the homepage.',
    );
    if (!ok) return;
    setState(() => _publishingTicker = true);
    try {
      // Same payload as AdminApi.publishTicker, but queueSubmit returns
      // the queue id so it can be shown.
      final id = await AdminApi.instance.queueSubmit('ticker', {
        'items': _ticker.map((e) => e.toJson()).toList(),
      });
      if (mounted) showMsg(context, 'Queue mein daal diya — id: $id');
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _publishingTicker = false);
    }
  }

  // ---------- articles ----------

  Future<void> _openEditor([Article? article]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ArticleEditorScreen(
          article: article,
          existingIds: _articles.map((a) => a.id).toSet(),
        ),
      ),
    );
    if (saved == true) _loadArticles();
  }

  Future<void> _deleteArticle(Article article) async {
    final ok = await confirmDialog(
      context,
      'Delete article?',
      'Delete "${article.title.isEmpty ? article.id : article.title}"?',
    );
    if (!ok) return;
    setState(() => _deletingArticleId = article.id);
    try {
      final id = await AdminApi.instance.queueSubmit('article', {
        'action': 'delete',
        'article': {'id': article.id},
      });
      if (mounted) {
        showMsg(context, 'Queue mein daal diya — id: $id');
        setState(() => _articles.removeWhere((a) => a.id == article.id));
      }
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _deletingArticleId = null);
    }
  }

  Future<void> _homepageRefresh() async {
    setState(() => _refreshing = true);
    try {
      final id = await AdminApi.instance
          .queueSubmit('homepage-refresh', {'action': 'refresh'});
      if (mounted) showMsg(context, 'Queue mein daal diya — id: $id');
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session khatam — dobara login karein', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _tickerSection(),
          _articlesSection(),
          SectionCard(
            title: 'Homepage',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Homepage refresh — homepage dobara banayen (queue mein jata hai, ~5 minute mein lagta hai).',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _refreshing ? null : _homepageRefresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                      _refreshing ? 'Bhej rahe hain…' : 'Homepage refresh'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Har change queue mein jata hai aur ~5 minute mein site par lagta hai.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tickerSection() {
    return SectionCard(
      title: 'Breaking Ticker (بریکنگ ٹکر)',
      actions: [
        TextButton.icon(
          onPressed: () => _editTickerItem(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add item'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Homepage par chalne wali breaking khabrein. Publish karne par poori nayi list queue mein jati hai.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_tickerLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator())),
          if (_tickerError != null)
            ErrorView(message: _tickerError!, onRetry: _loadTicker),
          if (!_tickerLoading && _tickerError == null && _ticker.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Ticker khaali hai.',
                  style: TextStyle(color: Colors.black54)),
            ),
          if (!_tickerLoading && _tickerError == null)
            ..._ticker.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        '${item.titleEn.isEmpty ? '—' : item.titleEn} · ${item.id}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                              onPressed: () => _editTickerItem(idx),
                              child: const Text('Edit')),
                          IconButton(
                            tooltip: 'Up',
                            icon: const Icon(Icons.arrow_upward),
                            onPressed: idx == 0
                                ? null
                                : () => _moveTicker(idx, -1),
                          ),
                          IconButton(
                            tooltip: 'Down',
                            icon: const Icon(Icons.arrow_downward),
                            onPressed: idx == _ticker.length - 1
                                ? null
                                : () => _moveTicker(idx, 1),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _deleteTickerItem(idx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _publishingTicker ? null : _publishTicker,
            icon: const Icon(Icons.publish),
            label: Text(
                _publishingTicker ? 'Bhej rahe hain…' : 'Publish ticker'),
          ),
        ],
      ),
    );
  }

  Widget _articlesSection() {
    final filtered = _filtered;
    final int pages = filtered.isEmpty
        ? 1
        : ((filtered.length - 1) ~/ _pageSize) + 1;
    int page = _page;
    if (page >= pages) page = pages - 1;
    if (page < 0) page = 0;
    final slice = filtered.skip(page * _pageSize).take(_pageSize).toList();
    return SectionCard(
      title: 'Articles (مضامین)',
      actions: [
        TextButton.icon(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New article'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by id ya title…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          const SizedBox(height: 8),
          if (_articlesLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator())),
          if (_articlesError != null)
            ErrorView(message: _articlesError!, onRetry: _loadArticles),
          if (!_articlesLoading && _articlesError == null) ...[
            Text(
              '${filtered.length} articles · Page ${page + 1} of $pages',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (slice.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Koi article nahi mila.',
                    style: TextStyle(color: Colors.black54)),
              ),
            ...slice.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.title.isEmpty ? '(no title)' : a.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${a.id} · ${a.catUr.isEmpty ? a.cat : a.catUr} · ${a.date}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openEditor(a),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        onPressed: _deletingArticleId == a.id
                            ? null
                            : () => _deleteArticle(a),
                      ),
                    ],
                  ),
                  onTap: () => _openEditor(a),
                )),
            if (pages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                    child: const Text('Previous'),
                  ),
                  TextButton(
                    onPressed: page >= pages - 1
                        ? null
                        : () => setState(() => _page = page + 1),
                    child: const Text('Next'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// Edit dialog for one ticker item: Urdu title, English title, id.
/// New items get a panel-style id (`ticker-<base36 timestamp>`) when the
/// id field is left empty.
class _TickerEditDialog extends StatefulWidget {
  const _TickerEditDialog({this.item});
  final TickerItem? item;
  @override
  State<_TickerEditDialog> createState() => _TickerEditDialogState();
}

class _TickerEditDialogState extends State<_TickerEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _titleEn;
  late final TextEditingController _id;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item?.title ?? '');
    _titleEn = TextEditingController(text: widget.item?.titleEn ?? '');
    _id = TextEditingController(text: widget.item?.id ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _titleEn.dispose();
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    return AlertDialog(
      title: Text(isNew ? 'Add ticker item' : 'Edit ticker item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration:
                  const InputDecoration(labelText: 'Headline (Urdu) — سرخی'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleEn,
              decoration: const InputDecoration(
                  labelText: 'Headline (English)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _id,
              decoration: const InputDecoration(
                labelText: 'ID',
                hintText: 'Khaali chhorein to auto id ban jayega',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) {
              showMsg(context, 'Urdu headline likhna zaroori hai',
                  error: true);
              return;
            }
            var id = _id.text.trim();
            if (id.isEmpty) {
              id = 'ticker-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
            }
            Navigator.of(context).pop(TickerItem(
              id: id,
              title: title,
              titleEn: _titleEn.text.trim(),
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Full article editor on its own route. New articles get today's
/// date/time in the panel's Urdu format, thumb 'thumb-news' and icon '📰';
/// editing an existing article preserves its thumb/icon/img and its
/// date/time/mins unless changed here.
class _ArticleEditorScreen extends StatefulWidget {
  const _ArticleEditorScreen({required this.article, required this.existingIds});
  final Article? article;
  final Set<String> existingIds;
  @override
  State<_ArticleEditorScreen> createState() => _ArticleEditorScreenState();
}

class _ArticleEditorScreenState extends State<_ArticleEditorScreen> {
  late final TextEditingController _id;
  late final TextEditingController _title;
  late final TextEditingController _dek;
  late final TextEditingController _catUr;
  late final TextEditingController _date;
  late final TextEditingController _time;
  late final TextEditingController _mins;
  late final List<TextEditingController> _paras;
  late String _cat;
  bool _saving = false;

  bool get _isNew => widget.article == null;

  @override
  void initState() {
    super.initState();
    final a = widget.article;
    _cat = (a?.cat ?? 'news');
    if (!_cats.contains(_cat)) _cat = 'news';
    _id = TextEditingController(text: a?.id ?? '');
    _title = TextEditingController(text: a?.title ?? '');
    _dek = TextEditingController(text: a?.dek ?? '');
    _catUr = TextEditingController(
        text: a?.catUr ?? _catUrMap[_cat] ?? '');
    _date = TextEditingController(
        text: a?.date ?? _urduDateToday());
    _time = TextEditingController(text: a?.time ?? _timeNow());
    _mins = TextEditingController(text: '${a?.mins ?? 3}');
    final body = a?.body ?? <String>[];
    _paras = (body.isEmpty ? [''] : body)
        .map((p) => TextEditingController(text: p))
        .toList();
  }

  @override
  void dispose() {
    _id.dispose();
    _title.dispose();
    _dek.dispose();
    _catUr.dispose();
    _date.dispose();
    _time.dispose();
    _mins.dispose();
    for (final c in _paras) {
      c.dispose();
    }
    super.dispose();
  }

  void _onCatChanged(String? value) {
    if (value == null) return;
    setState(() {
      _cat = value;
      if (_catUr.text.trim().isEmpty) {
        _catUr.text = _catUrMap[value] ?? '';
      }
    });
  }

  void _movePara(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _paras.length) return;
    setState(() {
      final c = _paras.removeAt(index);
      _paras.insert(target, c);
    });
  }

  Future<void> _save() async {
    final id = _id.text.trim();
    final title = _title.text.trim();
    final body = _paras.map((c) => c.text.trim()).where((p) => p.isNotEmpty).toList();

    // Panel validation (admin/index.html article-form submit).
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) {
      showMsg(
          context,
          'ID ghalat hai — sirf chhote English haroof, number aur hyphen (-) allowed',
          error: true);
      return;
    }
    if (title.isEmpty) {
      showMsg(context, 'Title likhna zaroori hai', error: true);
      return;
    }
    if (body.isEmpty) {
      showMsg(context, 'Body mein kam az kam aik paragraph likhein',
          error: true);
      return;
    }
    if (_isNew && widget.existingIds.contains(id)) {
      showMsg(context, 'Is ID ka article pehle se mojood hai', error: true);
      return;
    }

    final existing = widget.article;
    final article = Article(
      id: id,
      title: title,
      dek: _dek.text.trim(),
      cat: _cat,
      catUr: _catUr.text.trim().isEmpty
          ? (_catUrMap[_cat] ?? _cat)
          : _catUr.text.trim(),
      date: _date.text.trim().isEmpty ? _urduDateToday() : _date.text.trim(),
      time: _time.text.trim().isEmpty ? _timeNow() : _time.text.trim(),
      mins: int.tryParse(_mins.text.trim()) ?? (existing?.mins ?? 3),
      body: body,
      thumb: existing?.thumb ?? 'thumb-news',
      icon: existing?.icon ?? '📰',
      img: existing?.img,
    );

    setState(() => _saving = true);
    try {
      final queueId = await AdminApi.instance.queueSubmit('article', {
        'action': 'upsert',
        'article': article.toQueuePayload(),
      });
      if (!mounted) return;
      showMsg(context, 'Queue mein daal diya — id: $queueId');
      Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New article' : 'Edit article'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _id,
            enabled: _isNew,
            decoration: const InputDecoration(
              labelText: 'ID — lowercase English letters, numbers and hyphens (-) only',
              hintText: 'e.g. mir-ali-mosque-hideouts-ibo-nov-9-ur',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            autofocus: _isNew,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dek,
            decoration: const InputDecoration(labelText: 'Summary (Dek)'),
            maxLines: 3,
            minLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _cat,
                  decoration:
                      const InputDecoration(labelText: 'Category (code)'),
                  items: _cats
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: _onCatChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _catUr,
                  decoration: const InputDecoration(
                      labelText: 'Category (Urdu)',
                      hintText: 'e.g. Pakistan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _date,
                  decoration:
                      const InputDecoration(labelText: 'Date (تاریخ)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _time,
                  decoration: const InputDecoration(
                      labelText: 'Time (HH:mm, 24h)'),
                  keyboardType: TextInputType.datetime,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _mins,
                  decoration:
                      const InputDecoration(labelText: 'Read mins'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Body — har paragraph alag field mein',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ..._paras.asMap().entries.map((e) {
            final idx = e.key;
            final ctrl = e.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paragraph ${idx + 1}',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 13)),
                    TextField(
                      controller: ctrl,
                      maxLines: null,
                      minLines: 3,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Paragraph likhein…',
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Up',
                          icon: const Icon(Icons.arrow_upward, size: 20),
                          onPressed: idx == 0
                              ? null
                              : () => _movePara(idx, -1),
                        ),
                        IconButton(
                          tooltip: 'Down',
                          icon: const Icon(Icons.arrow_downward, size: 20),
                          onPressed: idx == _paras.length - 1
                              ? null
                              : () => _movePara(idx, 1),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          onPressed: _paras.length <= 1
                              ? null
                              : () => setState(() {
                                    _paras.removeAt(idx).dispose();
                                  }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(
                () => _paras.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Add paragraph'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.send),
            label: Text(_saving ? 'Bhej rahe hain…' : 'Save (send to queue)'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
