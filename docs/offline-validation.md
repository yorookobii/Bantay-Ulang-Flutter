# Offline viewing and online submissions

Ulang, Plant, Mortality, and task completions require internet and server confirmation. There is no local record queue, saved-record panel, upload worker, or reconnect-triggered upload. Firestore Rules and Firebase configuration are unchanged.

## Existing devices

The first launch of this version upgrades `bantay_offline.db` to version 2. The upgrade atomically drops the old `operations` and `recalculations` tables for **all accounts on that device**, including pending, interrupted, rejected, and synced local entries. Unsent local entries are permanently discarded, as requested. Already uploaded Firestore records remain on the server.

Saved approval metadata and cache timestamps remain. Firestore's downloaded-data cache remains available for offline viewing. This migration runs before account pages open; do not uninstall or clear app storage to perform the upgrade.

## Automated checks

```powershell
flutter test --no-pub --concurrency=1
flutter analyze --no-pub lib/offline
flutter test integration_test/offline_persistence_test.dart -d <android-device-id>
```

Unit/widget checks cover database migration across multiple accounts, preserved offline access/cache metadata, all four online-only submission kinds, repeated taps, server-check timeouts, network failures, account transitions, task changes, multiple mortality entries per week, retry deduplication, paired records, and summary-update failure. The Android integration test uses real SQLite with simulated authentication and Firestore responses; it does not authenticate to the live project or validate deployed permissions.

The old queue persistence and process-restart synchronization tests have been retired. Prior results for those tests describe the previous feature and do not establish current submission behavior.

## Validation completed on 2026-10-11

- Full unit/widget regression suite: **148 passed** with `flutter test --no-pub --concurrency=1`.
- Final submission checks: **70 passed**, including the four additional delayed/lost-acknowledgment cases added after the full suite, and the final task-context guard.
- Android integration: **2 passed** on `Medium_Phone_API_36.1` (`emulator-5554`). Real SQLite removes legacy queues for both seeded accounts while preserving cached-viewing metadata and an approved offline session. Ulang/Plant forms reject offline attempts and save after reconnecting in the same simulated approved session.
- Focused analysis: no issues. Screen analysis matches the starting worktree's **92 existing notices**, with no new findings or errors. `git diff --check` passed.
- Normal debug app rebuilt with `flutter build apk --debug --no-pub -t lib/main.dart`, replacing the test-runner artifact.
- Firebase configuration, Firestore Rules, dependencies, authentication/profile behavior, and unrelated existing edits were not changed by this work. Native validation only refreshed generated local Android build metadata.
- These results do not establish deployed Firestore permissions or physical-device performance. No live account credentials were used and the connected physical phone was not modified.

Diagnostic logs: `build/online-submission-validation/`.

## Mortality validation on 2026-10-15

- Removed the one-entry-per-week restriction. Four separate one-death submissions in the same week create four mortality/log pairs and reduce survival from 100% to 96% for stock of 100. The existing See More control reveals all four cards.
- Full unit/widget suite: **269 passed**; focused submission/backend/form checks: **76 passed**. Coverage includes retries of the same operation, existing weekly-ID/web records, changed cycles, approval/session changes, and record deletion/replacement.
- Local Firestore emulator with the unchanged checked-in Rules: four same-week paired submissions accepted, an older record preserved, combined survival updated, and a suspended account's paired write rejected without partial records.
- Focused analysis retains the same **17 existing warnings/info notices** as before the change, with no new diagnostics. Existing unrelated files match their starting hashes.
- Android release build passed with `flutter build apk --release`: `build/app/outputs/flutter-apk/app-release.apk`. The initial `--no-pub` attempt encountered stale generated integration-test registration; the normal build regenerated release tooling successfully. Dependency versions and tracked Android configuration were unchanged.
- Diagnostic logs and the local Rules probe: `build/mortality-event-validation/`. These checks do not establish physical-device or deployed-Firebase acceptance.

## Mortality card cycle-week display

Mortality cards show `Linggo ng cycle: N`, calculated from each entry's `observedAt` (or `createdAt` for older entries) and the latest admin System Parameters `growth_indicators.cycleStart`. They use the same seven-day cycle intervals as the admin analytics. Entries on opposite sides of a week boundary retain different recorded weeks. Each card keeps its existing recording-date stamp; the redundant cycle date range has been removed. Changing the admin cycle start recalculates the displayed week through the existing cycle subscription.

Missing cycle settings or recording dates show an unavailable label. Entries dated before the current admin cycle start are identified as belonging before the current cycle, rather than assigned a week in it.

This is a display-only change. Each entry's date, saved `weekNumber`, mortality count, paired log, and the calculations used by web analytics remain unchanged. The existing cycle subscription supplies the parameters; the display adds no Firestore queries or writes.

Validation: **275 unit/widget tests passed**, including admin-cycle changes, exact seven-day boundaries, observation-time priority, legacy timestamp fallback, missing settings/dates, pre-cycle records, and a 390-pixel-wide layout. Focused analysis retains the same **17 existing warnings/info notices**, with no new diagnostics. Logs: `build/admin-cycle-week-validation/`. Physical-device and deployed-Firebase acceptance remain unverified.

The release build passed with `flutter build apk --release`; the updated installer is `build/app/outputs/flutter-apk/app-release.apk`.

## Current-cycle Logs graph

The weekly growth graph includes only records whose observation timestamp is on or after the current admin `cycleStart`, falling back to `createdAt` for legacy records. Earlier-cycle observations are excluded rather than folded into Week 1, including observations uploaded after the new cycle began. Exact cycle-start and seven-day boundaries retain their full timestamp precision. If the admin cycle start is unavailable, the graph stays empty instead of using the earliest historical record as its baseline. Historical records remain stored and the graph controls are unchanged.

Validation on 2026-10-16: **278 unit/widget tests passed**, including current-cycle aggregation, delayed uploads, legacy timestamps, admin cycle changes, empty-cycle graphs, and mortality week/date-stamp preservation. Focused analysis retains the same **17 existing warnings/info notices**, with no new diagnostics. Logs: `build/current-cycle-graph-validation/`. These automated checks do not establish physical-device or deployed-Firebase acceptance.

The updated release APK passed `flutter build apk --release` and is available at `build/app/outputs/flutter-apk/app-release.apk`.

## Device acceptance with an approved test account

1. Install the updated app over the previous build. Launch while connected. The saved-record panels and pending-sync labels must be absent. Confirm previously uploaded logs remain visible.
2. Sign in online with a verified, approved farm-user test account. Open Dashboard, Logs, Tasks, Yield, and Profile to preload data.
3. Disable Wi-Fi and mobile data. Previously downloaded data remains viewable under the existing seven-day approval window. A page not downloaded for this account must not show another account's cached data. The offline notice remains temporary.
4. Try valid Ulang, Plant, and Mortality submissions and an assigned task completion. Expect "Internet connection is required." Inputs remain and tasks stay pending. No local records are created.
5. Force-stop and reopen offline. Cached viewing and an unexpired approval remain available. There are no pending record panels. Reconnect: no discarded entries or blocked submissions upload automatically.
6. Submit each type online. A success message appears only after server confirmation. Confirm exactly one log per submission, atomic paired Ulang/Mortality records, matching observation timestamps, and the correct account identity. Task completion changes its server status to `done`.
7. Test Wi-Fi without internet and loss of connection during saving. Buttons recover on failure and input values remain. Check server records before retrying an unconfirmed save; an acknowledgment failure can leave its outcome uncertain. There is no app-level automatic retry.
8. Record separate single-death mortality entries in the same cycle/week. Each confirmed submission must create its own mortality/log pair, preserve earlier records, and reduce survival according to the combined deaths. Also try repeated taps, logout/account switching during a save, rejected permissions, reassigned/deleted tasks, and a changed farming cycle. Rejected submissions must not modify unrelated records or show success for another account.
9. A growth-summary failure after a confirmed save must say the record was saved and must clear that completed form. Do not submit the record again. Summary recalculation is attempted after subsequent successful Ulang/Mortality saves; there is no persistent recalculation queue.
10. Verify logout ends offline access and the seven-day expiry blocks protected pages until the next online approval check. Use injected-clock tests rather than changing the phone clock.

## Production permissions and limitations

- Live permission checks require an approved account and an available Firebase project. Verify that existing permissions accept the transaction reads and paired writes. Report `permission-denied` errors; do not change Rules to make tests pass.
- New mortality records use the submission ID shared with their log, allowing multiple entries in the same week while keeping retries of that operation idempotent. Enter deaths for the current entry rather than a cumulative weekly total.
- Existing weekly-ID and legacy/web mortality records remain unchanged and contribute to the survival total. Older app versions still enforce their own weekly restriction until updated.
- Firebase Auth handles credentials. Saved approval metadata contains no passwords. Server-side suspension cannot be discovered during an outage; the existing seven-day offline-viewing limit remains.
- Simulated Firestore tests verify application logic, not the native SDK's transaction implementation or deployed Rules. A physical-device/live-account check remains necessary for production acceptance.
- Rebuild the real app after integration testing: `flutter build apk --debug -t lib/main.dart`. An APK produced by an integration run may contain the test runner.
