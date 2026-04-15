//
//  CPSplitViewController.m
//  ChargeProcure
//
//  iPad double-column split view. Primary column hosts CPSidebarViewController;
//  secondary column shows detail content selected from the sidebar.
//

#import "CPSplitViewController.h"
#import "CPSidebarViewController.h"
#import "CPDashboardViewController.h"
#import "CPAuthService.h"

// MARK: - Private interface

@interface CPSplitViewController ()

/// Navigation controller wrapping the primary (sidebar) column.
@property (nonatomic, strong) UINavigationController *primaryNavigationController;

/// Navigation controller wrapping the secondary (detail) column.
@property (nonatomic, strong) UINavigationController *secondaryNavigationController;

/// The sidebar view controller instance.
@property (nonatomic, strong) CPSidebarViewController *sidebarViewController;

@end

// MARK: - Implementation

@implementation CPSplitViewController

// MARK: - Initialisation

- (instancetype)init {
    // Use the double-column style introduced in iOS 14 which gives clear
    // primary/secondary semantics and handles column show/hide automatically.
    if (@available(iOS 14.0, *)) {
        self = [super initWithStyle:UISplitViewControllerStyleDoubleColumn];
    } else {
        self = [super init];
    }
    return self;
}

// MARK: - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.delegate = self;

    // --- Primary column: sidebar ---
    self.sidebarViewController = [[CPSidebarViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    self.primaryNavigationController =
        [[UINavigationController alloc] initWithRootViewController:self.sidebarViewController];
    self.primaryNavigationController.navigationBar.prefersLargeTitles = YES;

    // --- Secondary column: starts on Dashboard ---
    CPDashboardViewController *dashVC = [[CPDashboardViewController alloc] init];
    self.secondaryNavigationController =
        [[UINavigationController alloc] initWithRootViewController:dashVC];
    self.secondaryNavigationController.navigationBar.prefersLargeTitles = YES;

    if (@available(iOS 14.0, *)) {
        // In the iOS 14 column API we set the view controllers on each column.
        [self setViewController:self.primaryNavigationController
                      forColumn:UISplitViewControllerColumnPrimary];
        [self setViewController:self.secondaryNavigationController
                      forColumn:UISplitViewControllerColumnSecondary];

        // Show primary alongside secondary by default (both visible on iPad).
        self.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;

        // Give the primary column a sensible width range.
        self.preferredPrimaryColumnWidthFraction = 0.28;
        self.minimumPrimaryColumnWidth  = 260.0;
        self.maximumPrimaryColumnWidth  = 320.0;
    } else {
        // iOS 13 fallback: use the traditional viewControllers array.
        self.viewControllers = @[self.primaryNavigationController,
                                 self.secondaryNavigationController];
        self.preferredDisplayMode = UISplitViewControllerDisplayModeAllVisible;
        self.preferredPrimaryColumnWidthFraction = 0.28;
        self.minimumPrimaryColumnWidth  = 260.0;
        self.maximumPrimaryColumnWidth  = 320.0;
    }

    // Observe auth session changes.
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(handleAuthSessionChanged:)
     name:CPAuthSessionChangedNotification
     object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: - Public API: detail navigation

/**
 * Replaces the secondary column's root view controller with `vc`.
 * Called by CPSidebarViewController when a row is selected.
 */
- (void)showDetailViewController:(UIViewController *)vc sender:(nullable id)sender {
    if (@available(iOS 14.0, *)) {
        UINavigationController *detailNav =
            [[UINavigationController alloc] initWithRootViewController:vc];
        detailNav.navigationBar.prefersLargeTitles = YES;
        self.secondaryNavigationController = detailNav;
        [self setViewController:detailNav forColumn:UISplitViewControllerColumnSecondary];
    } else {
        [super showDetailViewController:vc sender:sender];
    }
}

// MARK: - Trait collection changes (compact / regular)

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    BOOL wasCompact = (previousTraitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);
    BOOL isCompact  = (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);

    if (wasCompact != isCompact) {
        if (isCompact) {
            // Compact: collapse to single column (e.g. iPhone or slide-over).
            if (@available(iOS 14.0, *)) {
                self.preferredDisplayMode = UISplitViewControllerDisplayModeSecondaryOnly;
            } else {
                self.preferredDisplayMode = UISplitViewControllerDisplayModePrimaryHidden;
            }
        } else {
            // Regular: show sidebar alongside detail.
            self.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
        }
    }
}

// MARK: - UISplitViewControllerDelegate

/**
 * When collapsing from regular to compact, we keep the primary (sidebar)
 * visible so the user can always navigate without getting stuck on a blank
 * detail screen.
 */
- (BOOL)splitViewController:(UISplitViewController *)splitViewController
collapseSecondaryViewController:(UIViewController *)secondaryViewController
  ontoPrimaryViewController:(UIViewController *)primaryViewController {
    // Returning YES tells the split view controller NOT to merge the secondary
    // into the primary stack — we handle the compact layout ourselves via
    // preferredDisplayMode in traitCollectionDidChange:.
    return YES;
}

/**
 * When separating back to regular width, supply our secondary column
 * navigation controller so detail content is preserved.
 */
- (nullable UIViewController *)splitViewController:(UISplitViewController *)splitViewController
  separateSecondaryViewControllerFromPrimaryViewController:(UIViewController *)primaryViewController {
    // If secondary nav already has content, use it; otherwise show Dashboard.
    if (self.secondaryNavigationController.viewControllers.count > 0) {
        return self.secondaryNavigationController;
    }
    CPDashboardViewController *dashVC = [[CPDashboardViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:dashVC];
    nav.navigationBar.prefersLargeTitles = YES;
    self.secondaryNavigationController = nav;
    return nav;
}

// MARK: - Auth session

- (void)handleAuthSessionChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL sessionValid = [[CPAuthService sharedService] isSessionValid];
        if (!sessionValid) {
            // AppDelegate will replace the root VC; nothing extra needed here.
            NSLog(@"[CPSplitViewController] Session ended — awaiting root VC replacement.");
        }
    });
}

@end
