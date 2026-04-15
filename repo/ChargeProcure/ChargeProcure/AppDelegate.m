//
//  AppDelegate.m
//  ChargeProcure
//
//  Created by ChargeProcure Team.
//  Copyright © 2024 ChargeProcure. All rights reserved.
//

#import "AppDelegate.h"

// Core Data stack
#import "CPCoreDataStack.h"

// Image cache (cleared on memory warning)
#import "CPImageCache.h"

// Navigation / view controllers
#import "CPLoginViewController.h"
#import "CPSplitViewController.h"
#import "CPTabBarController.h"

// Session / auth
#import "CPAuthService.h"

// Background task manager (single source of truth for all BG tasks)
#import "CPBackgroundTaskManager.h"

// MARK: - Private interface

@interface AppDelegate ()

/// Singleton Core Data stack shared across the application.
@property (nonatomic, strong) CPCoreDataStack *coreDataStack;

/// YES when the app is running in Low Power Mode (throttles background work).
@property (nonatomic, assign) BOOL isLowPowerModeActive;

@end

// MARK: - Implementation

@implementation AppDelegate

// MARK: UIApplicationDelegate — application lifecycle

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {

    // 1. Initialise the Core Data stack first; everything else depends on it.
    [self setupCoreDataStack];

    // 2. Observe Low Power Mode changes before building the UI so that
    //    any component that checks isLowPowerModeActive at init time gets
    //    the correct value.
    [self registerForPowerStateNotifications];
    self.isLowPowerModeActive = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    // 3. Build the window and root view controller.
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor systemBackgroundColor];

    [self configureRootViewControllerForAuthState];

    [self.window makeKeyAndVisible];

    // 4. Register background tasks AFTER the window is visible so that any
    //    UI-touching completion handlers have a runloop to execute on.
    //    All registration is delegated to CPBackgroundTaskManager which holds
    //    the canonical identifier constants matching Info.plist.
    [[CPBackgroundTaskManager sharedManager] registerBackgroundTasks];

    // 5. If first-run seeding prepared bootstrap credentials, show them once
    //    in a secure in-app alert so the operator can note them.  This replaces
    //    the former NSLog approach and ensures credentials are never written to
    //    any persistent log.  The alert is presented after makeKeyAndVisible so
    //    the rootViewController is guaranteed to be on screen.
    [self showBootstrapCredentialsIfPending];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Resume background task scheduling when the app returns to foreground.
    if (!self.isLowPowerModeActive) {
        [[CPBackgroundTaskManager sharedManager] scheduleChargerSyncTask];
        [[CPBackgroundTaskManager sharedManager] scheduleProcurementRefreshTask];
    }
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Persist any unsaved changes when the app is about to become inactive.
    [self saveMainContext];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Persist any unsaved changes then delegate all BG task scheduling to
    // CPBackgroundTaskManager — the single source of truth for BG tasks.
    [self saveMainContext];
    [[CPBackgroundTaskManager sharedManager] applicationDidEnterBackground];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Final save before the process exits.
    [self saveMainContext];

    // Remove notification observers to be tidy.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    // Evict all cached images to relieve memory pressure immediately.
    [[CPImageCache sharedCache] clearAllCachedImages];

    NSLog(@"[ChargeProcure] Memory warning received — image cache cleared.");
}

// MARK: - Core Data setup

/// Initialises the CPCoreDataStack and stores a strong reference.
- (void)setupCoreDataStack {
    self.coreDataStack = [CPCoreDataStack sharedStack];

    NSLog(@"[ChargeProcure] Core Data stack initialised.");

    BOOL isUITesting = [[[NSProcessInfo processInfo] environment][@"UI_TESTING"]
                        isEqualToString:@"1"];
    if (isUITesting) {
        // XCUITest mode: seed all three accounts with a deterministic password so
        // tests can log in without handling the password-change alert.
        // The in-memory store (configured in CPCoreDataStack) guarantees a clean
        // slate on every app launch, so re-seeding is always correct here.
        [[CPAuthService sharedService] seedDefaultUsersWithPassword:@"Test1234Pass"];
        // Clear the forced-rotation flag so tests reach the main UI directly.
        [[NSUserDefaults standardUserDefaults]
         removeObjectForKey:@"cp_must_change_password_uuids"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        // Seed the three default accounts (admin / technician / finance) on first
        // launch. The method is a no-op if any User record already exists.
        [[CPAuthService sharedService] seedDefaultUsersIfNeeded];
    }
}

/// Saves the main (view) managed object context, logging any errors.
- (void)saveMainContext {
    NSManagedObjectContext *context = self.coreDataStack.mainContext;
    if (context == nil) { return; }
    if (!context.hasChanges) { return; }

    NSError *error = nil;
    if (![context save:&error]) {
        NSLog(@"[ChargeProcure] Failed to save main context: %@", error.localizedDescription);
    }
}

// MARK: - Navigation setup

/**
 * Examines the current authentication state and installs the appropriate
 * root view controller:
 *   - Not logged in  → CPLoginViewController (modal / full screen)
 *   - Logged in, iPhone → role-aware tab bar controller
 *   - Logged in, iPad   → UISplitViewController (CPMainSplitViewController)
 */
- (void)configureRootViewControllerForAuthState {
    BOOL isLoggedIn = [[CPAuthService sharedService] isSessionValid];

    if (!isLoggedIn) {
        CPLoginViewController *loginVC = [[CPLoginViewController alloc] init];
        UINavigationController *loginNav =
            [[UINavigationController alloc] initWithRootViewController:loginVC];
        loginNav.navigationBar.prefersLargeTitles = NO;
        self.window.rootViewController = loginNav;
        return;
    }

    // Authenticated — pick the appropriate navigation paradigm.
    if ([self isIPad]) {
        [self configureIPadRootViewController];
    } else {
        [self configureIPhoneRootViewController];
    }
}

/// Builds the role-aware iPhone root tab bar.
- (void)configureIPhoneRootViewController {
    self.window.rootViewController = [[CPTabBarController alloc] init];
}

/// Builds a UISplitViewController for iPad using CPSplitViewController.
- (void)configureIPadRootViewController {
    CPSplitViewController *splitVC = [[CPSplitViewController alloc] init];
    self.window.rootViewController = splitVC;
}

/// Returns YES when the current device is an iPad (or Mac Catalyst).
- (BOOL)isIPad {
    return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
}

// MARK: - Bootstrap credential display

/// Shows a one-time in-app alert with the first-run bootstrap credentials if
/// CPAuthService stored them during seeding.  Clears them immediately after
/// presentation so they cannot be recalled.  Nothing is written to any log.
- (void)showBootstrapCredentialsIfPending {
    // Skip one-time credential display during automated UI testing — no human is
    // watching to note them and the alert would block the test interaction flow.
    if ([[[NSProcessInfo processInfo] environment][@"UI_TESTING"] isEqualToString:@"1"]) {
        [[CPAuthService sharedService] clearPendingBootstrapCredentials];
        return;
    }
    NSDictionary<NSString *, NSString *> *creds =
        [CPAuthService sharedService].pendingBootstrapCredentials;
    if (!creds) { return; }

    [[CPAuthService sharedService] clearPendingBootstrapCredentials];

    NSMutableString *body = [NSMutableString string];
    [body appendString:@"Note these credentials before dismissing.\n\n"];
    [creds enumerateKeysAndObjectsUsingBlock:^(NSString *user, NSString *pwd, BOOL *stop) {
        [body appendFormat:@"%@: %@\n", user, pwd];
    }];
    [body appendString:@"\nAll accounts require a password change on first login."];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"First-Run Setup"
                                            message:[body copy]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"I've Noted These"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];

    // Present on the root VC; the window is already visible at this point.
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// MARK: - Low Power Mode

/// Registers for NSProcessInfoPowerStateDidChangeNotification on the main queue.
- (void)registerForPowerStateNotifications {
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(handlePowerStateDidChange:)
     name:NSProcessInfoPowerStateDidChangeNotification
     object:nil];
}

- (void)handlePowerStateDidChange:(NSNotification *)notification {
    BOOL nowLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    self.isLowPowerModeActive = nowLowPower;

    if (nowLowPower) {
        NSLog(@"[ChargeProcure] Low Power Mode enabled — throttling background tasks.");
        // Cancel non-urgent pending task requests. CPBackgroundTaskManager
        // respects Low Power Mode internally when tasks fire.
        [[BGTaskScheduler sharedScheduler]
         cancelTaskRequestWithIdentifier:CPBGTaskChargerSync];
        [[BGTaskScheduler sharedScheduler]
         cancelTaskRequestWithIdentifier:CPBGTaskProcurementRefresh];
        // Keep the cleanup task — it is low-cost and beneficial.
    } else {
        NSLog(@"[ChargeProcure] Low Power Mode disabled — resuming normal background tasks.");
        [[CPBackgroundTaskManager sharedManager] scheduleChargerSyncTask];
        [[CPBackgroundTaskManager sharedManager] scheduleProcurementRefreshTask];
    }

    // Notify interested UI components via a local notification so they can
    // update animations and polling intervals accordingly.
    [[NSNotificationCenter defaultCenter]
     postNotificationName:@"CPPowerStateDidChangeNotification"
     object:@(nowLowPower)];
}

// MARK: - Background Tasks
//
// All background task registration, scheduling, and handling is managed by
// CPBackgroundTaskManager. AppDelegate simply delegates to it, ensuring a
// single source of truth for task identifiers and lifecycle.

@end
