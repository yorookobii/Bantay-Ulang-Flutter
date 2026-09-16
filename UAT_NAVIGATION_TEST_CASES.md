# Bantay Ulang Mobile Application
## User Acceptance Testing (UAT) & Navigation Test Cases Specification

---

## 1. Document Overview

### 1.1 Purpose
This document provides a comprehensive navigation map and formal User Acceptance Testing (UAT) test cases for the **Bantay Ulang** Flutter mobile application. It is designed for quality assurance (QA) testers, farm operators, product owners, and stakeholders to systematically validate all user journeys, route transitions, modal interactions, and error states.

### 1.2 Target Audience
- **QA & Testing Teams**: Test case execution and regression verification.
- **End Users (Farm Technicians / Farm Owners)**: UAT sign-off and usability validation.
- **Developers**: Reference for routing contracts, route guards, and UI navigation triggers.

### 1.3 Target Environment
- **Platform**: Android (APK / Flutter Engine with Impeller Vulkan backend) / iOS
- **Supported Resolutions**: Mobile (360x640 to 1080x2400) and Tablet viewports
- **Backend**: Firebase Authentication & Cloud Firestore (Real-time collections: `sensor_readings`, `growth_indicators`, `tasks`, `alerts`, `users`, `logs`)

---

## 2. Application Navigation Architecture & Sitemap

```
                          [ App Launch ]
                                │
                                ▼
                       ┌─────────────────┐
                       │    LoginPage    │  (Welcome / Splash)
                       └────────┬────────┘
                                │  "Get Started"
                                ▼
                       ┌─────────────────┐
                       │   SignupPage    │  (Mode Switcher: Sign-In / Sign-Up)
                       └────────┬────────┘
                                │  Successful Auth (Role: 'user', verified & active)
                                ▼
                 ┌─────────────────────────────┐
                 │     DashboardPage Shell     │  (Top Bar + Bottom Nav + PopScope)
                 └──────────────┬──────────────┘
                                │
        ┌───────────────────────┼───────────────────────┬───────────────────────┐
        ▼                       ▼                       ▼                       ▼
  ┌───────────┐           ┌───────────┐           ┌───────────┐           ┌───────────┐
  │   Tab 0   │           │   Tab 1   │           │   Tab 2   │           │   Tab 3   │
  │ Dashboard │           │  Gawain   │           │    Ani    │           │   Logs    │
  │   View    │           │  (Tasks)  │           │  (Yield)  │           │  (Data)   │
  └─────┬─────┘           └─────▲─────┘           └─────▲─────┘           └───────────┘
        │                       │                       │
        │─── Tap Ulang Hero ────┼───────────────────────┘
        │─── Tap Ani Footer ────┼───────────────────────┘
        │─── Tap Babala Task ───┘
        │
        ▼  (Tap Avatar Icon)
  ┌───────────┐
  │ProfilePage│ ◄─── (Sidebar Drawer / Back Navigation)
  └─────┬─────┘
        │  (Log Out Button)
        ▼
  ┌───────────┐
  │  Confirm  │ ── Confirm ──► Sign Out ──► Redirect to LoginPage
  │  Dialog   │ ── Cancel ───► Stay on ProfilePage
  └───────────┘
```

---

## 3. Global Route Inventory

| Route Path / Screen | Widget Class | Trigger / Entry Point | Access Guards | Key Navigational Outlets |
|---|---|---|---|---|
| `/login` | `LoginPage` | Initial launch route (`main.dart`) | None (Public) | "Get Started" button -> `SignupPage` |
| Direct / Child | `SignupPage` | Tapped "Get Started" from `LoginPage` | Rate limiter (3 attempts / 3 min lockout) | Mode toggle (Log in / Create an Account); Forgot Password; Auth -> `/dashboard` |
| `/dashboard` | `DashboardPage` | Successful login / Session restoration | Auth required (`role == 'user'`, `emailVerified`, `status == 'active'`) | Bottom Nav (4 tabs), Notification Dropdown, Profile Page (`/profile`) |
| Tab Index 0 | `_buildDashboardView` | Bottom Nav index `0` | Embedded inside `DashboardPage` | Tap Ulang Hero -> Tab 2; Tap Ani Footer -> Tab 2; Tap Babala -> Tab 1 |
| Tab Index 1 | `TasksPage` | Bottom Nav index `1`, notification tap, or Babala alert tap | Authenticated user (`assignedTo == uid`) | Mark task as Done; Refresh |
| Tab Index 2 | `YieldEstimationPage` | Bottom Nav index `2` or Dashboard overview tap | Authenticated user | Recalculate; View RF projection & cycle factors |
| Tab Index 3 | `LogsPage` | Bottom Nav index `3` | Authenticated user | Tab forms (Ulang, Mortality, Plant); Growth Chart; See More lists |
| Child Screen | `ProfilePage` | Avatar icon in `DashboardPage` Top Bar | Authenticated user | Back button -> Dashboard; Drawer menu; Logout -> `/login` |

---

## 4. UI Shell Navigation Controls

### 4.1 Persistent Top Bar (`_buildTopBar`)
- **App Logo & Title**: Displays "Bantay Ulang" branding with aquaponic water drop badge.
- **Notification Bell**: Toggles the overlay dropdown with active notification count badge (`9+` supported).
- **Profile Avatar**: Displays user initials (e.g. "JS"). Tapping navigates (`Navigator.push`) to `ProfilePage`.

### 4.2 Dynamic Bottom Navigation Bar (`_buildBottomNavBar`)
- **Tabs**:
  - `0`: **Dashboard** (Home icon)
  - `1`: **Gawain** (Task clipboard icon)
  - `2`: **Ani** (Analytics chart icon)
  - `3`: **Logs** (List icon)
- **Auto-Hide Behavior**:
  - Scrolling down on vertical lists hides the navbar smoothly.
  - Scrolling up or reaching the bottom edge of content auto-reveals the navbar.
  - Single tap on content toggles navbar visibility.

### 4.3 Hardware & System Back Navigation (`PopScope`)
- If the notification dropdown is visible, pressing Back closes the dropdown.
- If a user switched tabs (e.g., Dashboard -> Gawain -> Ani), pressing Back returns to the previous tab history (`_navHistory.removeLast()`).
- On root of navigation history, pressing Back prompts system exit.

---

## 5. Structured UAT Test Cases

### Category A: Authentication & Onboarding Navigation

#### TC-AUTH-001: Splash Screen to Sign-Up / Login Navigation
- **Objective**: Verify that the user can navigate from the welcome splash screen to the authentication screen.
- **Preconditions**: Application is installed and launched. User is not currently authenticated.
- **Steps**:
  1. Launch the Bantay Ulang app.
  2. Observe the initial screen displaying the background hero image and app title.
  3. Tap the **"Get Started"** button.
- **Expected Result**: The app smoothly transitions to the `SignupPage` with the Mode Switcher set to "Log in".

---

#### TC-AUTH-002: Mode Toggle Between "Log in" and "Create an Account"
- **Objective**: Verify seamless switching between login and registration forms without navigation delay or state loss.
- **Preconditions**: User is on `SignupPage`.
- **Steps**:
  1. Observe the top pill control displaying "Log in" (active) and "Create an Account".
  2. Tap **"Create an Account"**.
  3. Verify form fields: Full Name, Email Address, Password, Confirm Password appear.
  4. Tap **"Log in"**.
  5. Verify form fields: Email Address, Password, "Forgot Password?" link appear.
- **Expected Result**: Mode updates instantly with smooth pill indicator slide animation. Input controllers clear appropriately.

---

#### TC-AUTH-003: Rate Limiting and Lockout Navigation
- **Objective**: Verify that 3 consecutive failed login attempts trigger the 3-minute lockout screen state.
- **Preconditions**: User is on `SignupPage` in "Log in" mode.
- **Steps**:
  1. Enter a valid email and an incorrect password. Tap **"Log in"**. Observe remaining attempts warning (2 attempts left).
  2. Enter an incorrect password again. Tap **"Log in"**. Observe warning (1 attempt left).
  3. Enter an incorrect password a third time. Tap **"Log in"**.
- **Expected Result**:
  - The submit button changes state to `Locked (03:00)`.
  - A red error banner appears: *"Naka-lock ang iyong account. Subukan muli pagkalipas ng 03:00."*
  - Countdown timer decrements second-by-second in real-time.
  - Submit button remains disabled during the lockout period.

---

#### TC-AUTH-004: Password Reset Request Flow
- **Objective**: Verify password reset modal navigation and feedback.
- **Preconditions**: User is on `SignupPage` in "Log in" mode.
- **Steps**:
  1. Enter user email address into the Email field.
  2. Tap **"Forgot Password?"**.
- **Expected Result**: A success notification banner indicates: *"Naipadala ang password reset link. Tingnan ang iyong inbox."*

---

#### TC-AUTH-005: Role & Account Status Route Guarding
- **Objective**: Verify that non-farm users or pending accounts are prevented from entering the mobile dashboard.
- **Preconditions**: Test credentials for:
  - Account A: `role == 'admin'` or `'technician'`
  - Account B: `emailVerified == false`
  - Account C: `status == 'pending'`
- **Steps**:
  1. Attempt login with Account A -> Observe redirection blocked with message directing user to web portal.
  2. Attempt login with Account B -> Observe redirection blocked with prompt to verify email via inbox.
  3. Attempt login with Account C -> Observe redirection blocked with message indicating pending admin approval.
- **Expected Result**: User is automatically signed out; navigation to `/dashboard` is strictly blocked.

---

#### TC-AUTH-006: Successful Login Navigation to Dashboard
- **Objective**: Verify authorized farm user can log in and reach the Dashboard.
- **Preconditions**: Account has `role == 'user'`, `emailVerified == true`, and `status == 'active'`.
- **Steps**:
  1. Input registered email and password.
  2. Tap **"Log in"**.
- **Expected Result**:
  - Loading spinner appears briefly on the submit button.
  - `Navigator.pushReplacementNamed` navigates to `/dashboard`.
  - Welcome greeting ("Magandang Araw!") and dashboard header load cleanly.

---

### Category B: Dashboard & KPI Hierarchy Navigation

#### TC-DASH-001: Top App Bar Notification Dropdown Navigation
- **Objective**: Verify notification dropdown overlay opens, displays alerts, and allows outside-tap dismissal.
- **Preconditions**: User is on `DashboardPage`.
- **Steps**:
  1. Observe the notification bell icon on the top right (check unread badge if alerts exist).
  2. Tap the notification bell icon.
  3. Verify the dropdown card opens on the upper right displaying active alerts and pending tasks.
  4. Tap anywhere outside the dropdown card.
- **Expected Result**: Dropdown opens cleanly on tap and closes immediately when tapping outside.

---

#### TC-DASH-002: Notification Dropdown Direct Link to Tasks
- **Objective**: Verify tapping a task notification inside the dropdown redirects to the Gawain tab.
- **Preconditions**: Notification dropdown is open with at least one notification item.
- **Steps**:
  1. Tap an assigned task item inside the notification dropdown.
- **Expected Result**:
  - Notification dropdown closes automatically.
  - Bottom navigation switches to Tab 1 (`Gawain`).
  - The tasks view is displayed.

---

#### TC-DASH-003: Navigation to User Profile Page
- **Objective**: Verify tapping the profile avatar circle navigates to the Profile screen.
- **Preconditions**: User is on `DashboardPage`.
- **Steps**:
  1. Observe user initials circle in the top right corner of the Top Bar.
  2. Tap the profile avatar circle.
- **Expected Result**: Screen navigates to `ProfilePage` (`Navigator.push`) displaying full name, email, role, and address.

---

#### TC-DASH-004: Living Assets Hierarchy — Ulang Yield Tap Navigation
- **Objective**: Verify that tapping the Ulang Harvest card inside the Living Assets hero card redirects directly to the Ani (Yield Estimation) tab.
- **Preconditions**: User is on Tab 0 (`Dashboard`).
- **Steps**:
  1. Directly below the greeting header, locate the **Living Assets** hero card.
  2. Verify the left card displays:
     - Scale icon (`Icons.scale_rounded`) with circular teal background
     - Title: "Inaasahang Ani"
     - Subtitle: "Ulang"
     - Large bold kg yield metric (e.g. `24.5 kg` or `Pending`)
     - Health status badge (e.g. `MALUSOG` / `NORMAL`) with dot indicator
     - Interactive corner chevron arrow
  3. Tap the **Inaasahang Ani** card.
- **Expected Result**: Bottom navigation bar immediately switches to Tab 2 (`Ani`) displaying the full yield and revenue estimation breakdown.

---

#### TC-DASH-005: Living Assets Hierarchy — Plant Status Display Validation & Tap Navigation
- **Objective**: Verify that plant health status card is displayed alongside Ulang yield inside the Living Assets hero card and supports tap navigation.
- **Preconditions**: User is on Tab 0 (`Dashboard`).
- **Steps**:
  1. Directly below the greeting header, locate the **Living Assets** hero card.
  2. Verify the right card displays:
     - Plant/Eco icon (`Icons.eco_rounded`) with circular emerald background
     - Title: "Mga Halaman"
     - Subtitle: "Biofilter"
     - Health metric text (e.g. `Maayos` or `Malusog`)
     - Status badge (e.g. `MAAYOS` / `MALUSOG`) with dot indicator
     - Interactive corner chevron arrow
  3. Tap the **Mga Halaman** card.
- **Expected Result**: Bottom navigation bar immediately switches to Tab 2 (`Ani`) displaying the full harvest and growth indicators.

---

#### TC-DASH-006: Water Parameters Grid Organization Below Living Assets
- **Objective**: Verify the 6 water parameters are cleanly organized in a 2-column grid directly below the Living Assets hero card.
- **Preconditions**: User is on Tab 0 (`Dashboard`).
- **Steps**:
  1. View the dashboard directly below the Living Assets hero card.
  2. Verify the 6 water parameter cards are arranged in 3 clean rows:
     - Row 1: pH Level & Dissolved Oxygen
     - Row 2: Temperatura & Salinity / TDS
     - Row 3: Turbidity & Lebel ng Tubig (Water Level)
  3. Verify each card displays: Icon, parameter title, large reading value, and status pill badge (NORMAL, MATAAS, MABABA, etc.).
- **Expected Result**: All cards render uniformly in a clean 2-column layout without redundant section headers, overflow, or clipping.

---

#### TC-DASH-007: Babala / Urgent Notification Action Navigation
- **Objective**: Verify urgent water warnings allow one-tap navigation to the assigned corrective tasks.
- **Preconditions**: At least one active alert exists in Firestore or default alerts are rendered.
- **Steps**:
  1. Scroll to the **"Babala"** cards below the water sensor grid.
  2. Read alert message and priority badge (`URGENT`).
  3. Tap **"Tingnan ang gawain →"**.
- **Expected Result**: Bottom navigation bar switches to Tab 1 (`Gawain`) so the user can address the task.

---

### Category C: Tab Navigation & Gesture Control

#### TC-NAV-001: Bottom Navigation Bar Tab Switching
- **Objective**: Verify clicking on any of the 4 bottom navigation items switches views properly.
- **Preconditions**: User is on `DashboardPage`.
- **Steps**:
  1. Tap **"Gawain"** (Tab 1) -> Verify `TasksPage` renders.
  2. Tap **"Ani"** (Tab 2) -> Verify `YieldEstimationPage` renders.
  3. Tap **"Logs"** (Tab 3) -> Verify `LogsPage` renders.
  4. Tap **"Dashboard"** (Tab 0) -> Verify `DashboardPage` main view renders.
- **Expected Result**: `IndexedStack` maintains state across tabs without flickering or reloading.

---

#### TC-NAV-002: Tap-to-Toggle Navbar Visibility
- **Objective**: Verify that a tap gesture on the screen toggles the bottom navigation bar to maximize viewing area.
- **Preconditions**: User is viewing any tab on `DashboardPage`.
- **Steps**:
  1. Tap once on an empty area of the screen (without dragging/scrolling).
  2. Observe the bottom navbar slides down and hides.
  3. Tap once on the screen again.
  4. Observe the bottom navbar slides back up into view.
- **Expected Result**: Smooth `AnimatedSlide` transition hides and restores the navbar.

---

#### TC-NAV-003: Scroll-Driven Navbar Auto-Hide and Auto-Reveal
- **Objective**: Verify navbar hides during downward reading and reveals when scrolling up or hitting the bottom edge.
- **Preconditions**: User is on Tab 0 (`Dashboard`) or Tab 3 (`Logs`) with scrollable content.
- **Steps**:
  1. Scroll down moderately fast.
  2. Observe navbar hides as content scrolls.
  3. Scroll up slightly.
  4. Observe navbar immediately slides into view.
  5. Scroll all the way down to the bottom of the page.
- **Expected Result**: Reaching the bottom edge auto-reveals the navbar so the user is never stranded without navigation controls.

---

#### TC-NAV-004: Hardware / System Back Button Stack Traversal
- **Objective**: Verify back button navigates through the user's tab history in reverse order.
- **Preconditions**: User is on `DashboardPage`.
- **Steps**:
  1. Start on Tab 0 (`Dashboard`).
  2. Tap Tab 1 (`Gawain`).
  3. Tap Tab 2 (`Ani`).
  4. Press the Android system / hardware Back button.
  5. Observe navigation returns to Tab 1 (`Gawain`).
  6. Press the Back button again.
  7. Observe navigation returns to Tab 0 (`Dashboard`).
- **Expected Result**: Each back press traverses `_navHistory` in Last-In-First-Out (LIFO) order.

---

### Category D: Gawain (Tasks) Page Navigation

#### TC-TASK-001: Task Completion State Transition
- **Objective**: Verify marking a task as done updates Firestore and UI in real-time.
- **Preconditions**: At least one pending task exists in the user's task list.
- **Steps**:
  1. Navigate to Tab 1 (`Gawain`).
  2. Find an active task card with priority tag.
  3. Tap the **"Tapusin ang Gawain"** (Mark as Done) button.
- **Expected Result**:
  - Loading spinner appears briefly on the task card button.
  - Firestore document updates `status: 'done'`.
  - Task disappears from the pending list.
  - Floating SnackBar confirms: *"Matagumpay mong natapos ang gawain."*

---

### Category E: Ani (Yield Estimation) Page Navigation

#### TC-YIELD-001: Yield Estimation Refresh / Recalculate Navigation
- **Objective**: Verify manual pull-to-refresh and recalculate triggers.
- **Preconditions**: User is on Tab 2 (`Ani`).
- **Steps**:
  1. Locate the refresh button on the top right header of the Ani tab, or perform a pull-down gesture on the scroll view.
  2. Observe the loading indicator.
- **Expected Result**:
  - Growth indicators subscription re-synchronizes.
  - Floating SnackBar appears: *"Data is automatically updated in real time."*

---

#### TC-YIELD-002: 90-Day Machine Learning Gate Status Validation
- **Objective**: Verify visual indicators for harvest eligibility countdown vs processed prediction.
- **Preconditions**: User is on Tab 2 (`Ani`).
- **Steps**:
  1. Observe the **"Growth Cycle"** card.
  2. If the current cycle is `< 90 days`, verify:
     - Prediction badge displays: `Pending`.
     - Subtext displays: *"Prediction available in X weeks"*.
  3. If the current cycle is `>= 90 days`, verify:
     - Projected yield is displayed in kg with RF Prediction mode tag.
- **Expected Result**: Accurate conditional rendering based on real-time cultivation cycle data.

---

### Category F: Logs & Data History Navigation

#### TC-LOGS-001: Ulang Sampling Record Submission Navigation
- **Objective**: Verify submitting an Ulang growth record updates lists and charts.
- **Preconditions**: User is on Tab 3 (`Logs`).
- **Steps**:
  1. In the Ulang tab section, enter valid Size (cm) and Weight (g).
  2. Tap **"I-save ang Sukat"**.
- **Expected Result**:
  - Button displays loading indicator during Firestore write.
  - Input fields clear.
  - Success message confirms save.
  - Weekly growth curve and recent records update immediately.

#### TC-LOGS-002: Plant Growth Record Form Navigation
- **Objective**: Verify plant growth logging with dropdown validation.
- **Preconditions**: User is on Tab 3 (`Logs`).
- **Steps**:
  1. In the Plant section, select Plant Name (Mint or Oregano).
  2. Select Stage (Seedling, Vegetative, Pre-Flowering, or Harvest).
  3. Input Height in cm.
  4. Select Condition (Malusog, Dilaw, Nalalanta, or May Peste).
  5. Tap **"I-save ang Sukat ng Halaman"**.
- **Expected Result**: Form validates, saves to Firestore `logs` collection, and resets fields.

#### TC-LOGS-003: "Tingnan ang Iba Pa" (See More) List Expansion
- **Objective**: Verify collapsible history lists for Mortality, Ulang, and Plant logs.
- **Preconditions**: More than 3 log entries exist.
- **Steps**:
  1. Scroll down to Recent Logs.
  2. Observe only the first 3 items are rendered initially.
  3. Tap **"Tingnan ang Iba Pa"** (See More).
  4. Observe all logged records expand into view.
  5. Tap **"Ipakita ang Mas Kaunti"** (Show Less).
- **Expected Result**: List expands and collapses smoothly without jumping or layout breakage.

---

### Category G: Profile Page & Logout Navigation

#### TC-PROF-001: Profile Page Navigation Drawer (Sidebar) Links
- **Objective**: Verify the hamburger/sidebar drawer in `ProfilePage` redirects to any core tab.
- **Preconditions**: User is on `ProfilePage`.
- **Steps**:
  1. Open the left sidebar drawer.
  2. Tap **"Tasks"** -> Verify drawer closes and user navigates to Tasks.
  3. Return to Profile and open drawer.
  4. Tap **"Yield"** -> Verify user navigates to Yield.
  5. Return to Profile and open drawer.
  6. Tap **"Logs"** -> Verify user navigates to Logs.
  7. Return to Profile and open drawer.
  8. Tap **"Home"** -> Verify user navigates to Dashboard.
- **Expected Result**: All drawer navigation links route to the designated screens cleanly.

---

#### TC-PROF-002: Profile Information Inline Edit
- **Objective**: Verify editing Full Name and Address on the profile screen.
- **Preconditions**: User is on `ProfilePage`.
- **Steps**:
  1. Tap **"Edit"** next to Full Name.
  2. Modify name in the text field.
  3. Tap **"Edit"** next to Address and modify address.
  4. Tap **"Update Account Information"**.
- **Expected Result**:
  - Loading spinner displays on update button.
  - Firestore updates `users` document.
  - Fields revert to view mode displaying updated text.
  - Top bar avatar initials update across the app.

---

#### TC-PROF-003: Logout Confirmation Dialog Navigation
- **Objective**: Verify logout confirmation modal prevents accidental sign-outs and handles confirmed logouts.
- **Preconditions**: User is on `ProfilePage`.
- **Steps**:
  1. Scroll down and tap **"Log Out"**.
  2. Verify dialog appears: *"Gusto mo bang mag-log out?"* with "Hindi" and "Oo" options.
  3. Tap **"Hindi"** (No / Cancel).
  4. Verify dialog dismisses and user remains on `ProfilePage`.
  5. Tap **"Log Out"** again.
  6. Tap **"Oo"** (Yes / Confirm).
- **Expected Result**:
  - `FirebaseAuth.instance.signOut()` executes.
  - App redirects to `/login` via `Navigator.pushNamedAndRemoveUntil`.
  - All back navigation history is cleared; pressing Back exits the app rather than reopening the dashboard.

---

### Category H: Push Notifications & Deep Linking Navigation

#### TC-NOTIF-001: App Redirection on Notification Click
- **Objective**: Verify tapping a system tray notification opens the app and routes directly to the Tasks tab.
- **Preconditions**: An alert or task push notification was triggered on the device.
- **Steps**:
  1. Background or close the Bantay Ulang application.
  2. Pull down the Android system notification drawer.
  3. Tap the **"Bantay Ulang Alert"** or **"Nakatalagang Gawain"** notification.
- **Expected Result**:
  - The application opens/resumes.
  - `NotificationService.navigateToTasks()` activates.
  - The user lands directly on Tab 1 (`Gawain`).

---

## 6. UAT Test Execution Sign-Off Matrix

| Test Suite / Category | Total Test Cases | Passed | Failed | Blocked | Tester Signature | Date |
|---|---|---|---|---|---|---|
| **A. Authentication & Onboarding** | 6 | | | | | |
| **B. Dashboard & KPI Hierarchy** | 8 | | | | | |
| **C. Tab Navigation & Gestures** | 4 | | | | | |
| **D. Gawain (Tasks) Page** | 1 | | | | | |
| **E. Ani (Yield Estimation) Page** | 2 | | | | | |
| **F. Logs & Growth Tracking** | 3 | | | | | |
| **G. Profile & Logout** | 3 | | | | | |
| **H. Notifications & Deep Linking** | 1 | | | | | |
| **TOTAL** | **28** | | | | | |

### Overall UAT Verdict:
- [ ] **ACCEPTED / READY FOR PRODUCTION**
- [ ] **CONDITIONAL ACCEPTANCE (Minor defects noted)**
- [ ] **REJECTED (Critical defects blocking sign-off)**

**Project Stakeholder / Lead Approver:** _________________________  
**Date:** _________________________
