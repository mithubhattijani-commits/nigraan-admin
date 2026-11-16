# Nigraan Admin — screen implementation spec (v1.0.0)

Owner: coordinator subagent. You implement the 8 stub screens in
`lib/screens/` (website, apps, earn, coins, doner, vault, queue,
settings). `lib/main.dart` (login + tab shell), `lib/services/admin_api.dart`
(full API client — DO NOT change its method signatures), `lib/services/js_literal.dart`
(verified parser), `lib/widgets/common_widgets.dart` (SectionCard, ErrorView,
showMsg, confirmDialog) and `lib/screens/overview_screen.dart` are DONE.
Do not rewrite them; only add what the screens need.

## Ground rules
- The web admin panel (`~/workspace/nigraan-tv/working-site/admin/index.html`,
  2,854 lines) is the spec. Every screen mirrors its panel section.
  Read the relevant panel JS before implementing a screen — field names,
  payload shapes and validation rules must match the panel EXACTLY,
  because the same queue + Worker applies them.
- All saves go through the queue (`AdminApi.queueSubmit`) and apply on
  the site within ~5 min. After every successful queue submit, show the
  returned queue id ("Queue mein daal diya — id: …").
- Every screen: pull-to-refresh where it lists data; loading spinner;
  ErrorView with retry on failure; `UnauthorizedException` → show
  "Session khatam — dobara login karein" (the user reopens the app to
  log in again). Never crash on null/missing JSON fields — use `??`
  defaults everywhere. Never log or print tokens/passwords/secret values.
- Language: UI in English, with Urdu labels where the panel has them.
  Keep it simple and professional: Nigraan red #EF0017 + blue #3D5AFE.
- After implementing ALL screens, run `flutter analyze` (Flutter 3.47.8
  at ~/workspace/tools/flutter-3.47.8/bin) and fix EVERY issue.
  Then report: per-screen what was built + the analyzer result.
  Do NOT run a local build (the parent does that) and do NOT push anything.

## 1. website_screen.dart — Website tab
- **Ticker section** (panel `loadTicker` ~line 2100): load via
  `AdminApi.ticker()`. List items (Urdu title + English title + id).
  Per item: Edit (dialog: title, titleEn, id), Up, Down, Delete.
  "Add item" button (empty fields). "Publish ticker" button →
  `AdminApi.publishTicker(items)` → show queued id. Warn: publishing
  replaces the whole ticker list.
- **Articles section**: load via `AdminApi.articles()` (1,337 articles).
  Search field filtering by id or title (case-insensitive). List shows
  title + id + date. Tap → editor screen (new route): fields id
  (disabled on edit), title, dek, cat (dropdown: news/world/pakistan/
  sports/tech/health/business — read the panel's cat list if it differs),
  catUr, date, time, mins (number), body = list of paragraph fields
  (add/remove/reorder). Save → `AdminApi.publishArticle(article)` —
  new articles get today's date/time in Urdu format like the panel
  (`ur-PK` locale, day numeric + month long + year; time HH:mm 24h)
  and thumb 'thumb-news', icon '📰'. Delete (confirm dialog) →
  `AdminApi.deleteArticle(id)`. Editing an existing article MUST
  preserve its thumb/icon/img (Article model already carries them).
- **Homepage refresh** button → `AdminApi.homepageRefresh()`.

## 2. apps_screen.dart — Apps tab
- Load manifest via `AdminApi.appsManifest()` (6 apps). One sub-tab
  per app (horizontal chips or a dropdown). For the selected app load
  `AdminApi.appConfig(key)` (full JSON, deep-copied for editing).
- **Generic typed editor** (v1): render the config recursively —
  bool → Switch, number → number TextField, string → TextField
  (multiline when long), nested object → expandable SectionCard,
  list of strings/numbers → editable rows with add/remove.
  Known keys must keep their meaning: `download.ads_required`
  (number, min 0, NO max — the user ordered no ad limit),
  `advertising_banner.enabled` (bool), rewarded `ads2/2/50` style
  nested numbers, `sponsored_ad` title/action_url/enabled.
  Preserve every key the editor does not touch (edit the deep copy,
  save the whole config).
- Save button → `queueSubmit('app-config', {'app': key, 'config': config})`
  → show queued id. Show "updated_at" auto-set to now (ISO) like the panel.

## 3. earn_screen.dart — TJ Earn tab
- Stats card: `AdminApi.sbStats()` (show the returned keys as label/value
  rows; tolerate any shape).
- **Referrals**: `AdminApi.referrals(status:)` with a status filter
  (pending/approved/rejected). Each row: user id/email, coins, status.
  Tap → detail with Approve / Reject buttons (+ reason field for reject)
  → `AdminApi.reviewReferral(id, action, reason:)`.
- **Withdrawals**: same pattern via `AdminApi.withdrawals(status:)` and
  `AdminApi.reviewWithdrawal(id, action, txId:)` — approve needs a
  transaction id field.
- **Reward config**: `AdminApi.sbConfig()` — editable keys ONLY (the
  Worker's EDITABLE_CONFIG set; read it from
  `~/workspace/nigraan-tv/admin-api/src/index.js` before building):
  quiz_coins_per_correct, quiz_questions_per_day, daily_checkin_coins,
  daily_reward_cap, read_article_coins, read_article_daily_cap,
  read_min_dwell_seconds, referral_reward_coins, referral_l1/l2/l3plus_coins,
  referral_milestone_5/10/25, referral_daily_cap,
  referral_eligibility_rule, spin_daily_limit, spin_rewards,
  streak_bonus_7/14/21/30, tool_use_coins, tool_use_daily_cap,
  tool_use_min_gap_seconds, unity_reward_coins, unity_reward_daily_cap,
  onboarding_bonus, max_pending_withdrawals. Number fields (spin_rewards
  is a list of numbers). Save per key → `AdminApi.setSbConfig(key, value)`.

## 4. coins_screen.dart — Coins tab
- Health line: `AdminApi.sbHealth()` (ok? show "Supabase connected").
- **User lookup**: text field (user id OR email) → `AdminApi.lookupUser(user)`
  → show balance + recent ledger rows (tolerate the response shape).
- **Adjust coins**: user field + amount (int, non-zero, |amount| ≤ 1,000,000)
  + note field → `AdminApi.adjustCoins(user:, amount:, note:)` with a
  confirm dialog showing the exact amount and user first.

## 5. doner_screen.dart — Doner tab
- Health line: `AdminApi.donerHealth()`.
- **In-charges**: `AdminApi.incharges()` list; add/edit form + delete.
  **Office-bearers**: `AdminApi.officeBearers()` list; add/edit + delete.
  **Donors**: `AdminApi.donors()` list (search by name); delete with confirm.
  Field names + required fields: READ the panel's Doner section in
  `working-site/admin/index.html` (search "doner") — do not guess them.
  The Worker proxies to the Doner Worker; its field names are the panel's.

## 6. vault_screen.dart — Vault tab (PIN-gated)
- **PIN gate (local only)**: first use → set a 6-digit PIN (enter twice).
  Store SHA-256 of the PIN in flutter_secure_storage (key `vault_pin_hash`).
  Later opens → PIN entry; 5 wrong tries → 60s lockout. Optional
  biometric unlock via local_auth when the device supports it.
  The PIN never leaves the phone; it only gates this tab.
- **Secrets list**: `AdminApi.vaultList()` — name + kind + created date.
  NEVER display a value in the list.
- **Add secret**: name + kind (dropdown: api_key / password / token / other)
  + value (obscured field) → `AdminApi.vaultAdd(...)`.
- **Reveal**: tap a secret → `AdminApi.vaultReveal(id)` (server audit-logs
  every reveal) → show the value once with a Copy button; auto-hide
  after 30s or when leaving the screen. Show a note: "Har dafa dekhne
  ka record banta hai."
- **Delete**: confirm dialog → `AdminApi.vaultDelete(id)`.
- **Audit log**: `AdminApi.vaultAudit()` — list of {time, action, secret name},
  newest first.

## 7. queue_screen.dart — Queue tab
- `AdminApi.queueList()` — newest 50. Each row: type, status badge
  (pending/done/failed), created time, a one-line summary by type
  (article → action + id + title; ticker → "N items"; app-config → app
  name; change-password → "password change"; homepage-refresh → "refresh").
  Per item: Retry + Delete buttons (confirm for delete).
  Pull-to-refresh. Auto-refresh every 30s while visible (Timer).

## 9. agent_screen.dart — Agent Access tab (NEW, user order 16 Nov ~09:10)
The user wants to connect a FUTURE agent (after Jaani) to the app so it
can pull the information it needs — but EVERY piece of information needs
the user's permission in the app first. The backend is LIVE
(Worker deploy e4369ab8). The rules, enforced server-side:
- An agent connects with its OWN token (created here). It can NEVER read
  anything directly. Each request becomes a PENDING item; the user taps
  Allow or Deny. Approval is ONE-TIME per request — no standing access,
  no "always allow". An approved request is consumed on first read.
  Every request + decision is audit-logged.
- Agent token storage: only the SHA-256 hash is stored server-side; the
  full token is shown ONCE at creation. The user copies it and gives it
  to the new agent. Never display a full token again — only the last 4.
- Scopes the agent can ask for (show them in plain words in the UI):
  overview, handover, ticker, articles (summary list, no bodies),
  article:<id> (full single article), app-config:<key>, queue, sb-stats,
  sb-referrals, sb-withdrawals, sb-config, doner-incharges,
  doner-office-bearers, doner-donors, vault:<id> (a secret's value).
- Screen sections:
  1. "Connect a new agent": name field + Create button → calls
     `AdminApi.createAgent(name)` → shows the token ONCE in a dialog
     with a Copy button and the warning "Ye token sirf us agent ko
     dein — dobara nahi dikhega."
  2. "Connected agents": `AdminApi.agents()` — name, created date,
     last used, token last-4, Revoke button (confirm dialog) →
     `AdminApi.revokeAgent(id)`.
  3. "Permission requests": `AdminApi.agentRequests(status: 'pending')`
     — agent name, scope in plain words (e.g. "Vault secret: Gmail
     password"), the agent's reason (detail), time. Allow / Deny buttons
     → `AdminApi.reviewAgentRequest(id, 'approve' | 'deny')`. Auto-refresh
     every 15s while visible + pull-to-refresh. Show a count badge when
     pending requests exist.
  4. "Access log": `AdminApi.agentAudit()` — newest first: time, agent,
     action (request / approve / deny / consumed / revoked), scope.
- Also fix the 4 analyzer issues found 16 Nov ~09:06 in the shell
  (they are already fixed in overview_screen.dart, common_widgets.dart
  and test/widget_test.dart was deleted — just make sure `flutter analyze`
  is clean at the end).

## 10. handover_screen.dart — Handover tab (NEW, user order 16 Nov ~09:12)
A rolling DAILY briefing document so a new agent never has to be taught
anything again. Stored server-side (Worker KV `handover:current`);
updated every day at 21:30 PKT by the daily-handover job; each new day
REPLACES the old document — yesterday's copy is deleted by design.
The document always holds: today's work, tomorrow's plan, every cron,
every version, open items, standing rules. The first document
(16 Nov 2026) is already live.
- Screen: `AdminApi.handover()` → if `available` is false, show
  "Abhi tak koi handover nahi — aaj raat 21:30 par pehla banega."
  Otherwise show the date + updated time and the full content as
  readable text (simple markdown-ish rendering: headings bold, the rest
  plain; a scrollable SelectableText is acceptable for v1).
- Pull-to-refresh. A short note at the top: "Ye rozana update hota hai —
  pichle din ka delete ho jata hai, agle din ki maloomat bhi is mein hoti
  hai. Naya agent ye parh kar sab kuch seekh jata hai."
- No editing in the app for v1 (the daily job writes it).

## 8. settings_screen.dart — Settings tab
- App version (1.0.0+1), session note (12h token), Logout button.
- **Change admin password**: new password + confirm (min 10 chars,
  must match) → `queueSubmit('change-password', {'newPassword': pw})`
  → show queued id + note that the new password applies after the
  queue runs (~5 min) and the current session stays valid until then.
- About text: what the app controls + that it never stores the admin
  password on the phone (only the session token, in secure storage).
