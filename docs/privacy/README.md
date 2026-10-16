# Bantay Ulang privacy implementation and release review

Reviewed 15 October 2026. These are preparation artifacts, not a certification of
Google Play compliance or evidence of deployed Firebase configuration.
The official privacy/deletion contact `quadlabs2026@gmail.com` was supplied by
the project owner in this task. No legal publisher name was inferred from it.

## Verified integration

| Service | Current mobile integration | Evidence |
| --- | --- | --- |
| Firebase Authentication | Yes: email/password registration/sign-in, verification, resets, UID/session | `pubspec.yaml:38-40`, `pubspec.lock`, `lib/signup.dart:276`, `lib/signup.dart:387`, `lib/offline/session_controller.dart:15` |
| Cloud Firestore | Yes: accounts, tasks, readings, alerts, growth/mortality records, settings, indicators | `lib/landing_page.dart:147`, `lib/tasks.dart:54`, `lib/logs.dart:122`, `lib/offline/sync_backend.dart:114` |
| Realtime Database | No dependency or application API calls found | `pubspec.yaml`, `pubspec.lock`, `lib/` |
| FCM | No dependency, token registration, or messaging API calls found | `pubspec.yaml`, `lib/notification_service.dart:43` |
| Firebase Storage | No dependency, upload, or Storage API calls found | `pubspec.yaml`, `lib/profile.dart:110` (profile changes write an address to Firestore) |
| Analytics / Crashlytics | No corresponding SDK integration or application calls found | `pubspec.yaml`, `pubspec.lock`, `lib/` |

`flutter_local_notifications` generates local notifications from Firestore
listeners (`lib/landing_page.dart:179`, `lib/tasks.dart:54`). It is not FCM and does
not guarantee delivery when the process is stopped. Permission requests and
notification channels are in `lib/notification_service.dart:52-91`; notification
IDs and seen/shown state are stored in SharedPreferences, not uploaded as tokens.

Account records contain name, email, UID, role, approval/verification status, and
timestamps (`lib/signup.dart:393`). Optional profile address is written by
`lib/profile.dart:118`. Firebase Auth receives the password; it is not copied to
Firestore. Submission attribution copies UID/name/email to some records
(`lib/offline/sync_backend.dart:183-188`). Plant measurements are stored in `logs`;
prawn measurements also go to `ulang_growth_records`; mortality records go to
`mortality_records` and logs. Recorded tasks update `tasks.status`.

Firestore persistence caches records. SQLite holds approval/profile metadata and
view-confirmation timestamps (`lib/offline/offline_store.dart:24-30`), and login
lockout state lives in preferences (`lib/signup.dart:94-135`). Seven-day approval
validity (`lib/offline/offline_models.dart:27-36`) is not a seven-day deletion timer.
Logout clears approval and signs out (`lib/offline/session_controller.dart:212-245`)
without a general Firestore cache/prefs purge or server-record deletion.

Firebase Android Authentication also processes IP addresses, UID, app/SDK and
device/platform metadata; this is provider behavior described in
[Firebase's Android disclosure guide](https://firebase.google.com/docs/android/play-data-disclosure).
Firestore sends the signed-in UID with requests. Absence of FCM does **not** mean
there are no identifiers or technical SDK data. The guide describes latest SDKs;
verify the actual native versions/transitive SDKs in the release artifact.

The companion web repository's `firestore.rules` was inspected read-only.
Its source has role/approval/ownership checks, but also permits unauthenticated
writes to some sensor-ingestion paths (`firestore.rules:178-197`) and other
public paths. No claim was made that the source rules are deployed or that all
records are private to their creator. The web user-management implementation
uses `deleteDoc(users/{uid})` (`web/pages/shared/js/users.js:129`, `:218`), which
does not prove Firebase Auth or linked records are deleted. The companion site's
report modules also show administrator reporting/export surfaces. They were not
modified and a full web/backend/Console audit remains outside this client review.

## In-app navigation and common content

- Profile → Settings → Privacy Policy.
- Login **and** registration → Privacy Policy (available before authentication).
- Public routes `/privacy` and `/settings`; the policy page itself reads only a
  bundled asset and needs no Firebase account or internet request.
- Text is selectable, with responsive scrolling and the existing teal/Poppins
  styling. This is an information link, not a new consent checkbox or auth gate.
- `assets/privacy/privacy_policy.json` is the content source for Flutter and the
  two HTML pages. The public dates, review banner, provider-reference footer,
  and specified technical passages were removed at the project owner's request.
  The release review items remain documented in this internal checklist.

Generate web pages after changing policy text:

```powershell
python tool/generate_privacy_policy.py
python tool/generate_privacy_policy.py --check
```

`index.html` and `account-deletion.html` are standalone responsive HTML, with an
embedded existing logo and no scripts, external fonts, trackers, cookies, or
Firebase calls. Upload both to a public HTTPS directory; the relative links
must remain together. No page has been deployed and no production URL invented.
The deletion page opens a prefilled email addressed to the confirmed contact;
users review and send it themselves. It does not delete anything or pretend a
request has been submitted merely by clicking the link.

## Data Safety form preparation (review before submission)

These are candidate mappings, not a completed Play Console declaration.

| Verified information | Candidate Data Safety type | Purpose / review |
| --- | --- | --- |
| Full name, email, UID | Personal info: Name, Email address, User IDs | Account management, app functionality, authentication/security |
| Optional typed profile address | Personal info: Address | Profile/account functionality; not GPS location |
| Role, approval status | Other personal info, where applicable | Access/account management; confirm category in Console |
| Recorder-linked plant/prawn/mortality entries and task text | App activity: Other user-generated content / Other actions as applicable | Farm functionality and management; classify actual collected fields |
| IP and app/SDK/device metadata processed by Auth | Review the matching SDK disclosures and Console categories | Authentication/abuse prevention; do not infer GPS collection or omit SDK processing |
| Local approval/cache, notification IDs, lockout counters | Device-local unless uploaded as part of another field | Distinguish on-device storage from off-device collection |

User-provided information sent to Firebase is collected off-device. Disclosure of
Google/Firebase as a processor is still required in the policy. Whether a transfer
counts as “sharing” in the Data Safety form depends on the service-provider
exception and actual downstream use; do not automatically mark all Firebase
transfers as sharing or select “no sharing” without reviewing exports and other
processors. Avoid classifying prawn water quality as human health information.
Review required/optional inputs, ephemeral processing, and deletion answers per
field rather than making one blanket assertion.
[Google Play Data Safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469)
defines these distinctions. Firebase Analytics is absent; farm growth analysis
is not evidence that Google Analytics is collecting user behavior.

## Required publication and configuration checklist

- [x] Official privacy contact provided: `quadlabs2026@gmail.com`.
- [x] App identified as Bantay Ulang; actual Auth/Firestore usage disclosed.
- [x] Policy accessible in-app before sign-in and from Settings.
- [ ] Confirm the legal publisher/operator and match the Play listing. “Bantay
  Ulang development team” is descriptive, not an invented company identity.
- [ ] Approve concrete retention periods for profiles, attributed farm records,
  tasks, request correspondence, backups, and administrator exports; specify
  reasons/durations for any retention exception. No timer was found in client code.
- [ ] Confirm a monitored mailbox, identity-verification procedure, request
  response/fulfilment time, and completion confirmation for deletion requests.
- [ ] Implement a readily discoverable **in-app account-deletion initiation**
  option (native request flow or functional link to the published request page).
  Reading an email address inside the policy is not a verified initiation flow.
- [ ] Publish `account-deletion.html` on HTTPS and enter that functional URL in
  Play Console. Test composing/sending a request and fulfilment end to end.
- [ ] Coordinate Auth deletion with `users/{uid}`, `logs` (`createdBy`, embedded
  name/email), `ulang_growth_records`/`mortality_records` (`recordedBy`), assigned
  tasks, audit/history/exports, subcollections, and other backend copies. Verify
  any permitted retained data is justified, minimized, and disclosed. Deleting
  an Auth account or a profile alone is insufficient; disabling is not deletion.
- [ ] Review whether a configured deletion extension/backend process exists in
  the deployed project. None was established by this mobile-code audit. A UID
  path-only extension would miss random-ID documents with recorder fields unless
  specifically configured: see [Firebase Delete User Data](https://firebase.google.com/docs/extensions/official/delete-user-data).
- [ ] Verify deployed Firestore Rules against actual account, farm, assignment,
  and ownership requirements; review unauthenticated ingestion integrity. Keep
  Rules unchanged while doing this UI task. Test with an emulator separately.
- [ ] Review Console/IAM administrator access, locations/subprocessors, App Check,
  account protections, backups, and releases. MFA/App Check/custom local encryption
  or a particular region were not confirmed and are not claimed in the policy.
- [ ] Inspect a fresh release dependency graph and merged permissions; current
  source has no FCM/Analytics/Crashlytics/Storage/Realtime Database plugin, but old
  build artifacts are not evidence of the current release. Verify SDK data handling.
- [ ] Review notification-permission prompt timing. The existing startup calls
  `NotificationService.initialize()` before the first app screen, and that method
  requests notification permission; determine whether further contextual disclosure
  or consent is needed for the release. This privacy UI task preserves that flow.
- [ ] Review additional backend functions, sensors, the companion web app,
  exported reports, email processing, and the eventual policy host's logs.
- [x] Intended audience wording supplied by the owner: Bantay Ulang is not designed
  for users under 13 years of age.
- [ ] Match store-listing audience declarations to the intended audience. The
  policy wording does not add an age-verification flow or change registration.
- [ ] Review final retention/deletion wording and publication metadata. Dates are
  not displayed in the public policy at the owner's request. Regenerate HTML and
  rebuild the app together when the finalized wording changes.
- [ ] Publish the policy at an active, public, non-geofenced HTTPS URL that does
  not require sign-in, is not a PDF, and is not editable by visitors. Enter it in
  Play Console and keep the policy and Data Safety form consistent.

Account creation exists, so Google Play requires account-deletion initiation
inside and outside the app, plus handling associated user data with any justified
retention disclosed. The new external page is prepared, but its hosting and the
actual deletion process are not verified. See
[Google Play account-deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
and [User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311).

Provider-level HTTPS and Firestore default encryption disclosures are based on
[Firebase Android disclosures](https://firebase.google.com/docs/android/play-data-disclosure)
and [Firestore encryption documentation](https://firebase.google.com/docs/firestore/cmek),
not a claim of end-to-end, custom-key, or encrypted local storage.

## Files in this change

- `assets/privacy/privacy_policy.json`: shared policy wording and official contact.
- `lib/privacy_policy.dart`: public, offline-readable policy screen and asset model.
- `lib/settings.dart`: Settings/About with policy navigation and notification guidance.
- `lib/main.dart`: public policy/settings routes.
- `lib/signup.dart`: login/registration policy link, without changing auth logic.
- `lib/profile.dart`: Profile → Settings link, without changing profile saves.
- `pubspec.yaml`: register the single policy asset; dependencies unchanged.
- `tool/generate_privacy_policy.py`: reproducible HTML generation and parity check.
- `docs/privacy/index.html`: generated web policy.
- `docs/privacy/account-deletion.html`: generated external email request page.
- `docs/privacy/README.md`: evidence, release gaps, Data Safety preparation, file summary.
- `test/privacy_policy_test.dart`: public access, navigation, content and phone renders.

Earlier dashboard, splash/logo, and Back-message changes are retained. This task
does not deploy a website, submit Play Console forms, delete accounts/data, alter
Firebase rules/configuration, or silently change retention behavior.

## Initial integration verification

- Full suite: **267 tests passed** using `flutter test --no-pub --concurrency=1`.
  An earlier parallel run had 266 passes and one timeout in the existing SQLite
  version-1 upgrade test; the complete sequential rerun passed without changing it.
- Six new privacy tests cover bundled reading without Firebase initialization or
  sign-in, all ten sections, login/registration form preservation, Settings/Back,
  the actual app's public routes, and phone/landscape/enlarged-text rendering.
- Flutter policy, Settings, and login were rendered and inspected. Both HTML
  pages were rendered in an explicit 390-pixel iframe viewport and inspected.
  The mailto link is checked as a compose link; no request email was sent.
- Analyzer: no new diagnostics in the added privacy/settings code. The six-file
  analysis reports 38 existing informational notices in `main.dart`/`profile.dart`
  (37 opacity deprecations and one constructor-style suggestion), with no errors
  or warnings. `git diff --check` and the HTML content-parity check pass.
- Firebase Rules/configuration and unrelated existing work are preserved.
  Deployed Rules, release Data Safety answers, public HTTPS hosting, real mailbox
  handling, account deletion/backup fulfilment, and physical-device acceptance
  are not proven by these automated checks.

## Requested public-text revision

The passages specified by the owner were removed from the shared policy and both
public renderers. Children's Privacy now states that the app is not designed for
users under 13 years of age. This is audience wording; registration and backend
behavior are unchanged.

Revision validation: 18 privacy/startup tests passed; the changed screen and test
have no analyzer issues. App and web phone renders were inspected, generated HTML
matches the bundled text, and diff checks pass. Other existing work is preserved.
