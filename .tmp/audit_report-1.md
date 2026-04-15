# Delivery Acceptance / Project Architecture Inspection (Frontend, Static Audit)

## Scope and Method

- Review target: `w2t142/repo` (iOS Objective-C UIKit app in `ChargeProcure`).
- Prompt standard used as sole acceptance baseline.
- **Static-only audit** per user request (no runtime/build/test execution in this pass).
- Evidence format: `path:line`.
- Repro commands are provided for local verification where runtime confirmation is needed.

---

## 1) Mandatory Gate Checks

### 1.1 Can the delivered project actually be run and verified?

- **Conclusion: Partial Pass**
- **Reasoning:** Startup and test instructions exist and are specific, but this pass is static-only, so runnable behavior is not runtime-confirmed.
- **Evidence:**
  - Run/build instructions in `README.md:106`, `README.md:110`, `README.md:114`, `README.md:127`.
  - Startup script exists and builds/installs/launches simulator app: `start.sh:83`, `start.sh:102`, `start.sh:105`.
  - Test script entry point exists: `run_tests.sh:30`.
  - Project target configuration present for iOS/iPhone+iPad: `ChargeProcure/ChargeProcure.xcodeproj/project.pbxproj:924`, `ChargeProcure/ChargeProcure.xcodeproj/project.pbxproj:1010`.
- **Repro steps:**
  1. `cd /Users/apple/Documents/projects/eagle-point_new/w2t142/repo`
  2. `./start.sh "iPhone 17"`  
     Expected: simulator boots, app installs and launches (`start.sh:69`, `start.sh:102`, `start.sh:105`).
  3. `./run_tests.sh "iPhone 17" "latest"`  
     Expected: XCTest output and result bundle under `.build/test-results`.

### 1.2 Does the deliverable materially deviate from the Prompt?

- **Conclusion: Partial Pass**
- **Reasoning:** Major flows are implemented (auth, bulletin workflow, procurement chain, pricing, charger commands, analytics/export, local persistence). However, key prompt constraints/features are missing or weakened (notably permission gating exposure, incomplete deposit/pre-auth and coupon-package business usage, and non-rich WYSIWYG behavior).
- **Evidence (aligned portions):**
  - Auth/lockout/biometric foundation: `CPAuthService.m:23`, `CPAuthService.m:24`, `CPAuthService.m:629`, `CPAuthService.m:639`, `CPAuthService.m:276`.
  - Bulletin autosave/summary/scheduling/versioning: `CPBulletinEditorViewController.m:539`, `CPBulletinEditorViewController.m:83`, `CPBulletinEditorViewController.m:688`, `CPBulletinService.m:260`, `CPBulletinService.m:291`.
  - Procurement flow and thresholds: `CPProcurementService.m:87`, `CPProcurementService.m:243`, `CPProcurementService.m:485`, `CPProcurementService.m:635`, `CPProcurementService.m:822`, `CPProcurementService.m:69`, `CPProcurementService.m:70`, `CPProcurementService.m:71`.
  - Charger command timeout and Pending Review: `CPChargerService.m:16`, `CPChargerService.m:266`, `CPChargerService.m:409`.
  - Background/offline orientation: `AppDelegate.m:123`, `Info.plist:42`, `CPBackgroundTaskManager.m:106`, `CPBackgroundTaskManager.m:137`.
- **Evidence (deviations/gaps):**
  - iPad sidebar exposes all modules regardless of role: `CPSidebarViewController.m:121`, `CPSidebarViewController.m:147`, `CPSidebarViewController.m:152`.
  - Reports screen lacks RBAC guard in UI layer: `CPReportsViewController.m:113`, `CPReportsViewController.m:175`.
  - Export service has no permission check before generating files: `CPExportService.m:29`, `CPExportService.m:94`.
  - “WYSIWYG” mode is mostly UI toggling and markdown wrappers, not rich-text data model: `CPBulletinEditorViewController.m:150`, `CPBulletinEditorViewController.m:612`, `CPBulletinEditorViewController.m:781`.
  - Deposit/coupon entities exist, but no corresponding end-user flow evidence in modules/services:
    - Entities present: `Model.xcdatamodel/.../contents:268`, `Model.xcdatamodel/.../contents:338`.
- **Repro steps:**
  1. Inspect iPad sidebar module list in `CPSidebarViewController.m`.
  2. Inspect Reports view and export service for permission checks.
  3. Compare prompt-required deposit/coupon operational flow vs existing module/service references.

---

## 2) Completeness of Delivery

### 2.1 Core requirements coverage (pages/features/interactions/states)

- **Conclusion: Partial Pass**
- **Reasoning:** Core business flows are broadly present; several prompt-critical details are absent/partially implemented.
- **Evidence:**
  - Role-aware iPhone tabs: `CPTabBarController.m:84`, `CPTabBarController.m:100`, `CPTabBarController.m:111`, `CPTabBarController.m:133`.
  - iPad split view: `CPSplitViewController.m:39`, `AppDelegate.m:172`.
  - Procurement screens and write-off/invoice/vendor statement flows: `CPProcurementListViewController.m:224`, `CPInvoiceViewController.m` (module presence), `CPWriteOffViewController.m` (module presence), `CPVendorStatementViewController.m:353`.
  - Statement export vendor/month: `CPProcurementService.m:1350`.
  - Attachment limits/type validation/cleanup: `CPAttachmentService.m:7`, `CPAttachmentService.m:136`, `CPAttachmentService.m:375`.
  - Analytics streak/trend/heatmap/anomaly: `CPAnalyticsService.m:97`, `CPAnalyticsService.m:122`, `CPAnalyticsService.m:391`, `CPAnalyticsService.m:507`, `CPAnalyticsService.m:557`.
- **Gaps:**
  - Deposit/pre-authorization business workflow not evidenced beyond entity definitions: `Model.xcdatamodel/.../contents:268`, `Model.xcdatamodel/.../contents:353`.
  - CouponPackage business usage not evidenced beyond entity definition: `Model.xcdatamodel/.../contents:338`.
  - “Rich WYSIWYG” semantics are limited (largely markdown tooling): `CPBulletinEditorViewController.m:781`.
- **Repro steps:**
  1. Trace each prompt flow to matching module/service entry.
  2. For deposit/coupon flows, search modules/services for operational usage and verify absent coverage.

### 2.2 Real project shape vs demo/snippet

- **Conclusion: Pass**
- **Reasoning:** This is a multi-module, persisted app with structured services, view controllers, Core Data schema, scripts, and tests.
- **Evidence:**
  - Project structure + docs/scripts: `README.md:1`, `start.sh:1`, `run_tests.sh:1`.
  - App entry + background manager + Core Data stack: `AppDelegate.m:46`, `AppDelegate.m:70`, `AppDelegate.m:114`.
  - Large module/service split visible in file tree and source.
- **Mock/stub handling judgment:**
  - Charger simulation adapter exists for tests/dev (`CPChargerSimulatorAdapter` references in service/tests), but production path still supports vendor ACK wait with timeout: `CPChargerService.m:269`, `CPChargerService.m:287`.
  - **Risk:** unclear if production SDK adapter wiring is fully integrated (cannot confirm statically).
- **Repro steps:**
  1. Open `ChargeProcure.xcodeproj`.
  2. Confirm module navigation and persisted data operations under Core Data during app use.

---

## 3) Engineering and Architecture Quality

### 3.1 Structure and module split

- **Conclusion: Pass**
- **Reasoning:** Responsibilities are generally separated by domain (`Modules/*`, `Core/Services/*`, `Core/CoreData/*`, navigation controllers, background manager).
- **Evidence:**
  - Navigation/auth root split: `AppDelegate.m:147`, `CPTabBarController.m:84`, `CPSplitViewController.m:48`.
  - Domain services for auth/procurement/bulletin/pricing/analytics/attachments/export.
  - Core Data entities are extensive and explicit: `Model.xcdatamodel/.../contents:3` onward.
- **Caveat:** some service files are very large (e.g., procurement service), increasing maintenance risk.
- **Repro steps:**
  1. Review `ChargeProcure/ChargeProcure/Modules` and `ChargeProcure/ChargeProcure/Core/Services`.

### 3.2 Maintainability and extensibility

- **Conclusion: Partial Pass**
- **Reasoning:** Domain separation exists, but security and state-transition concerns reduce maintainability confidence.
- **Evidence:**
  - Permission checks embedded across many services/controllers (good baseline): `CPAuthService.m:896`, `CPProcurementService.m:1104`, `CPChargerService.m:184`.
  - Missing centralized screen-level route/access enforcement on iPad sidebar path: `CPSidebarViewController.m:121`.
  - Logout transition logic is brittle and not centralized to root replacement: `CPSettingsViewController.m:524`, `CPSettingsViewController.m:527`, `CPTabBarController.m:237`.
- **Repro steps:**
  1. Compare iPhone role-aware tab construction vs iPad sidebar module exposure.
  2. Follow logout call chain and verify whether login screen is guaranteed.

---

## 4) Engineering Detail and Professionalism

### 4.1 Error handling / validation / UI states / logging / sensitive exposure

- **Conclusion: Partial Pass**
- **Reasoning:** Validation and UI states are implemented in many modules; however, security-sensitive logging and access controls have serious issues.
- **Evidence (good):**
  - Password and lockout validation: `CPAuthService.m:629`, `CPAuthService.m:158`.
  - Summary length and weight validation: `CPBulletinService.m:135`, `CPBulletinService.m:206`.
  - Write-off validation and cap enforcement: `CPProcurementService.m:1101`, `CPProcurementService.m:1150`.
  - Loading/empty states and feedback examples: `CPProcurementListViewController.m:324`, `CPAuditLogViewController.m:233`, `CPLoginViewController.m:575`.
  - Audit logging structure includes actor/resource/time/device: `CPAuditService.m:61`, `CPAuditService.m:67`, `CPAuditService.m:69`.
- **Evidence (risks):**
  - **Credential leakage in logs:** bootstrap passwords printed to console: `CPAuthService.m:714`.
  - Mixed log discipline includes direct `NSLog` operational/debug statements in multiple modules.
  - Reports/export lacks explicit RBAC checks in UI/service layers: `CPReportsViewController.m:175`, `CPExportService.m:94`.
- **Repro steps:**
  1. Run first launch and inspect console logs for bootstrap credential output.
  2. Review report generation call path for explicit permission checks.

### 4.2 Product-like experience vs demo artifact

- **Conclusion: Partial Pass**
- **Reasoning:** App has connected screens and workflows, but some access-control and prompt-fit gaps keep it below production-grade acceptance.
- **Evidence:**
  - Multi-page flow and navigation cohesion: `CPTabBarController.m:152`, `CPProcurementListViewController.m:493`, `CPBulletinDetailViewController.m` (share/archive/restore controls).
  - Background and export/report infrastructure present: `CPBackgroundTaskManager.m:41`, `CPExportService.m:29`.
- **Repro steps:**
  1. Walk login -> dashboard -> procurement -> invoice/write-off -> reports export.
  2. Validate role restrictions and post-logout behavior.

---

## 5) Prompt Understanding and Fit

### 5.1 Business goal and constraints fidelity

- **Conclusion: Partial Pass**
- **Reasoning:** Strong implementation breadth for offline UIKit/Core Data workflow, but several constraints are incomplete or inconsistently enforced.
- **Evidence (fit):**
  - Fully local persistence (Core Data + sandbox files): `CPCoreDataStack` usage across services, `CPAttachmentService.m:33`.
  - No server/backend networking found in app code (no `NSURLSession`/HTTP paths detected by static search).
  - BG tasks and low-power defer behavior: `CPBackgroundTaskManager.m:137`, `CPBackgroundTaskManager.m:205`, `CPBackgroundTaskManager.m:244`.
- **Evidence (misfit / ambiguity):**
  - iPad module exposure does not match strict multi-role access intent: `CPSidebarViewController.m:121`.
  - Coupon/deposit flows not materially surfaced in user/business operations beyond schema entities: `Model.xcdatamodel/.../contents:268`, `Model.xcdatamodel/.../contents:338`.
  - Tests still rely on legacy static seed passwords conflicting with documented/implemented random bootstrap logic:
    - random bootstrap: `CPAuthService.m:707`, `CPAuthService.m:714`.
    - test static credentials usage: `CPProcurementServiceTests.m:21`, `CPRBACServiceTests.m:39`, `CPChargerServiceTests.m:22`.
- **Repro steps:**
  1. Review role-gated navigation paths on iPhone vs iPad.
  2. Trace deposit/coupon requirements to executable module/service flows.
  3. Run tests to verify credential mismatch behavior.

---

## 6) Visual and Interaction Quality (Frontend)

### 6.1 Visual polish and interaction feedback

- **Conclusion: Pass (with caveats)**
- **Reasoning:** UIKit layouts, Safe Area, Dynamic Type, dark-mode adaptation, and feedback patterns are consistently applied; however, some higher-order UX requirements (true rich editor semantics) are only partially met.
- **Evidence:**
  - Safe area usage in key screens: `CPLoginViewController.m:239`, `CPDashboardViewController.m:368`, `CPProcurementListViewController.m:317`.
  - Dynamic Type scaling: `CPLoginViewController.m:113`, `CPDashboardViewController.m:93`.
  - Dark mode trait handling: `CPLoginViewController.m:601`, `CPTabBarController.m:225`.
  - Haptic feedback on critical actions: `CPChargerDetailViewController.m:514`, `CPWriteOffViewController.m:517`.
  - Split-view adaptation for iPad: `CPSplitViewController.m:39`, `CPSplitViewController.m:121`.
- **Repro steps:**
  1. Toggle light/dark mode and Dynamic Type sizes in simulator settings.
  2. Trigger critical actions and observe haptic/disabled/loading states.

---

## Security and Access-Control Priority Findings

### Blocker

1. **Logout flow may not reliably return to login screen (session ended but UI potentially remains accessible).**
   - **Evidence:** `CPSettingsViewController.m:524`, `CPSettingsViewController.m:527`, `CPSettingsViewController.m:531`, `CPTabBarController.m:237`.
   - **Impact:** Users may continue browsing previously loaded content after logout; high risk of unauthorized visibility.
   - **Smallest executable fix:** On logout, delegate directly to `AppDelegate configureRootViewControllerForAuthState` (or a centralized router) instead of `pop/dismiss` heuristics.

2. **Sensitive bootstrap credentials are logged in plaintext to console.**
   - **Evidence:** `CPAuthService.m:714`.
   - **Impact:** Anyone with device logs can obtain first-run credentials; severe credential exposure.
   - **Smallest executable fix:** Remove plaintext credential logging; replace with one-time secure handoff UX (or ephemeral secure display without logs).

### High

1. **Reports/export functionality lacks explicit permission checks in UI/service path.**
   - **Evidence:** `CPReportsViewController.m:175`, `CPExportService.m:29`, `CPExportService.m:94`.
   - **Impact:** Users without report-export privileges may still trigger offline data exports.
   - **Smallest executable fix:** Enforce `report.export`/resource-action checks before showing generation controls and inside `CPExportService`.

2. **iPad sidebar is not role-aware; modules are universally listed.**
   - **Evidence:** `CPSidebarViewController.m:121`, `CPSidebarViewController.m:147`, `CPSidebarViewController.m:152`.
   - **Impact:** Hidden-by-UI security model can be bypassed by direct navigation path on iPad.
   - **Smallest executable fix:** Build sidebar items from current role permissions, mirroring `CPTabBarController` role gating logic.

3. **Test suite credential assumptions conflict with current auth implementation and README.**
   - **Evidence:** `CPAuthService.m:707`, `CPAuthService.m:714`, `README.md:141`, `CPProcurementServiceTests.m:21`, `CPRBACServiceTests.m:39`.
   - **Impact:** Automated verification reliability is compromised; false confidence risk.
   - **Smallest executable fix:** Replace static seeded-password login in tests with deterministic test-user creation or bootstrap-password interception strategy.

### Medium

1. **Prompt-required deposit/pre-auth and coupon-package operational flows are not materially implemented beyond schema entities.**
   - **Evidence:** `Model.xcdatamodel/.../contents:268`, `Model.xcdatamodel/.../contents:338`.
   - **Impact:** Business-scenario completeness gap.
   - **Smallest executable fix:** Add service + UI workflows for deposit/pre-auth status tracking and coupon-package operations.

2. **“WYSIWYG” editor mode appears shallow (format toggles/markers) rather than robust rich-text editing model.**
   - **Evidence:** `CPBulletinEditorViewController.m:150`, `CPBulletinEditorViewController.m:612`, `CPBulletinEditorViewController.m:781`.
   - **Impact:** UX/functionality may not match requirement intent.
   - **Smallest executable fix:** Introduce attributed-text/rich-text model with persisted HTML/attributed payload and conversion boundaries.

### Low

1. **Pagination requirement is unevenly implemented across long-history lists.**
   - **Evidence:** Pagination in audit log: `CPAuditLogViewController.m:233`; procurement list currently FRC-based full fetch: `CPProcurementListViewController.m:367`.
   - **Impact:** Potential scalability/UX degradation for large datasets.
   - **Smallest executable fix:** Add cursor/page windowing to high-volume list modules.

---

## Tests and Logging Review (Explicit)

### Unit tests

- **Conclusion: Pass (existence), Partial Pass (trustworthiness)**
- **Evidence:** Unit-style suites exist for auth/procurement/bulletin/charger/rbac/analytics/pricing/attachment in `ChargeProcureTests/*.m`.

### Component tests

- **Conclusion: Not Applicable**
- **Reasoning boundary:** UIKit Objective-C project relies primarily on service tests plus limited navigation contract tests; no React/Vue-style component-test layer is expected.

### Page/route integration tests

- **Conclusion: Partial Pass**
- **Evidence:** `CPNavigationAndContractTests.m` validates sidebar class wiring and service contracts (`CPNavigationAndContractTests.m:26`, `CPNavigationAndContractTests.m:130`).
- **Gap:** No end-to-end UI navigation/login/logout permission journey tests.

### E2E tests

- **Conclusion: Not Applicable (missing)**
- **Reasoning boundary:** No UI automation suite (XCUITest) present in repository.

### Logging categorization and sensitive-data risk

- **Conclusion: Partial Pass**
- **Evidence:** Structured audit categories exist (`CPAuditService.m:27`, `CPAuditService.m:169`), but plaintext credential logging is present (`CPAuthService.m:714`).

---

## Test Coverage Evaluation (Static Audit)

### 1) Test Overview

- **Test artifacts present:** unit/service + contract tests in `ChargeProcure/ChargeProcureTests/*.m`.
- **Framework:** XCTest (`CPAuthServiceTests.m:1`, `CPProcurementServiceTests.m:1`, etc.).
- **Entry points documented:** `README.md:127`, `run_tests.sh:30`.
- **Execution state in this audit:** not executed (static-only by request).

### 2) Coverage Mapping Table (Requirement/Risk -> Tests)

| Requirement / Risk Item | Corresponding Test Case (file:line) | Key Assertion / Fixture / Mock (file:line) | Coverage Judgment | Gap | Smallest Test Addition Recommendation |
|---|---|---|---|---|---|
| Password policy (>=10 chars + digit) | `CPAuthServiceTests.m:76`, `CPAuthServiceTests.m:87`, `CPAuthServiceTests.m:100` | `XCTAssertTrue/False` on `validatePassword` | Fully covered | None | Keep |
| 5-failure lockout + 15-min behavior | `CPAuthServiceTests.m:151`, `CPAuthServiceTests.m:224` | Repeated wrong login attempts + lockout expiry mutation | Fully covered | Remaining clock/race runtime risk | Add deterministic clock abstraction tests |
| Biometric auth availability failure path | `CPAuthServiceTests.m:323` | Simulator biometric unavailable assertions | Basically covered | No success-path biometric test | Add success-path mock LAContext test |
| Forced password rotation flow | `CPAuthServiceTests.m:490` | `needsPasswordChange` + flag-clearing assertions | Fully covered | None | Keep |
| Procurement happy path E2E chain | `CPProcurementServiceTests.m:905` | REQ->RFQ->PO->Receipt->Invoice->Reconcile->Payment->Closed assertions | Fully covered | UI integration absent | Add UI-level flow smoke test |
| Variance thresholds ($25 or 2%) | `CPProcurementServiceTests.m:164`, `CPProcurementServiceTests.m:1188` | Amount and OR-threshold assertions | Fully covered | None | Keep |
| Write-off cap <= $250 | `CPProcurementServiceTests.m:296`, `CPProcurementServiceTests.m:777` | Cumulative cap enforcement assertions | Fully covered | No UI form validation tests | Add write-off view validation test |
| Partial receipt/invoice handling | `CPProcurementServiceTests.m:383` | `receivedQty` update assertion | Basically covered | Partial invoicing UI path not covered | Add invoice partial-line integration test |
| Bulletin summary limit 280 | `CPBulletinServiceTests.m:161`, `CPBulletinServiceTests.m:187` | >280 reject, ==280 accept | Fully covered | None | Keep |
| Bulletin publish/version/restore | `CPBulletinServiceTests.m:124`, `CPBulletinServiceTests.m:233`, `CPBulletinServiceTests.m:389` | Version snapshot and restore assertions | Fully covered | Editor-mode parity not covered | Add WYSIWYG-mode state persistence tests |
| Weekly cleanup (90-day draft + pinned exclusion) | `CPBulletinServiceTests.m:442`, `CPBulletinServiceTests.m:484` | stale delete vs pinned preserve assertions | Fully covered | None | Keep |
| Attachment magic headers + 25MB limit | `CPAttachmentServiceTests.m:63`, `CPAttachmentServiceTests.m:119` | file-type and oversize rejection assertions | Fully covered | No malformed PDF edge cases | Add truncated/corrupt binary tests |
| Charger command ACK timeout (8s) | `CPChargerServiceTests.m:98`, `CPChargerServiceTests.m:173` | deterministic timeout adapter + status checks | Fully covered | No hardware delegate integration test | Add adapter contract test for vendor SDK integration |
| Charger RBAC deny paths | `CPChargerServiceTests.m:358`, `CPChargerServiceTests.m:396` | 403/no-op assertions | Fully covered | UI gating still untested | Add screen-level access tests |
| Pricing rule matching/versioning | `CPPricingServiceTests.m:48`, `CPPricingServiceTests.m:216` | specificity and version assertions | Basically covered | Time-window/deposit linkage absent | Add time-window and deposit interaction tests |
| Navigation contract (class wiring) | `CPNavigationAndContractTests.m:26`, `CPNavigationAndContractTests.m:63` | required class resolution assertions | Basically covered | No permission-route guard assertions | Add role-based nav visibility tests |

### 3) Security Coverage Audit (Mandatory)

- **Authentication (login/token/session): Partial Pass**
  - Covered: password validation/lockout/rotation tests (`CPAuthServiceTests.m:76`, `CPAuthServiceTests.m:151`, `CPAuthServiceTests.m:490`).
  - Gap: logout UI transition correctness not explicitly tested.
  - Repro idea: perform logout from settings and verify root becomes login immediately.

- **Frontend route protection / route guards: Fail**
  - Evidence of missing role-aware iPad navigation guards: `CPSidebarViewController.m:121`.
  - Repro idea: log in as non-admin on iPad layout and inspect accessible modules.

- **Page-level / feature-level access control: Partial Pass**
  - Guarded: user management / roles screens (`CPUserManagementViewController.m:382`, `CPRolesPermissionsViewController.m:94`).
  - Unguarded risk: reports/export path (`CPReportsViewController.m:175`, `CPExportService.m:29`).

- **Sensitive information exposure: Fail**
  - Plaintext bootstrap credentials logged: `CPAuthService.m:714`.
  - Repro idea: first-run launch, inspect console log output.

- **Cache/state isolation after user switching: Cannot Confirm**
  - Session keys clear on logout (`CPAuthService.m:250`), but explicit UI/data cache purge and route-reset assertions are absent.
  - Repro idea: login as User A, load sensitive lists, logout/login User B, check for stale visible data before refresh.

### 4) Overall Test Sufficiency Judgment

- **Conclusion: Partial Pass**
- **Judgment boundary:**
  - **Well covered risks:** service-level business rules for auth/procurement/bulletin/attachments/charger timing/RBAC.
  - **Insufficiently covered risks:** UI-level auth transitions, route/page-level guard enforcement (especially iPad sidebar/reports), and sensitive data exposure regressions.
  - Therefore, even with many passing tests, serious security and access defects can remain.

### 5) Mock/Stub Usage Judgment

- **Conclusion: Acceptable with risk controls needed**
- **Evidence:** Charger deterministic adapters in tests (`CPChargerServiceTests.m:75`, `CPChargerServiceTests.m:102`).
- **Risk boundary:** Ensure test adapters cannot accidentally become default production path.

---

## Final Acceptance Determination

- **Overall verdict: Partial Pass (Not acceptance-ready yet).**
- **Why:** Core architecture and major business workflows are substantial and mostly aligned, but security/access-control defects and credential-logging exposure are critical blockers for delivery acceptance.
- **Minimum pre-acceptance fixes:**
  1. Enforce guaranteed logout-to-login root transition.
  2. Remove plaintext bootstrap credential logging.
  3. Add explicit RBAC checks to reports/export flow and role-aware iPad sidebar composition.
  4. Align test credentials with current auth bootstrap logic and re-run test suite.
