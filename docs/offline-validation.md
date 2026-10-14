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

Unit/widget checks cover database migration across multiple accounts, preserved offline access/cache metadata, all four online-only submission kinds, repeated taps, server-check timeouts, network failures, account transitions, task changes, weekly mortality duplicates, paired records, and summary-update failure. The Android integration test uses real SQLite with simulated authentication and Firestore responses; it does not authenticate to the live project or validate deployed permissions.

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

## Device acceptance with an approved test account

1. Install the updated app over the previous build. Launch while connected. The saved-record panels and pending-sync labels must be absent. Confirm previously uploaded logs remain visible.
2. Sign in online with a verified, approved farm-user test account. Open Dashboard, Logs, Tasks, Yield, and Profile to preload data.
3. Disable Wi-Fi and mobile data. Previously downloaded data remains viewable under the existing seven-day approval window. A page not downloaded for this account must not show another account's cached data. The offline notice remains temporary.
4. Try valid Ulang, Plant, and Mortality submissions and an assigned task completion. Expect "Internet connection is required." Inputs remain and tasks stay pending. No local records are created.
5. Force-stop and reopen offline. Cached viewing and an unexpired approval remain available. There are no pending record panels. Reconnect: no discarded entries or blocked submissions upload automatically.
6. Submit each type online. A success message appears only after server confirmation. Confirm exactly one log per submission, atomic paired Ulang/Mortality records, matching observation timestamps, and the correct account identity. Task completion changes its server status to `done`.
7. Test Wi-Fi without internet and loss of connection during saving. Buttons recover on failure and input values remain. Check server records before retrying an unconfirmed save; an acknowledgment failure can leave its outcome uncertain. There is no app-level automatic retry.
8. Try repeated taps, logout/account switching during a save, rejected permissions, reassigned/deleted tasks, a changed farming cycle, and a second mortality submission for the same cycle/week. Rejected submissions must not modify unrelated records or show success for another account.
9. A growth-summary failure after a confirmed save must say the record was saved and must clear that completed form. Do not submit the record again. Summary recalculation is attempted after subsequent successful Ulang/Mortality saves; there is no persistent recalculation queue.
10. Verify logout ends offline access and the seven-day expiry blocks protected pages until the next online approval check. Use injected-clock tests rather than changing the phone clock.

## Production permissions and limitations

- Live permission checks require an approved account and an available Firebase project. Verify that existing permissions accept the transaction reads, paired writes, and deterministic mortality IDs. Report `permission-denied` errors; do not change Rules to make tests pass.
- The deterministic mortality ID retains its historical `offline_` prefix for compatibility with existing records. This naming does not mean the new app queues submissions.
- Existing legacy/web mortality records are recognized. Concurrent older clients using random document IDs still require production compatibility checks.
- Firebase Auth handles credentials. Saved approval metadata contains no passwords. Server-side suspension cannot be discovered during an outage; the existing seven-day offline-viewing limit remains.
- Simulated Firestore tests verify application logic, not the native SDK's transaction implementation or deployed Rules. A physical-device/live-account check remains necessary for production acceptance.
- Rebuild the real app after integration testing: `flutter build apk --debug -t lib/main.dart`. An APK produced by an integration run may contain the test runner.
