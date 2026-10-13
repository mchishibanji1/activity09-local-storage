# In-Class Activity 09 — Local Storage Part II (Flutter + SQLite)

**Student:** Marc Chishibanji
**Course:** Mobile Application Development — MW Section
**Pathway:** Undergraduate
**Due:** October 13, 2026

## Overview

This project extends my In-Class Activity 08 Flutter + SQLite app (single `my_table`
guest roster) into a related parent/child card catalogue. A versioned database
migration adds `folders` and `cards` tables with a foreign-key relationship, while
preserving every row from Part I. The UI exposes folder lists with card counts, a
per-folder card list, add/edit/delete for cards, create/delete for folders with
confirmation, an image-reference fallback, and clear loading/empty/error states.

## Environment

- Flutter 3.47.3 (stable channel)
- Dart 3.13.3
- Target: Android 14 (API 34), emulator `emulator-5554`
- Package name: `com.example.local_storage_lab`
- Dependencies: `sqflite`, `path` (both from Part I; no new dependencies added)

## Setup / run / test commands

```powershell
flutter pub get
flutter run -d emulator-5554      # dev run on Android emulator
flutter analyze                   # static analysis
flutter build apk --relea


## Database schema
Filename: MyDatabase.db (unchanged from Part I)
Version: 2 (bumped from 1)

Part I (preserved)
sql
CREATE TABLE my_table (
  _id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  age INTEGER NOT NULL
);
Part II (added in version 2)
sql
CREATE TABLE folders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);

CREATE TABLE cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  suit TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  image_ref TEXT,
  folder_id INTEGER NOT NULL,
  FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
);

CREATE INDEX idx_cards_folder_id ON cards(folder_id);
Lifecycle hooks
onConfigure: PRAGMA foreign_keys = ON

onCreate: creates my_table + folders + cards + index (fresh installs)

onUpgrade(oldVersion < 2): creates folders + cards + index (keeps my_table intact)

Migration approach
The database filename is unchanged (MyDatabase.db), so an existing Activity 08
install finds the same file on open. The version number was increased from 1
to 2. SQLite sees the version bump, skips onCreate, and calls onUpgrade.
onUpgrade only runs the CREATE TABLE / CREATE INDEX statements for the
new catalogue tables — the Part I my_table is never touched, and no DROP,
DELETE, or reseed is performed.

Image reference choice
image_ref is a nullable TEXT column. It stores a reference (asset path, file
path, or URL), never the image bytes themselves. For this lab I left
image_ref NULL on all cards and rely on a suit-symbol fallback (♥ ♦ ♣ ♠)
rendered in the card list. This keeps the database compact, avoids broken-image
handling complexity, and matches the assignment's guidance that a nullable
reference with a fallback is sufficient. A network or asset image can be added
later by populating image_ref without any schema change.

Trade-off: A bundled asset works offline but inflates APK size and requires a
rebuild to change. A remote URL keeps the row small but fails without network.
Storing bytes in a BLOB would make each row self-contained but heavy. For a
sample card catalogue with no real artwork, NULL + suit fallback is the safest
choice and is what T6 verifies.

Test matrix (T1–T6)
All tests were run on emulator-5554 (Android 14, API 34). Fictional sample
data only. Console lines were captured from the Flutter debug console via
debugPrint() in the repository layer.

T1 / Upgrade & fresh creation
Subtest	Action	Expected	Observed	Pass
T1a	Launch version-2 helper against existing version-1 MyDatabase.db	Version-2 tables exist; all Part I rows preserved with same IDs/values	user_version = 2, foreign_keys = 1, folders+cards+idx_cards_folder_id present; my_table rows: [{_id:2, name:River, age:35}, {_id:3, name:Acorn, age:0}, {_id:4, name:Oak, age:130}]	✅
T1b	(not separately run — see limitations)	Fresh-install onCreate builds both Part I and catalogue schema	Verified by code inspection: onCreate calls _createPartOneTables then _createCatalogueTables. A separate disposable install was not performed within the lab window.	⚠️ partial
Evidence: evidence/T1_before.png, evidence/T1a_diagnostic.txt, evidence/T1a_diagnostics.png.

T2 / Parent-child create
Action	Expected	Observed	Pass
Create folders "Atlas" and "Harbor"	Two folder rows with distinct IDs	Folder IDs 1 (Atlas) and 2 (Harbor)	✅
Add two "Compass" cards to Atlas	Two distinct card IDs, Atlas count = 2	Card IDs 1 and 2, Atlas shows 2 cards	✅
Add one "Signal" card to Harbor (image_ref null)	Signal count = 1 under Harbor	Card ID 3, Harbor shows 1 card	✅
Evidence: evidence/T2_cards.png.

T3 / Edit identity
Subtest	Action	Expected	Observed	Pass
T3a	Edit card #1 ("Compass") → title "Compass revised", notes "Edited for T3", Save	One row updated; other Compass unchanged	Console: Updated card #1 -> affected 1 row(s)	✅
T3b	Open edit on the other Compass, type "SHOULD NOT SAVE", Cancel	No write; card unchanged	No Updated card line appeared; card still titled "Compass"	✅
T4 / Restart persistence
Subtest	Action	Expected	Observed	Pass
T4	Force-stop app via Android Settings (not Clear storage), relaunch same install	Same folders, IDs, cards, values, counts; no duplicate seeds	After force-stop and flutter run, Folders showed same counts, same card titles, same IDs. No seed duplication.	✅
Evidence: evidence/T4_before.png, evidence/T4_after.png.

T5 / Card delete & cascade
Subtest	Action	Expected	Observed	Pass
T5a	Cancel delete of Compass revised (card #1)	No write	No Deleted card line in console	✅
T5b	Confirm delete of card #1	1 row deleted; Atlas count → 1	Deleted card #1 -> affected 1 row(s)	✅
T5c	Cancel delete of Atlas folder	No write	No Deleted folder line in console	✅
T5d	Confirm delete of Atlas folder	Folder row deleted; cascade removes remaining Compass; Harbor/Signal intact	Deleted folder #1 -> affected 1 row(s); Folders shows only Harbor (1 card); Signal untouched	✅
Cascade check	Query SELECT COUNT(*) FROM cards after T5d	1 card (Signal only)	T5 cascade check — total cards in cards table: [{COUNT(*): 1}]	✅
Evidence (optional): evidence/T5_after_cascade.png.

T6 / Validation & fallback
Subtest	Action	Expected	Observed	Pass
T6a	Open Signal (image_ref = null)	Suit fallback shown; no error	♣ Clubs badge displayed; no image attempted	✅
T6b	Add card with whitespace-only title	"Title is required." error; no write	Red inline error under Title; no Inserted card line	✅
T6c	Create folder with blank name	"Folder name is required." error; no write	Red inline error; no Inserted folder line	✅
T6d	Create folder named "Harbor" (already exists)	UNIQUE constraint rejection; no write	Could not create folder: DatabaseException(UNIQUE constraint failed: folders.name (code 2067 SQLITE_CONSTRAINT_UNIQUE)) shown in UI; only one Harbor remains	✅
Evidence: evidence/T6_duplicate_folder.png.

Evidence folder contents
text
evidence/
  T1_before.png               Pre-upgrade Part I roster (3 rows: River, Acorn, Oak)
  T1a_diagnostic.txt          PRAGMA output confirming v2 + FKs + tables + preserved rows
  T1a_diagnostics.png         Terminal screenshot of the diagnostic block
  T2_cards.png                Folders screen showing Atlas 2 / Harbor 1
  T4_before.png               State captured before force-stop
  T4_after.png                Same state after relaunch
  T5_after_cascade.png        Folders screen after Atlas delete (Harbor only)
  T6_duplicate_folder.png     UNIQUE constraint rejection on duplicate folder name
  analysis_output.txt         flutter analyze output (No issues found!)
Old artifacts from a prior attempt are kept in evidence/_old/ and are not part
of the submission.

Rubric mapping
Criterion	Where it lives
Schema & data preservation (25)	database_helper.dart (onCreate/onUpgrade/onConfigure); T1 evidence
Models, repository & CRUD (25)	Folder, CardRecord, FolderWithCount classes; all repository methods; folder_screen.dart, card_screen.dart
Image handling & usability (10)	Nullable image_ref; _SuitBadge fallback; empty/loading/error states in both screens
Testing & evidence (20)	Test matrix above; evidence/ folder; release APK smoke test
Critical thinking & AI Lab (15)	Separate Lastname_Firstname_CriticalThinking.docx
README & individual delivery (5)	This file; github_link.txt; APK; DOCX
Known limitations
T1b (fresh install) not independently run: The lab window did not allow
spinning up a separate app installation with a distinct package ID. The
onCreate path is present and code-inspected but not separately demonstrated.
No data was destroyed to test this.

Single emulator target: Only emulator-5554 (Android 14, API 34) was used.
iOS/Windows/web targets were intentionally not used (this activity's sqflite
workflow is Android/iOS-only).

No image bytes stored: All cards currently have image_ref = NULL; the
suit-symbol badge is the fallback. A real image reference was not exercised
end-to-end.

flutter analyze clean at time of writing; no unresolved findings.

References
sqflite package: https://pub.dev/packages/sqflite

Flutter SQLite recipe: https://docs.flutter.dev/cookbook/persistence/sqlite

SQLite foreign keys: https://www.sqlite.org/foreignkeys.html

SQLite ALTER TABLE: https://www.sqlite.org/lang_altertable.html

Course materials: In-Class Activity 09 assignment page and lecture companion

AI / assistance attribution
Course assignment text and lecture companion used as reference.

Code review and structural guidance received during this session.

No AI tool was used to generate test results; all IDs, counts, and console
lines were observed on the running app.