# Anchor App — Bug Fixes & Performance Improvements

This document lists every bug found in the codebase, ordered by impact on the
"app not responding" issue. Each entry contains:

- **What** the bug is
- **Why** it causes the symptom
- **Where** the file and line region
- **Fix** — concrete code change

The fixes are independent unless noted. Apply them in the order listed for the
fastest perceptible improvement.

---

## Priority 1 — Freeze causes (apply these first)

These are the items that, together, account for the majority of the
"not responding" symptom. Fixing #1–#5 should eliminate the worst freezes.

---

### 1. `_ImageContent` decodes every visible image twice on init

**File:** `lib/features/anchor_detail/anchor_detail_screen.dart`

**What:** `_ImageContent._resolveRatio()` calls `ImageProvider.resolve()` for
every image card during `initState`. With 20 image items in a grid, this
schedules 20 simultaneous JPEG/PNG decodes on the UI isolate. Then the
`CachedNetworkImage` in `build()` resolves the image **a second time**, since
its `ImageStream` listener is separate from the one used for ratio detection.

**Why it freezes:** Image decode runs on the UI isolate by default. 20 decodes
× ~80ms each = ~1.6s of frozen UI when opening an anchor with many photos.
This is the single biggest cause of the detail-screen freeze.

**Fix:** Store image dimensions in the SQLite schema so we can render the
correct `AspectRatio` without ever resolving the stream just to measure it.

#### Step 1.1 — Add `width` and `height` columns to `anchor_items`

In `lib/core/database.dart`:

```dart
// Bump the version
return openDatabase(
  path,
  version: 3, // was 2
  onCreate: (db, _) => _createAll(db),
  onUpgrade: (db, oldVersion, newVersion) async {
    if (oldVersion < 2) await _migrateV1toV2(db);
    if (oldVersion < 3) await _migrateV2toV3(db);
  },
);
```

Update `_createAll` to include the new columns:

```dart
CREATE TABLE anchor_items (
  id TEXT PRIMARY KEY,
  anchor_id TEXT NOT NULL,
  type TEXT NOT NULL,
  title TEXT,
  description TEXT,
  content TEXT NOT NULL,
  thumbnail_path TEXT,
  original_filename TEXT,
  mime_type TEXT,
  created_at INTEGER NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'na',
  cloudinary_url TEXT,
  cloudinary_public_id TEXT,
  thumbnail_url TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,
  width INTEGER,
  height INTEGER,
  FOREIGN KEY (anchor_id) REFERENCES anchors(id) ON DELETE CASCADE
)
```

Add the migration:

```dart
Future<void> _migrateV2toV3(Database db) async {
  Future<void> safeAlter(String sql) async {
    try { await db.execute(sql); } catch (_) {}
  }
  await safeAlter('ALTER TABLE anchor_items ADD COLUMN width INTEGER');
  await safeAlter('ALTER TABLE anchor_items ADD COLUMN height INTEGER');
}
```

#### Step 1.2 — Add `width`/`height` fields to `AnchorItemModel`

In `lib/models/anchor_item_model.dart`:

```dart
class AnchorItemModel {
  // ... existing fields ...
  final int? width;
  final int? height;

  AnchorItemModel({
    // ... existing ...
    this.width,
    this.height,
  });

  double? get aspectRatio =>
      (width != null && height != null && height! > 0)
          ? width! / height!
          : null;

  Map<String, dynamic> toMap() => {
    // ... existing keys ...
    'width': width,
    'height': height,
  };

  factory AnchorItemModel.fromMap(Map<String, dynamic> map) => AnchorItemModel(
    // ... existing ...
    width: map['width'] as int?,
    height: map['height'] as int?,
  );

  AnchorItemModel copyWith({
    // ... existing ...
    int? width,
    int? height,
  }) => AnchorItemModel(
    // ... existing fields ...
    width: width ?? this.width,
    height: height ?? this.height,
  );
}
```

#### Step 1.3 — Capture dimensions at upload time (Cloudinary returns them)

In `lib/core/cloudinary_service.dart`, update `CloudinaryResult` and `upload`:

```dart
class CloudinaryResult {
  final String publicId;
  final String secureUrl;
  final String resourceType;
  final int? width;
  final int? height;

  const CloudinaryResult({
    required this.publicId,
    required this.secureUrl,
    required this.resourceType,
    this.width,
    this.height,
  });
}

// Inside upload():
return CloudinaryResult(
  publicId: body['public_id'] as String,
  secureUrl: body['secure_url'] as String,
  resourceType: resourceType,
  width: body['width'] as int?,
  height: body['height'] as int?,
);
```

#### Step 1.4 — Persist dimensions after upload

In `lib/core/sync_service.dart`, inside `_uploadItem`:

```dart
await AppDatabase.instance.updateItemSync(
  item.id,
  syncStatus: SyncStatus.synced,
  cloudinaryUrl: result.secureUrl,
  cloudinaryPublicId: result.publicId,
  thumbnailUrl: thumbUrl,
  width: result.width,
  height: result.height,
);
```

Update `AppDatabase.updateItemSync` to accept these:

```dart
Future<void> updateItemSync(
  String id, {
  required SyncStatus syncStatus,
  String? cloudinaryUrl,
  String? cloudinaryPublicId,
  String? thumbnailUrl,
  int? width,
  int? height,
}) async {
  final values = <String, dynamic>{'sync_status': syncStatus.value};
  if (cloudinaryUrl != null) values['cloudinary_url'] = cloudinaryUrl;
  if (cloudinaryPublicId != null) values['cloudinary_public_id'] = cloudinaryPublicId;
  if (thumbnailUrl != null) values['thumbnail_url'] = thumbnailUrl;
  if (width != null) values['width'] = width;
  if (height != null) values['height'] = height;

  await (await db).update('anchor_items', values,
      where: 'id = ?', whereArgs: [id]);
}
```

#### Step 1.5 — Capture dimensions for local files at save time

In `lib/core/database.dart`, modify `createItem` for images. Use the
`image_size_getter` package or simpler: decode header with
`Image.file(...).image.resolve(...)` once. **Better:** do it on a background
isolate via `compute()`. Add this helper:

```dart
// lib/core/image_dimensions.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';

Future<({int? width, int? height})> readImageDimensions(String path) async {
  return compute(_readSync, path);
}

({int? width, int? height}) _readSync(String path) {
  try {
    final size = ImageSizeGetter.getSize(FileInput(File(path)));
    return (width: size.width, height: size.height);
  } catch (_) {
    return (width: null, height: null);
  }
}
```

Add `image_size_getter: ^2.1.3` to `pubspec.yaml`.

Then in `createItem` for image type:

```dart
int? width;
int? height;
if (type == ItemType.image && !content.startsWith('http')) {
  final dims = await readImageDimensions(content);
  width = dims.width;
  height = dims.height;
}

final item = AnchorItemModel(
  // ... existing ...
  width: width,
  height: height,
);
```

#### Step 1.6 — Rewrite `_ImageContent` to NEVER resolve image streams

Replace the entire `_ImageContent` class (and remove `_ImageContentState`) in
`lib/features/anchor_detail/anchor_detail_screen.dart`:

```dart
class _ImageContent extends StatelessWidget {
  final AnchorItemModel item;
  const _ImageContent({required this.item});

  @override
  Widget build(BuildContext context) {
    // 1.0 = square placeholder when dimensions unknown
    final ratio = item.aspectRatio ?? 1.0;

    final thumbUrl = item.cloudinaryPublicId != null
        ? CloudinaryService.instance
            .thumbnailUrl(item.cloudinaryPublicId!, item.type)
        : item.thumbnailUrl;
    final cdnUrl = item.cloudinaryUrl;
    final isLocalFile = !item.content.startsWith('http');

    Widget imageWidget;
    if (thumbUrl != null) {
      imageWidget = CachedNetworkImage(
        imageUrl: thumbUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(color: AppColors.bg),
        errorWidget: (_, __, ___) => _BrokenImage(height: 60.h),
      );
    } else if (cdnUrl != null) {
      imageWidget = CachedNetworkImage(
        imageUrl: cdnUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(color: AppColors.bg),
        errorWidget: (_, __, ___) => _BrokenImage(height: 60.h),
      );
    } else if (isLocalFile) {
      imageWidget = Image.file(
        File(item.content),
        fit: BoxFit.cover,
        width: double.infinity,
        cacheWidth: 600, // decode at display size, not full size
        errorBuilder: (_, __, ___) => _BrokenImage(height: 80.h),
      );
    } else {
      imageWidget = CachedNetworkImage(
        imageUrl: item.content,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(color: AppColors.bg),
        errorWidget: (_, __, ___) => _BrokenImage(height: 60.h),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(aspectRatio: ratio, child: imageWidget),
            if (item.syncStatus != SyncStatus.synced &&
                item.syncStatus != SyncStatus.na)
              Positioned(
                top: 6,
                right: 6,
                child: _SyncBadge(status: item.syncStatus),
              ),
          ],
        ),
        if (item.title != null)
          Padding(
            padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 10.h),
            child: Text(
              item.title!,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
```

The `cacheWidth: 600` on `Image.file` is important — it tells Flutter to
decode the image at display resolution, not full camera resolution.

---

### 2. Family invalidation rebuilds every anchor's preview at once

**File:** `lib/features/home/home_screen.dart`

**What:** `_HomeScreenState.didChangeAppLifecycleState` calls
`ref.invalidate(anchorPreviewProvider)` **without a family argument**. This
invalidates every `anchorPreviewProvider(anchorId)` instance — one per anchor.

**Why it freezes:** When the user returns from sharing, all N preview
providers rebuild simultaneously. Each runs a SQLite query on the same
connection. Combined with the sync writes happening at the same time, the UI
thread blocks waiting for the DB.

**Fix:** Just invalidate `anchorsProvider`. The card widgets watch the
preview family per-anchor, but Riverpod won't trigger a rebuild on a card
whose data didn't change — and a single `getAnchors` query is cheap.

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.hidden) {
    _wasHidden = true;
  } else if (state == AppLifecycleState.resumed && _wasHidden) {
    _wasHidden = false;
    ref.invalidate(anchorsProvider);
    // REMOVED: ref.invalidate(anchorPreviewProvider);
    // The card widgets re-read previews only if their anchor changed.
  }
}
```

If you actually need previews to refresh (e.g. a newly shared item showed up
inside an anchor), invalidate just that anchor's preview:

```dart
ref.invalidate(anchorPreviewProvider(specificAnchorId));
```

---

### 3. Search keystrokes rebuild every card and restart animations

**File:** `lib/features/home/home_screen.dart`

**What:** `_AnchorListColumn` has
`key: ValueKey('$_sortReversed|$_searchQuery')`. Every character typed in
the search bar changes the key, which destroys and rebuilds the entire list
widget — restarting the 750ms staggered animation, re-creating every
`_AnchorCard` (which then re-watches its preview provider), and re-decoding
any visible thumbnails.

**Why it freezes:** Typing fast in the search bar causes one full widget
tree teardown per character. With many anchors, this drops below 10 FPS.

**Fix:** Only re-key on `_sortReversed`. Filtering changes data, not
structure.

```dart
return SliverToBoxAdapter(
  child: _AnchorListColumn(
    key: ValueKey(_sortReversed), // removed _searchQuery
    anchors: list,
  ),
);
```

If you want a smooth fade between filtered states, wrap each card in an
`AnimatedSwitcher` or use `AnimatedList`.

**Bonus:** Debounce the search input so filtering doesn't run on every
keystroke either:

```dart
Timer? _searchDebounce;

void _onSearchChanged(String q) {
  _searchDebounce?.cancel();
  _searchDebounce = Timer(const Duration(milliseconds: 150), () {
    if (mounted) setState(() => _searchQuery = q);
  });
}
```

Don't forget to cancel the timer in `dispose`.

---

### 4. BackdropFilter on every anchor card + nav bar pegs the GPU

**File:** `lib/features/home/home_screen.dart`

**What:** Each `_AnchorCard` has a `BackdropFilter` for the frosted-glass
info strip. With 10 cards visible, that's 10 simultaneous blur passes plus
one more on `_FloatingNavBar`.

**Why it freezes:** `BackdropFilter` is the most expensive Flutter primitive
on Android. On MIUI / Impeller-enabled devices, multiple BackdropFilters in
a scrolling list cause sustained frame drops below 30 FPS, which Android
sometimes interprets as ANR.

**Fix (option A — recommended):** Replace the card's BackdropFilter with a
solid scrim. Visually nearly identical, vastly cheaper.

In `_AnchorCardState.build`, replace this block:

```dart
child: BackdropFilter(
  filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
  child: Container(
    color: Colors.white.withValues(alpha: 0.04),
    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
    child: _CardInfo(anchor: widget.anchor, items: items),
  ),
),
```

With:

```dart
child: Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withValues(alpha: 0.0),
        Colors.black.withValues(alpha: 0.45),
      ],
    ),
  ),
  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
  child: _CardInfo(anchor: widget.anchor, items: items),
),
```

**Fix (option B):** Keep the blur but enable Flutter's `isComplex` /
`willChange: false` hints and reduce sigma to 3. Less effective than
option A.

**Fix for the nav bar:** Keep its BackdropFilter (only one instance, always
on screen, low cost).

---

### 5. Sync service invalidates providers from inside a tight loop

**File:** `lib/core/sync_service.dart`

**What:** `_uploadItem` is called once per pending item in a `for await`
loop. Each call invokes `_refreshItemsUi` twice (once on start, once on
finish), and `_refreshItemsUi` calls `ref.invalidate` on two providers.
Uploading 5 items = 20 invalidations = 20 SQLite reads competing with the
sync's own writes.

**Why it freezes:** SQLite serializes all access on its single connection.
The UI's read queries get queued behind the sync's writes. The UI appears
unresponsive while the queue drains.

**Fix:** Coalesce UI refreshes. Refresh once when sync starts (so the
"uploading" badge shows) and once when sync ends. If you want per-item
progress, use a separate fine-grained state instead of provider invalidation.

Replace the relevant parts of `CloudinarySyncNotifier`:

```dart
Future<void> syncPending() async {
  if (_running) return;

  final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
  if (!isOnline) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  _running = true;
  final touchedAnchors = <String>{};
  try {
    final items = await AppDatabase.instance.getPendingItems();
    if (items.isEmpty) {
      state = const AsyncData(SyncSummary.empty);
      return;
    }

    state = AsyncData(SyncSummary(pending: items.length));

    for (final item in items) {
      await _uploadItem(item, user.uid);
      touchedAnchors.add(item.anchorId);
    }

    state = AsyncData(await _computeSummary());
  } finally {
    _running = false;
    // ONE refresh per anchor, at the end.
    for (final anchorId in touchedAnchors) {
      ref.invalidate(anchorItemsProvider(anchorId));
      ref.invalidate(anchorPreviewProvider(anchorId));
    }
  }
}

Future<void> _uploadItem(AnchorItemModel item, String uid) async {
  await AppDatabase.instance.updateItemSync(
    item.id,
    syncStatus: SyncStatus.uploading,
  );
  // NO _refreshItemsUi here — was causing the invalidation storm.

  try {
    final file = File(item.content);
    if (!await file.exists()) {
      await AppDatabase.instance.updateItemSync(
        item.id,
        syncStatus: SyncStatus.synced,
      );
      return;
    }

    final result = await CloudinaryService.instance.upload(
      file, item.type, uid, item.id,
    );
    final thumbUrl =
        CloudinaryService.instance.thumbnailUrl(result.publicId, item.type);

    await AppDatabase.instance.updateItemSync(
      item.id,
      syncStatus: SyncStatus.synced,
      cloudinaryUrl: result.secureUrl,
      cloudinaryPublicId: result.publicId,
      thumbnailUrl: thumbUrl,
      width: result.width,
      height: result.height,
    );

    final synced = await AppDatabase.instance.getItemById(item.id);
    if (synced != null) {
      // Fire-and-forget but catch errors.
      unawaited(
        FirestoreService.instance
            .saveItem(uid, synced)
            .catchError((e) {
              debugPrint('Firestore save failed: $e');
            }),
      );
    }
  } catch (_) {
    await AppDatabase.instance.incrementRetryCount(item.id);
    final updated = await AppDatabase.instance.getItemById(item.id);
    if (updated != null && updated.retryCount >= 3) {
      await AppDatabase.instance.updateItemSync(
        item.id, syncStatus: SyncStatus.failed,
      );
    } else {
      await AppDatabase.instance.updateItemSync(
        item.id, syncStatus: SyncStatus.pending,
      );
    }
  }
}

// Remove _refreshItemsUi entirely — replaced by the touchedAnchors set.
```

Add `import 'dart:async';` for `unawaited`.

---

## Priority 2 — Concurrency & data-integrity bugs

These don't directly cause the freeze but make the app unstable and can
crash silently. Several of them compound the freeze under bad conditions.

---

### 6. Database `_init()` race on cold start

**File:** `lib/core/database.dart`

**What:** `_db ??= await _init()` is not atomic. Two simultaneous callers
can both see `_db == null` and both call `_init()`, opening two database
handles against the same file.

**Why:** sqflite's underlying SQLite is single-writer. Two open handles
cause `database is locked` errors on Android, which can hang the UI.

**Fix:** Guard with a `Completer`.

```dart
class AppDatabase {
  static AppDatabase? _instance;
  static Database? _db;
  static Completer<Database>? _opening;

  AppDatabase._();
  static AppDatabase get instance => _instance ??= AppDatabase._();

  Future<Database> get db {
    if (_db != null) return Future.value(_db);
    if (_opening != null) return _opening!.future;
    final c = Completer<Database>();
    _opening = c;
    _init().then((d) {
      _db = d;
      c.complete(d);
    }).catchError((e, st) {
      _opening = null;
      c.completeError(e, st);
    });
    return c.future;
  }
  // ... rest unchanged
}
```

Add `import 'dart:async';` at the top.

---

### 7. Background Firestore restore can write `state` after disposal

**Files:** `lib/providers/anchors_provider.dart`,
`lib/providers/anchor_items_provider.dart`

**What:** `_syncFromFirestoreAndRefresh` is fired from `build()` and writes
to `state` later. If the user signs out or navigates away before it
finishes, the notifier is disposed, and the assignment throws
`Bad state: Tried to use AnchorsNotifier after dispose`.

**Why:** Sometimes this exception manifests as a frozen UI on Android
because the surrounding zone never propagates the error.

**Fix:** Use a "mounted" check via Riverpod's `ref.mounted`.

In `anchors_provider.dart`:

```dart
Future<void> _syncFromFirestoreAndRefresh(String uid) async {
  await _syncFromFirestore(uid);
  if (!ref.mounted) return; // GUARD
  final restored = await AppDatabase.instance.getAnchors();
  if (!ref.mounted) return; // GUARD again after await
  if (restored.isNotEmpty) {
    state = AsyncData(restored);
  }
}
```

Same change in `anchor_items_provider.dart`:

```dart
Future<void> _syncItemsAndRefresh(String uid, String anchorId) async {
  await _syncItemsFromFirestore(uid, anchorId);
  if (!ref.mounted) return;
  final items = await AppDatabase.instance.getItems(anchorId);
  if (!ref.mounted) return;
  if (items.isNotEmpty) {
    state = AsyncData(items);
  }
}
```

---

### 8. Firestore restore N×M inserts without a transaction

**File:** `lib/providers/anchors_provider.dart`

**What:** `_syncFromFirestore` runs `Future.wait` over all anchors,
performing per-item `upsertItem` calls in parallel. SQLite serializes them
anyway, so this is fake parallelism — but each insert is its own implicit
transaction, which is 10–50× slower than batching.

**Fix:** Wrap the whole restore in `db.transaction`. Also serializes
correctly against other reads.

Add a batch method to `AppDatabase`:

```dart
Future<void> upsertAnchorsAndItems(
  List<AnchorModel> anchors,
  Map<String, List<AnchorItemModel>> itemsByAnchor,
) async {
  final database = await db;
  await database.transaction((txn) async {
    for (final a in anchors) {
      await txn.insert(
        'anchors',
        a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final entry in itemsByAnchor.entries) {
      for (final item in entry.value) {
        await txn.insert(
          'anchor_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  });
}
```

Rewrite `_syncFromFirestore`:

```dart
Future<void> _syncFromFirestore(String uid) async {
  try {
    final remoteAnchors = await FirestoreService.instance.getAnchors(uid);

    // Fetch all items in parallel (network calls, no DB contention here).
    final itemsByAnchor = <String, List<AnchorItemModel>>{};
    await Future.wait(remoteAnchors.map((anchor) async {
      final items =
          await FirestoreService.instance.getItems(uid, anchor.id);
      itemsByAnchor[anchor.id] = items;
    }));

    // Single transaction for all writes.
    await AppDatabase.instance
        .upsertAnchorsAndItems(remoteAnchors, itemsByAnchor);
  } catch (_) {
    // Non-fatal.
  }
}
```

---

### 9. In-flight restore is not guarded — concurrent passes possible

**File:** `lib/providers/anchors_provider.dart`

**What:** If `build()` runs twice (e.g. user pulls to refresh while initial
restore is still going), two `_syncFromFirestoreAndRefresh` futures run
concurrently. They both end with `state = AsyncData(restored)`, but the
ordering is undefined.

**Fix:** Add an `_inFlight` flag.

```dart
class AnchorsNotifier extends AsyncNotifier<List<AnchorModel>> {
  bool _restoreInFlight = false;

  @override
  Future<List<AnchorModel>> build() async {
    final localAnchors = await AppDatabase.instance.getAnchors();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null && localAnchors.isEmpty && !_restoreInFlight) {
      _restoreInFlight = true;
      _syncFromFirestoreAndRefresh(uid).whenComplete(() {
        _restoreInFlight = false;
      });
    }
    return localAnchors;
  }
  // ...
}
```

Same pattern in `anchor_items_provider.dart`:

```dart
class AnchorItemsNotifier
    extends FamilyAsyncNotifier<List<AnchorItemModel>, String> {
  bool _restoreInFlight = false;

  @override
  Future<List<AnchorItemModel>> build(String anchorId) async {
    final localItems = await AppDatabase.instance.getItems(anchorId);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && localItems.isEmpty && !_restoreInFlight) {
      _restoreInFlight = true;
      _syncItemsAndRefresh(uid, anchorId).whenComplete(() {
        _restoreInFlight = false;
      });
    }
    return localItems;
  }
  // ...
}
```

---

### 10. Concurrent sync triggers from three places

**Files:** `lib/core/sync_service.dart`,
`lib/features/anchor_detail/anchor_detail_screen.dart`

**What:** `syncPending` is fired from:

1. `CloudinarySyncNotifier.build()` via `Future.microtask`
2. The connectivity listener
3. `AnchorDetailScreen.initState` via `Future.microtask`

The `_running` flag prevents overlap, but only after all three have started
their `ref.read` chain.

**Fix:** Drop the `initState` trigger from `AnchorDetailScreen`. The
notifier already syncs on init and on connectivity change.

In `lib/features/anchor_detail/anchor_detail_screen.dart`, remove:

```dart
// DELETE THIS:
Future.microtask(
    () => ref.read(cloudinarySyncProvider.notifier).syncPending());
```

If you specifically want a sync when the detail screen opens (e.g. for
items added while offline), use a debounced version:

```dart
ref.read(cloudinarySyncProvider); // just touch it — build() handles sync
```

---

### 11. Link preview parsing runs on the UI isolate

**File:** `lib/core/link_preview_service.dart`

**What:** The regex-based OG tag parser runs `_parse()` on the main isolate.
For a typical 200KB page this is OK, but pages with embedded JSON-LD or
inline styles can be 1MB+, and the regex with `dotAll: true` does heavy
backtracking.

**Fix:** Move parsing to a background isolate via `compute()`.

```dart
import 'package:flutter/foundation.dart';

// ── Top-level function (required by compute) ────────────────────────
LinkPreviewData _parseInIsolate(({String html, String url}) input) {
  return LinkPreviewService._parseStatic(input.html, input.url);
}

class LinkPreviewService {
  // ... existing ...

  Future<LinkPreviewData?> getPreview(String url) async {
    final cached = await AppDatabase.instance.getLinkPreview(url);
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached;
    }

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; AnchorBot/1.0; +https://anchors.app)',
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return cached;

      // Cap body size — pages over 500KB get truncated for parsing.
      final body = response.body.length > 500 * 1024
          ? response.body.substring(0, 500 * 1024)
          : response.body;

      // Off the UI isolate.
      final data = await compute(
        _parseInIsolate,
        (html: body, url: url),
      );

      await AppDatabase.instance.saveLinkPreview(data);
      return data;
    } catch (_) {
      return cached;
    }
  }

  // Rename _parse to _parseStatic and make it static.
  static LinkPreviewData _parseStatic(String html, String url) {
    // ... same body as old _parse ...
  }
}
```

Note: regexes inside `_parseStatic` are fine in an isolate. `compute()`
spins up a fresh isolate per call; for very high frequency consider
`Isolate.run` instead (Dart 2.19+).

---

### 12. Cloudinary upload response read has no timeout

**File:** `lib/core/cloudinary_service.dart`

**What:** `request.send().timeout(...)` only times out the send. After the
server accepts, `streamed.stream.bytesToString()` has no timeout. A server
that accepts the upload but stalls on the response will hang the sync
worker forever.

**Fix:**

```dart
final streamed = await request.send().timeout(const Duration(minutes: 5));
final responseString = await streamed.stream
    .bytesToString()
    .timeout(const Duration(seconds: 30));
final body = json.decode(responseString) as Map<String, dynamic>;
```

---

### 13. Fire-and-forget Firestore calls swallow errors

**Files:** `lib/providers/anchors_provider.dart`,
`lib/providers/anchor_items_provider.dart`

**What:** Calls like `FirestoreService.instance.saveItem(uid, item);` are
not awaited and not wrapped in try/catch. Unhandled future errors propagate
to the Flutter zone, which on some Android versions surfaces as ANR.

**Fix:** Wrap with `unawaited` and a `.catchError`.

```dart
import 'dart:async';

// In anchors_provider.add:
final uid = FirebaseAuth.instance.currentUser?.uid;
if (uid != null) {
  unawaited(
    FirestoreService.instance.saveAnchor(uid, anchor).catchError((e) {
      debugPrint('Firestore saveAnchor failed: $e');
    }),
  );
}
```

Apply the same pattern to every fire-and-forget Firestore call:
`saveAnchor`, `deleteAnchor`, `saveItem`, `deleteItem`.

---

### 14. `refresh()` pattern is broken

**Files:** `lib/providers/anchors_provider.dart`,
`lib/providers/anchor_items_provider.dart`

**What:**

```dart
Future<void> refresh() async {
  ref.invalidateSelf();
  await future;
}
```

`future` may resolve to the stale future depending on timing. Pull-to-
refresh sometimes dismisses before the new data arrives.

**Fix:**

```dart
Future<void> refresh() async {
  state = const AsyncLoading();
  state = await AsyncValue.guard(() => build()); // or build(arg) for family
}
```

For the family version:

```dart
Future<void> refresh() async {
  state = const AsyncLoading();
  state = await AsyncValue.guard(() => build(arg));
}
```

---

## Priority 3 — Native / share-target bugs

---

### 15. Firebase double-init when share target launches while main app is alive

**File:** `lib/main.dart`

**What:** `shareTarget()` calls `_init()` which always calls
`Firebase.initializeApp`. If the main app is already in memory and the user
shares to Anchor, this throws `[core/duplicate-app]`.

**Fix:**

```dart
Future<void> _init() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
}
```

---

### 16. `getParcelableExtra` is broken on Android 13+

**File:** `android/app/src/main/kotlin/com/asif/anchors/ShareTargetActivity.kt`

**What:** The non-typed overload is deprecated on API 33+. On Android 14+,
the deprecated signature returns null in some cases.

**Fix:**

```kotlin
import android.os.Build

// Single share:
val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
} else {
    @Suppress("DEPRECATION")
    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
}

// Multiple share:
val uris: ArrayList<Uri> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        ?: arrayListOf()
} else {
    @Suppress("DEPRECATION")
    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        ?: arrayListOf()
}
```

---

### 17. Share screen has no timeout on `getSharedData`

**File:** `lib/features/share/share_screen.dart`

**What:** If the native side crashes or never calls back, the spinner spins
forever.

**Fix:** Add a timeout.

```dart
Future<void> _loadSharedData() async {
  try {
    final data = await _channel
        .invokeMapMethod<dynamic, dynamic>('getSharedData')
        .timeout(const Duration(seconds: 10));
    // ... rest unchanged ...
  } catch (_) {
    if (mounted) setState(() => _loading = false);
  }
}
```

---

### 18. Close animation can race the platform channel

**File:** `lib/features/share/share_screen.dart`

**What:**

```dart
void _close() {
  _slideCtrl.reverse().then((_) => _channel.invokeMethod('close'));
}
```

If the user backgrounds the app mid-animation, the `then` callback might
not fire, leaving the native activity stuck.

**Fix:**

```dart
bool _closing = false;

Future<void> _close() async {
  if (_closing) return;
  _closing = true;
  try {
    await _slideCtrl.reverse();
  } finally {
    await _channel.invokeMethod('close');
  }
}

@override
void dispose() {
  // Belt-and-suspenders: if dispose runs before _close completes, ensure
  // the native side gets the close signal.
  if (!_closing) {
    _channel.invokeMethod('close');
  }
  _slideCtrl.dispose();
  _titleCtrl.dispose();
  _descCtrl.dispose();
  super.dispose();
}
```

---

### 19. Share-screen save is sequential for multi-image shares

**File:** `lib/features/share/share_screen.dart`

**What:** `for (final path in data.uris) { await notifier.addItem(...); }`
saves 5 images one at a time. User stares at a spinner for several seconds.

**Fix:** Use `Future.wait`. Each `addItem` is independent.

```dart
} else {
  final paths = data.uris.where((p) => p.isNotEmpty);
  await Future.wait(paths.map((path) => notifier.addItem(
    type: data.type,
    title: title,
    description: desc,
    content: path,
    originalFilename: path.split('/').last,
    mimeType: data.mimeType,
  )));
}
```

---

## Priority 4 — Quality & polish bugs

---

### 20. `deleteAnchor` is not transactional

**File:** `lib/core/database.dart`

**What:** Items are deleted, then the anchor is deleted. If the second
delete fails, you have orphan state.

**Fix:**

```dart
Future<void> deleteAnchor(String id) async {
  final d = await db;
  await d.transaction((txn) async {
    await txn.delete('anchor_items', where: 'anchor_id = ?', whereArgs: [id]);
    await txn.delete('anchors', where: 'id = ?', whereArgs: [id]);
  });
}
```

---

### 21. Cloudinary `pg_1` thumbnail breaks for non-PDF raw files

**File:** `lib/core/cloudinary_service.dart`

**What:** The `default` branch of `thumbnailUrl` always tries to generate a
PDF page-1 preview. For ZIP, DOCX, etc., Cloudinary returns 404, and the UI
shows a broken image forever.

**Fix:** Only build a thumbnail URL for previewable formats.

```dart
String? thumbnailUrl(String publicId, ItemType type, {String? mimeType}) {
  switch (type) {
    case ItemType.image:
      return '$_baseCdn/image/upload'
          '/c_fill,w_400,h_400,g_auto,f_auto,q_auto'
          '/$publicId';
    case ItemType.video:
      return '$_baseCdn/video/upload'
          '/so_1.0,c_fill,w_400,h_400,f_jpg,q_auto'
          '/$publicId.jpg';
    case ItemType.file:
      // Only PDFs get a page-1 preview. Other raw files have no thumbnail.
      if (mimeType == 'application/pdf') {
        return '$_baseCdn/image/upload'
            '/pg_1,c_fill,w_400,h_400,f_jpg,q_auto'
            '/$publicId.jpg';
      }
      return null;
    default:
      return null;
  }
}
```

Update callers to pass `mimeType` (item.mimeType is already available).

---

### 22. Empty-anchor re-fetches from Firestore on every open

**File:** `lib/providers/anchor_items_provider.dart`

**What:** `if (uid != null && localItems.isEmpty)` triggers Firestore
restore every time the user opens an anchor that has no items.

**Fix:** Track sync state per anchor in SharedPreferences or a small "sync
metadata" table:

```dart
// Add to AppDatabase
Future<void> markAnchorSynced(String anchorId) async {
  await (await db).insert(
    'sync_metadata',
    {'anchor_id': anchorId, 'synced_at': DateTime.now().millisecondsSinceEpoch},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<bool> isAnchorSynced(String anchorId) async {
  final rows = await (await db).query(
    'sync_metadata',
    where: 'anchor_id = ?',
    whereArgs: [anchorId],
  );
  return rows.isNotEmpty;
}
```

Then guard the restore:

```dart
if (uid != null && localItems.isEmpty &&
    !await AppDatabase.instance.isAnchorSynced(anchorId)) {
  _restoreInFlight = true;
  _syncItemsAndRefresh(uid, anchorId)
      .whenComplete(() => _restoreInFlight = false);
}
```

And call `markAnchorSynced` at the end of `_syncItemsFromFirestore`.

Don't forget to add the table in `_createAll`:

```dart
await db.execute('''
  CREATE TABLE IF NOT EXISTS sync_metadata (
    anchor_id TEXT PRIMARY KEY,
    synced_at INTEGER NOT NULL
  )
''');
```

---

### 23. `launchUrl` errors are swallowed

**File:** `lib/features/anchor_detail/anchor_detail_screen.dart`

**Fix:**

```dart
case ItemType.link:
  final uri = Uri.tryParse(item.content);
  if (uri != null) {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }
```

---

### 24. `google_sign_in` API may not match current package version

**File:** `lib/features/auth/auth_service.dart`

**What:** `google_sign_in` v7+ changed the API. The current code uses the
v6 pattern. Verify your `pubspec.yaml` version.

**Action:** Run `flutter pub deps | grep google_sign_in` and confirm the
version. If you're on 7.x, follow the migration guide:
<https://pub.dev/packages/google_sign_in>. The v6 code shown here is fine
for `google_sign_in: ^6.x`.

---

### 25. `_ImagePreviewScreen` crashes if the local file was deleted

**File:** `lib/features/anchor_detail/anchor_detail_screen.dart`

**Fix:** Check file existence first.

```dart
@override
Widget build(BuildContext context) {
  final displayUrl = item.cloudinaryUrl ?? item.content;
  final isNet = displayUrl.startsWith('http');

  final ImageProvider provider;
  if (isNet) {
    provider = CachedNetworkImageProvider(displayUrl);
  } else {
    final file = File(displayUrl);
    if (!file.existsSync()) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, /* ... */),
        body: const Center(
          child: Text('Image not found',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    provider = FileImage(file);
  }

  return Scaffold(
    // ... use provider ...
  );
}
```

---

### 26. `share_screen._save` invalidates the whole anchors provider unnecessarily

**File:** `lib/features/share/share_screen.dart`

**Fix:** Only refresh the affected anchor's preview:

```dart
// REPLACE:
ref.invalidate(anchorsProvider);

// WITH:
ref.invalidate(anchorPreviewProvider(anchorId));
```

The anchors list itself doesn't change — only the preview thumbnails for
that one anchor.

---

## Verification checklist

After applying the fixes, verify behaviour in this order:

1. **Cold start with 20+ image items in one anchor:** open that anchor.
   Should be smooth, no freeze.
2. **Search the home screen with many anchors:** type fast in the search
   bar. Should remain responsive.
3. **Share an image from another app to Anchor while offline:** save it,
   then re-enable WiFi. Sync should happen in the background without
   freezing the UI.
4. **Sign in on a fresh install with cloud data:** anchors should appear
   without the previous 40-second freeze.
5. **Pull to refresh on the home screen:** the indicator should dismiss
   when data is ready, not before.
6. **Multi-image share (5 photos at once):** save should complete in ~1s,
   not several seconds.
7. **Open an anchor with many link cards:** scrolling should be smooth
   while previews load in the background.

---

## Files touched summary

| File | Changes |
|---|---|
| `lib/core/database.dart` | #1.1, #6, #8, #20, #22 |
| `lib/core/cloudinary_service.dart` | #1.3, #12, #21 |
| `lib/core/sync_service.dart` | #1.4, #5 |
| `lib/core/link_preview_service.dart` | #11 |
| `lib/core/image_dimensions.dart` (new) | #1.5 |
| `lib/models/anchor_item_model.dart` | #1.2 |
| `lib/providers/anchors_provider.dart` | #7, #8, #9, #13, #14 |
| `lib/providers/anchor_items_provider.dart` | #7, #9, #13, #14, #22 |
| `lib/features/home/home_screen.dart` | #2, #3, #4 |
| `lib/features/anchor_detail/anchor_detail_screen.dart` | #1.6, #10, #23, #25 |
| `lib/features/share/share_screen.dart` | #17, #18, #19, #26 |
| `lib/main.dart` | #15 |
| `android/app/src/main/kotlin/com/asif/anchors/ShareTargetActivity.kt` | #16 |
| `pubspec.yaml` | Add `image_size_getter: ^2.1.3` |

---

## Final notes

- **Always do a clean migration test:** bumping the DB to v3 means existing
  users will run `_migrateV2toV3`. Test by installing the current build,
  using it, then upgrading to the new build.
- **Riverpod 2.x has `ref.mounted`** as of 2.4. If you're on an older
  version, replace `ref.mounted` with a `bool _disposed = false;` flag set
  via `ref.onDispose(() => _disposed = true);`.
- **Don't apply #11 (compute isolate) before #1.6** — the image rendering
  fixes are independent and have higher impact.
- After fix #1, you can remove the `image_size_getter` dependency if you
  decide to skip local-file dimension capture (the placeholder square will
  briefly flash before the network image loads with its known dimensions
  from Cloudinary).
