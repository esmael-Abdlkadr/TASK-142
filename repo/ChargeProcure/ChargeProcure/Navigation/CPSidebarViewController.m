//
//  CPSidebarViewController.m
//  ChargeProcure
//
//  iPad sidebar navigation. Displayed in the primary column of
//  CPSplitViewController. Tapping a row replaces the secondary column detail.
//

#import "CPSidebarViewController.h"
#import "CPSplitViewController.h"

// Detail view controllers
#import "CPDashboardViewController.h"
#import "CPChargerListViewController.h"
#import "CPProcurementListViewController.h"

// Auth / access control
#import "CPAuthService.h"
#import "CPRBACService.h"

// MARK: - Sidebar item model

@interface CPSidebarItem : NSObject
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *systemImageName;
@property (nonatomic, copy)   NSString *detailViewControllerClassName;
@property (nonatomic, assign) NSInteger tag;
+ (instancetype)itemWithTitle:(NSString *)title
                  systemImage:(NSString *)imageName
             detailClassName:(NSString *)className
                          tag:(NSInteger)tag;
@end

@implementation CPSidebarItem
+ (instancetype)itemWithTitle:(NSString *)title
                  systemImage:(NSString *)imageName
             detailClassName:(NSString *)className
                          tag:(NSInteger)tag {
    CPSidebarItem *item = [[CPSidebarItem alloc] init];
    item.title                          = title;
    item.systemImageName                = imageName;
    item.detailViewControllerClassName  = className;
    item.tag                            = tag;
    return item;
}
@end

// MARK: - Required sidebar class registry

/// The set of class names that MUST resolve to concrete UIViewController subclasses.
/// Any entry that cannot be resolved at runtime is a hard programming error —
/// an assert fires in DEBUG builds and the sidebar falls back to the Dashboard
/// (never a "coming soon" placeholder) in RELEASE builds.
static NSSet<NSString *> *CPRequiredSidebarClassNames(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"CPDashboardViewController",
            @"CPChargerListViewController",
            @"CPProcurementListViewController",
            @"CPBulletinListViewController",
            @"CPAnalyticsDashboardViewController",
            @"CPReportsViewController",
            @"CPSettingsViewController",
        ]];
    });
    return s;
}

// MARK: - Static cell reuse identifier

static NSString * const kSidebarCellID = @"CPSidebarCell";

// MARK: - Private interface

@interface CPSidebarViewController ()

/// Ordered list of sidebar navigation items.
@property (nonatomic, strong) NSArray<CPSidebarItem *> *items;

/// Index of the currently selected row (-1 = none).
@property (nonatomic, assign) NSInteger selectedIndex;

@end

// MARK: - Implementation

@implementation CPSidebarViewController

// MARK: - Lifecycle

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self) {
        _selectedIndex = 0; // Dashboard selected by default
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"ChargeProcure", nil);
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self buildItems];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kSidebarCellID];

    // Rebuild sidebar whenever the auth session changes (login, logout, user-switch)
    // so the exposed modules always reflect the current user's role.
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(handleAuthSessionChanged:)
     name:CPAuthSessionChangedNotification
     object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleAuthSessionChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self buildItems];
        [self.tableView reloadData];
        // Re-select row 0 (Dashboard is always first).
        self.selectedIndex = 0;
        NSIndexPath *firstPath = [NSIndexPath indexPathForRow:0 inSection:0];
        [self.tableView selectRowAtIndexPath:firstPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Ensure the initial selection is visually highlighted.
    NSIndexPath *initialPath = [NSIndexPath indexPathForRow:self.selectedIndex inSection:0];
    [self.tableView selectRowAtIndexPath:initialPath animated:NO scrollPosition:UITableViewScrollPositionNone];
}

// MARK: - Item configuration

/// Builds the sidebar item list filtered to the current user's role and permissions.
/// Mirrors the role-gating logic in CPTabBarController so iPhone and iPad
/// expose exactly the same modules for a given user.
- (void)buildItems {
    CPAuthService  *auth  = [CPAuthService sharedService];
    CPRBACService  *rbac  = [CPRBACService sharedService];

    BOOL isAdmin      = [auth.currentUserRole isEqualToString:@"Administrator"];
    BOOL isTechnician = [auth.currentUserRole isEqualToString:@"Site Technician"];
    BOOL isFinance    = [auth.currentUserRole isEqualToString:@"Finance Approver"];

    NSMutableArray<CPSidebarItem *> *items = [NSMutableArray array];
    NSInteger tag = 0;

    // Dashboard — always visible when authenticated.
    [items addObject:[CPSidebarItem itemWithTitle:NSLocalizedString(@"Dashboard", nil)
                                      systemImage:@"house.fill"
                                 detailClassName:@"CPDashboardViewController"
                                              tag:tag++]];

    // Chargers
    if (isAdmin ||
        [rbac currentUserCanPerform:CPActionRead    onResource:CPResourceCharger] ||
        [rbac currentUserCanPerform:CPActionUpdate  onResource:CPResourceCharger] ||
        [rbac currentUserCanPerform:CPActionExecute onResource:CPResourceCharger]) {
        [items addObject:[CPSidebarItem itemWithTitle:NSLocalizedString(@"Chargers", nil)
                                          systemImage:@"bolt.fill"
                                     detailClassName:@"CPChargerListViewController"
                                                  tag:tag++]];
    }

    // Procurement
    if (isAdmin ||
        [rbac currentUserCanPerform:CPActionRead    onResource:CPResourceProcurement] ||
        [rbac currentUserCanPerform:CPActionCreate  onResource:CPResourceProcurement] ||
        [rbac currentUserCanPerform:CPActionUpdate  onResource:CPResourceProcurement] ||
        [rbac currentUserCanPerform:CPActionApprove onResource:CPResourceProcurement]) {
        [items addObject:[CPSidebarItem itemWithTitle:NSLocalizedString(@"Procurement", nil)
                                          systemImage:@"doc.text.fill"
                                     detailClassName:@"CPProcurementListViewController"
                                                  tag:tag++]];
    }

    // Bulletins
    if (isAdmin || isTechnician ||
        [rbac currentUserCanPerform:CPActionRead   onResource:CPResourceBulletin] ||
        [rbac currentUserCanPerform:CPActionCreate onResource:CPResourceBulletin] ||
        [rbac currentUserCanPerform:CPActionUpdate onResource:CPResourceBulletin]) {
        [items addObject:[CPSidebarItem itemWithTitle:NSLocalizedString(@"Bulletins", nil)
                                          systemImage:@"newspaper.fill"
                                     detailClassName:@"CPBulletinListViewController"
                                                  tag:tag++]];
    }

    // Analytics — admin and finance only
    if (isAdmin || isFinance) {
        [items addObject:[CPSidebarItem itemWithTitle:NSLocalizedString(@"Analytics", nil)
                                          systemImage:@"chart.bar.fill"
                                     detailClassName:@"CPAnalyticsDashboardViewController"
                                                  tag:tag++]];
    }

    // Reports — only for users with report.export permission
    if (isAdmin ||
        [rbac currentUserCanPerform:CPActionExport onResource:CPResourceReport] ||
        [rbac currentUserCanPerform:CPActionRead   onResource:CPResourceReport]) {
        [items addObject:[CPSidebarItem itemWithTitle:NSLocalizedString(@"Reports", nil)
                                          systemImage:@"doc.richtext.fill"
                                     detailClassName:@"CPReportsViewController"
                                                  tag:tag++]];
    }

    // Settings — always available to authenticated users.
    [items addObject:[CPSidebarItem itemWithTitle:NSLocalizedString(@"Settings", nil)
                                      systemImage:@"gearshape.fill"
                                 detailClassName:@"CPSettingsViewController"
                                              tag:tag++]];

    self.items = [items copy];
}

// MARK: - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSidebarCellID
                                                            forIndexPath:indexPath];
    CPSidebarItem *item = self.items[(NSUInteger)indexPath.row];

    // Use UIListContentConfiguration for modern cell layout (iOS 14+).
    if (@available(iOS 14.0, *)) {
        UIListContentConfiguration *config =
            [UIListContentConfiguration sidebarCellConfiguration];
        config.text  = item.title;
        config.image = [UIImage systemImageNamed:item.systemImageName];
        config.imageProperties.tintColor = [UIColor systemBlueColor];
        cell.contentConfiguration = config;
    } else {
        // iOS 13 fallback.
        cell.textLabel.text = item.title;
        cell.imageView.image = [UIImage systemImageNamed:item.systemImageName];
        cell.imageView.tintColor = [UIColor systemBlueColor];
    }

    cell.accessibilityLabel = item.title;
    cell.accessibilityTraits |= UIAccessibilityTraitButton;

    return cell;
}

// MARK: - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedIndex = indexPath.row;
    CPSidebarItem *item = self.items[(NSUInteger)indexPath.row];
    [self showDetailForItem:item];
}

// MARK: - Detail navigation

- (void)showDetailForItem:(CPSidebarItem *)item {
    UIViewController *detailVC = [self instantiateViewControllerForClassName:item.detailViewControllerClassName];
    detailVC.title = item.title;

    // Navigate through the split view controller.
    [self.splitViewController showDetailViewController:detailVC sender:self];
}

/// Returns an instance of the named class.
/// For required sidebar modules an unresolvable class name triggers a DEBUG
/// assertion (fail-fast) and falls back to CPDashboardViewController in RELEASE.
/// Only non-required / future class names produce a generic placeholder.
- (UIViewController *)instantiateViewControllerForClassName:(NSString *)className {
    Class cls = NSClassFromString(className);
    if (cls && [cls isSubclassOfClass:[UIViewController class]]) {
        if ([cls isSubclassOfClass:[UITableViewController class]]) {
            return [[cls alloc] initWithStyle:UITableViewStylePlain];
        }
        return [[cls alloc] init];
    }

    BOOL isRequired = [CPRequiredSidebarClassNames() containsObject:className];

    // A missing required class is always a programming error — fail fast in DEBUG.
    NSAssert(!isRequired,
             @"[CPSidebarViewController] Required class '%@' is not linked into the binary. "
             @"Ensure the view controller is included in the app target.", className);

    if (isRequired) {
        // RELEASE safety net: fall back to Dashboard rather than showing a blank screen.
        NSLog(@"[CPSidebarViewController] CRITICAL: required class '%@' unresolvable — "
              @"falling back to Dashboard.", className);
        Class dash = NSClassFromString(@"CPDashboardViewController");
        return dash ? [[dash alloc] init] : [[UIViewController alloc] init];
    }

    // Only non-required (optional / future) entries use the generic placeholder.
    UIViewController *placeholder = [[UIViewController alloc] init];
    placeholder.view.backgroundColor = [UIColor systemBackgroundColor];
    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"%@ — not yet available", className];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [placeholder.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:placeholder.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:placeholder.view.centerYAnchor],
    ]];
    NSLog(@"[CPSidebarViewController] NOTE: optional class '%@' not found, using placeholder.", className);
    return placeholder;
}

@end
