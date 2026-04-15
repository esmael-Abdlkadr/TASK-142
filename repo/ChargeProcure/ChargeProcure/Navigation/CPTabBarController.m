//
//  CPTabBarController.m
//  ChargeProcure
//
//  Main tab bar controller for iPhone. Builds a role-aware set of tabs and
//  rebuilds itself when the auth session changes.
//

#import "CPTabBarController.h"

// View controllers for each tab
#import "CPDashboardViewController.h"
#import "CPChargerListViewController.h"
#import "CPProcurementListViewController.h"
#import "CPBulletinListViewController.h"
#import "CPAnalyticsDashboardViewController.h"
#import "CPSettingsViewController.h"

#import "CPAuthService.h"
#import "AppDelegate.h"

// MARK: - Tab indices

typedef NS_ENUM(NSUInteger, CPTabIndex) {
    CPTabIndexDashboard     = 0,
    CPTabIndexChargers      = 1,
    CPTabIndexProcurement   = 2,
    CPTabIndexBulletins     = 3,
    CPTabIndexAnalytics     = 4,
    CPTabIndexMore          = 5,
};

// MARK: - Private interface

@interface CPTabBarController ()

/// Builds the current role's tab view controllers and assigns them.
- (void)buildTabs;

/// Configures UITabBarAppearance for the current trait collection.
- (void)applyTabBarAppearance;

/// Creates a UINavigationController wrapping `vc` with the given tab metadata.
- (UINavigationController *)navControllerForViewController:(UIViewController *)vc
                                                     title:(NSString *)title
                                               systemImage:(NSString *)imageName
                                                       tag:(NSInteger)tag;

/// Returns YES when the signed-in user matches `roleName`.
- (BOOL)currentUserHasRole:(NSString *)roleName;

/// Returns YES when the current user is allowed to access the tab.
- (BOOL)currentUserHasAnyPermission:(NSArray<NSString *> *)permissions;

@end

// MARK: - Implementation

@implementation CPTabBarController

// MARK: - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    [self buildTabs];
    [self applyTabBarAppearance];

    // Observe auth session changes to tear down and rebuild (e.g. after logout
    // the AppDelegate replaces the root VC, but if this controller is somehow
    // still alive we reset to tab 0 defensively).
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(handleAuthSessionChanged:)
     name:CPAuthSessionChangedNotification
     object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: - Tab construction

- (void)buildTabs {
    BOOL isAdmin      = [self currentUserHasRole:@"Administrator"];
    BOOL isTechnician = [self currentUserHasRole:@"Site Technician"];
    BOOL isFinance    = [self currentUserHasRole:@"Finance Approver"];
    NSMutableArray<UINavigationController *> *tabs = [NSMutableArray array];

    // --- Dashboard ---
    CPDashboardViewController *dashVC = [[CPDashboardViewController alloc] init];
    UINavigationController *dashNav =
        [self navControllerForViewController:dashVC
                                       title:NSLocalizedString(@"Dashboard", nil)
                                 systemImage:@"house.fill"
                                         tag:CPTabIndexDashboard];
    [tabs addObject:dashNav];

    // --- Chargers ---
    if (isAdmin || [self currentUserHasAnyPermission:@[@"charger.read", @"charger.update", @"charger.execute"]]) {
        CPChargerListViewController *chargersVC = [[CPChargerListViewController alloc] init];
        UINavigationController *chargersNav =
            [self navControllerForViewController:chargersVC
                                           title:NSLocalizedString(@"Chargers", nil)
                                     systemImage:@"bolt.fill"
                                             tag:CPTabIndexChargers];
        [tabs addObject:chargersNav];
    }

    // --- Procurement ---
    if (isAdmin || [self currentUserHasAnyPermission:@[@"procurement.read", @"procurement.create", @"procurement.update", @"procurement.approve"]]) {
        CPProcurementListViewController *procVC = [[CPProcurementListViewController alloc] init];
        UINavigationController *procNav =
            [self navControllerForViewController:procVC
                                           title:NSLocalizedString(@"Procurement", nil)
                                     systemImage:@"doc.text.fill"
                                             tag:CPTabIndexProcurement];
        [tabs addObject:procNav];
    }

    // --- Bulletins ---
    if (isAdmin || isTechnician || [self currentUserHasAnyPermission:@[@"bulletin.read", @"bulletin.create", @"bulletin.update", @"bulletin.archive"]]) {
        CPBulletinListViewController *bulletinsVC = [[CPBulletinListViewController alloc] init];
        UINavigationController *bulletinsNav =
            [self navControllerForViewController:bulletinsVC
                                           title:NSLocalizedString(@"Bulletins", nil)
                                     systemImage:@"newspaper.fill"
                                             tag:CPTabIndexBulletins];
        [tabs addObject:bulletinsNav];
    }

    // --- Analytics ---
    if (isAdmin || isFinance) {
        CPAnalyticsDashboardViewController *analyticsVC = [[CPAnalyticsDashboardViewController alloc] init];
        UINavigationController *analyticsNav =
            [self navControllerForViewController:analyticsVC
                                           title:NSLocalizedString(@"Analytics", nil)
                                     systemImage:@"chart.bar.fill"
                                             tag:CPTabIndexAnalytics];
        [tabs addObject:analyticsNav];
    }

    // --- Settings ---
    CPSettingsViewController *settingsVC = [[CPSettingsViewController alloc] init];
    UINavigationController *settingsNav =
        [self navControllerForViewController:settingsVC
                                       title:NSLocalizedString(@"Settings", nil)
                                 systemImage:@"gearshape.fill"
                                         tag:CPTabIndexMore];
    [tabs addObject:settingsNav];

    self.viewControllers = tabs;
    self.selectedIndex = CPTabIndexDashboard;
}

- (UINavigationController *)navControllerForViewController:(UIViewController *)vc
                                                     title:(NSString *)title
                                               systemImage:(NSString *)imageName
                                                       tag:(NSInteger)tag {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = YES;

    UIImage *image = [UIImage systemImageNamed:imageName];
    UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:image tag:tag];
    nav.tabBarItem = item;

    return nav;
}

- (BOOL)currentUserHasRole:(NSString *)roleName {
    NSString *currentRole = [CPAuthService sharedService].currentUserRole;
    return [currentRole isEqualToString:roleName];
}

- (BOOL)currentUserHasAnyPermission:(NSArray<NSString *> *)permissions {
    CPAuthService *authService = [CPAuthService sharedService];
    for (NSString *permission in permissions) {
        if ([authService currentUserHasPermission:permission]) {
            return YES;
        }
    }
    return NO;
}

// MARK: - Tab bar appearance

- (void)applyTabBarAppearance {
    if (@available(iOS 15.0, *)) {
        UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
        [appearance configureWithDefaultBackground];

        // Use a translucent material (vibrancy) background that adapts to
        // dark/light mode automatically.
        appearance.backgroundEffect =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];

        // Selected item tint.
        UIColor *selectedColor = [UIColor systemBlueColor];

        // Normal (unselected) icon and label.
        UITabBarItemStateAppearance *normalState =
            appearance.stackedLayoutAppearance.normal;
        normalState.iconColor    = [UIColor secondaryLabelColor];
        normalState.titleTextAttributes =
            @{ NSForegroundColorAttributeName: [UIColor secondaryLabelColor] };

        // Selected icon and label.
        UITabBarItemStateAppearance *selectedState =
            appearance.stackedLayoutAppearance.selected;
        selectedState.iconColor    = selectedColor;
        selectedState.titleTextAttributes =
            @{ NSForegroundColorAttributeName: selectedColor };

        self.tabBar.standardAppearance   = appearance;
        self.tabBar.scrollEdgeAppearance = appearance;
    } else {
        // iOS 14 and earlier fallback.
        self.tabBar.barTintColor  = [UIColor systemBackgroundColor];
        self.tabBar.tintColor     = [UIColor systemBlueColor];
    }
}

// MARK: - Trait collection changes (dark / light mode)

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self applyTabBarAppearance];
    }
}

// MARK: - Auth session notifications

- (void)handleAuthSessionChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL sessionValid = [[CPAuthService sharedService] isSessionValid];
        if (sessionValid) {
            [self buildTabs];
        } else {
            // Session ended — replace the root VC with the login screen immediately.
            // This guarantees no protected content remains accessible after logout
            // or user-switch regardless of current navigation stack depth.
            AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
            [appDelegate configureRootViewControllerForAuthState];
        }
    });
}

@end
