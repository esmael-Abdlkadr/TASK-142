# ChargeProcure Field Operations

A native iOS Objective-C application for offline EV charging site operations — covering procurement workflows, charger command management, bulletin publishing, analytics, finance controls (deposits, coupons, invoices), and role-based access across Administrator, Site Technician, and Finance Approver roles. Designed to run fully offline with local Core Data persistence and background sync.

## Architecture & Tech Stack

* **Language:** Objective-C
* **UI Framework:** UIKit (iPhone + iPad, UISplitViewController for iPad)
* **Persistence:** Core Data — 28 entities, offline-first local store
* **Authentication:** `CPAuthService` + `LocalAuthentication` (Face ID / Touch ID), RBAC via `CPRBACService`
* **Background Tasks:** `BackgroundTasks` framework (`BGAppRefreshTask`, `BGProcessingTask`)
* **Platform:** iOS 15.0+, `TARGETED_DEVICE_FAMILY = 1,2`
* **Containerization:** Not applicable — native iOS/Xcode project; must be built and tested on macOS with Xcode 15+

## Project Structure

```text
.
├── ChargeProcure/
│   ├── ChargeProcure/
│   │   ├── Core/
│   │   │   ├── Services/            # 11 domain services (Auth, Procurement, Charger,
│   │   │   │                        #   Bulletin, Analytics, Export, Pricing, RBAC,
│   │   │   │                        #   Attachment, Deposit, Coupon)
│   │   │   ├── CoreData/
│   │   │   │   ├── Entities/        # 28 Core Data entities × 4 files each
│   │   │   │   └── Model.xcdatamodeld/
│   │   │   ├── Background/          # CPBackgroundTaskManager
│   │   │   └── Utilities/           # CPDateFormatter, CPNumberFormatter, CPIDGenerator,
│   │   │                            #   CPFileValidator, CPImageCache
│   │   ├── Modules/                 # 20 view controllers across 6 domains:
│   │   │   ├── Auth/                #   Login
│   │   │   ├── Dashboard/
│   │   │   ├── Charger/             #   List + Detail
│   │   │   ├── Procurement/         #   List, Case, Invoice, WriteOff, VendorStatement
│   │   │   ├── Bulletin/            #   List, Editor, Detail
│   │   │   ├── Pricing/             #   List + Detail
│   │   │   ├── Analytics/
│   │   │   ├── Finance/             #   Deposits, Coupons
│   │   │   ├── Admin/               #   Settings, AuditLog, UserMgmt, RolesPermissions
│   │   │   ├── Reports/
│   │   │   └── Vendor/              #   List + Detail
│   │   ├── Navigation/              # CPTabBarController, CPSplitViewController,
│   │   │                            #   CPSidebarViewController (role-filtered)
│   │   └── Resources/               # Assets, Info.plist, LaunchScreen
│   ├── ChargeProcureTests/          # 15 XCTest classes + CPTestCoreDataStack
│   └── ChargeProcure.xcodeproj/
├── start.sh                         # Build & launch in iOS Simulator
├── run_tests.sh                     # Test runner — full suite and --fast mode
└── README.md
```

## Prerequisites

This project is a native iOS/Xcode application. No Docker or backend server is required — the app runs entirely on-device or in the iOS Simulator with a local Core Data store.

* **macOS** (any version supported by Xcode 15+)
* **Xcode 15 or later** — [Download from Mac App Store](https://apps.apple.com/app/xcode/id497799835)
* **iOS Simulator** — bundled with Xcode; no separate installation needed

> **Docker note:** A root `Dockerfile` is present but intentionally informational only. If the container is run, it prints that ChargeProcure is a native iOS/Xcode project and must be built and tested on macOS.

## Running the Application

1. **Open in Xcode (recommended):**
   ```bash
   open ChargeProcure/ChargeProcure.xcodeproj
   ```
   Select an iOS 15.0+ simulator in the toolbar, then press **Run (⌘R)**.

2. **Build and launch via script:**
   ```bash
   ./start.sh                   # launches in iPhone 17 simulator (default)
   ./start.sh "iPhone 15 Pro"   # use a specific simulator name
   ```
   `start.sh` boots the simulator, builds with `xcodebuild`, installs the `.app`, and launches it.

3. **Access the app:**
   The iOS Simulator window opens automatically. Use the seeded credentials below to log in.

4. **Stop the simulator:**
   ```bash
   xcrun simctl shutdown <SIMULATOR_UDID>
   ```

## Testing

All unit and integration tests are run through `run_tests.sh`. The script handles simulator resolution, booting, and result bundle generation automatically.

Make the script executable (first time only), then run:

```bash
chmod +x run_tests.sh
./run_tests.sh
```

A fast subset (excludes the slow full-pipeline `CPProcurementServiceTests`) is available for routine local use:

```bash
./run_tests.sh --fast
```

| Workflow | Command | Targets / classes | When to use |
| :--- | :--- | :--- | :--- |
| Fast local | `./run_tests.sh --fast` | ChargeProcureTests — 16 of 17 | Every commit / pre-push |
| Full CI | `./run_tests.sh` | ChargeProcureTests — all 17 | CI, pre-merge, release |
| With coverage gate | `./run_tests.sh --threshold 70` | All 17 unit tests | CI, fail if coverage drops below 70 % |
| End-to-end UI | `./run_tests.sh --uitests` | ChargeProcureUITests — 2 classes, 10 flows | Pre-release, full regression |

The script outputs a standard exit code (`0` for success, non-zero for failure) and generates a code coverage report in the `.xcresult` bundle at `.build/test-results`. Open it in Xcode for per-file line/branch coverage:

```bash
open .build/test-results
```

To enforce a minimum coverage threshold (fails CI if coverage falls below the target):

```bash
./run_tests.sh --threshold 70          # fail if line coverage < 70 %
./run_tests.sh --fast --threshold 70   # fast subset + coverage gate
```

The `--uitests` flag runs the `ChargeProcureUITests` XCUITest target — full tap/navigation automation against the live app binary. The app is launched with `UI_TESTING=1` which uses an in-memory Core Data store and deterministic seed credentials.

*macOS + Xcode are required. On non-macOS environments the script prints a clear message and exits `0` without attempting to use unavailable Apple tooling.*

## Seeded Credentials

Three default accounts are seeded on first launch. **Each account requires a mandatory password change on first login** — the app prompts for a new password before granting access.

| Role | Username | Password | Notes |
| :--- | :--- | :--- | :--- |
| **Administrator** | `admin` | *(generated at first launch — see below)* | Full access to all modules including audit log, pricing, user management, and reports. |
| **Site Technician** | `technician` | *(generated at first launch — see below)* | Access to Dashboard, Chargers, Procurement, and Bulletins. |
| **Finance Approver** | `finance` | *(generated at first launch — see below)* | Access to Dashboard, Procurement (invoices/write-offs), Analytics, and Deposits/Coupons. |

**How to retrieve the passwords:** Default passwords are generated at first launch using `SecRandomCopyBytes` — they are never hardcoded in source or written to any log. After seeding, `AppDelegate` displays a one-time in-app alert with all three credentials. Copy them immediately; the values are discarded after the alert is dismissed.

Role-based module access:

| Module | Administrator | Site Technician | Finance Approver |
| :--- | :---: | :---: | :---: |
| Dashboard | ✓ | ✓ | ✓ |
| Chargers | ✓ | ✓ | |
| Procurement | ✓ | ✓ | ✓ |
| Bulletins | ✓ | ✓ | |
| Analytics | ✓ | | ✓ |
| Finance (Deposits/Coupons) | ✓ | | ✓ |
| Reports | ✓ | | |
| Admin (Audit, Users, Pricing) | ✓ | | |
| Settings | ✓ | ✓ | ✓ |
