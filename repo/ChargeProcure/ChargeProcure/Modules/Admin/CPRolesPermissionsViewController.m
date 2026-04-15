#import "CPRolesPermissionsViewController.h"
#import "CPRBACService.h"
#import "CPAuthService.h"

// ---------------------------------------------------------------------------
// Permission row cell
// ---------------------------------------------------------------------------
@interface CPPermissionCell : UITableViewCell
@property (nonatomic, strong) UILabel  *permissionLabel;
@property (nonatomic, strong) UISwitch *grantSwitch;
@property (nonatomic, copy)   void (^onToggle)(BOOL granted);
@end

@implementation CPPermissionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    self.permissionLabel = [UILabel new];
    self.permissionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.permissionLabel.font = [UIFont systemFontOfSize:14];
    [self.contentView addSubview:self.permissionLabel];

    self.grantSwitch = [[UISwitch alloc] init];
    self.grantSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.grantSwitch addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.grantSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [self.permissionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.permissionLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.permissionLabel.trailingAnchor constraintEqualToAnchor:self.grantSwitch.leadingAnchor constant:-8],

        [self.grantSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.grantSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
    ]];
    return self;
}

- (void)switchToggled:(UISwitch *)sw {
    if (self.onToggle) self.onToggle(sw.isOn);
}

@end

// ---------------------------------------------------------------------------
// Main view controller
// ---------------------------------------------------------------------------

// Canonical business roles.
static NSArray<NSString *> *CPCanonicalRoles(void) {
    return @[@"Administrator", @"Site Technician", @"Finance Approver"];
}

// All resource+action pairs shown in the permissions grid.
static NSArray<NSDictionary *> *CPAllPermissionPairs(void) {
    NSArray *resources = @[CPResourceCharger, CPResourceProcurement, CPResourceBulletin,
                            CPResourcePricing, CPResourceUser, CPResourceAudit,
                            CPResourceInvoice, CPResourceWriteOff, CPResourceReport];
    NSArray *actions   = @[CPActionRead, CPActionCreate, CPActionUpdate, CPActionDelete,
                            CPActionApprove, CPActionExecute, CPActionExport];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *res in resources) {
        for (NSString *act in actions) {
            [pairs addObject:@{@"resource": res, @"action": act}];
        }
    }
    return [pairs copy];
}

@interface CPRolesPermissionsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UISegmentedControl *rolePicker;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy)   NSString *selectedRole;
/// Cached set of "resource:action" strings currently granted for the selected role.
@property (nonatomic, strong) NSMutableSet<NSString *> *grantedSet;
@property (nonatomic, strong) NSArray<NSDictionary *> *allPairs;
@end

@implementation CPRolesPermissionsViewController

static NSString * const kPermCellID = @"CPPermissionCell";

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Roles & Permissions";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.allPairs = CPAllPermissionPairs();

    // Guard: only admins may access this screen.
    if (![[CPAuthService sharedService] currentUserHasPermission:@"admin"]) {
        [self showAccessDenied];
        return;
    }

    [self buildRolePicker];
    [self buildTableView];
    [self selectRole:CPCanonicalRoles().firstObject];
}

// ---------------------------------------------------------------------------
#pragma mark - UI setup
// ---------------------------------------------------------------------------

- (void)buildRolePicker {
    NSArray<NSString *> *roles = CPCanonicalRoles();
    self.rolePicker = [[UISegmentedControl alloc] initWithItems:roles];
    self.rolePicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.rolePicker.selectedSegmentIndex = 0;
    [self.rolePicker addTarget:self action:@selector(rolePickerChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.rolePicker];

    [NSLayoutConstraint activateConstraints:@[
        [self.rolePicker.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.rolePicker.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.rolePicker.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    ]];
}

- (void)buildTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 44;
    [self.tableView registerClass:[CPPermissionCell class] forCellReuseIdentifier:kPermCellID];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.rolePicker.bottomAnchor constant:12],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)showAccessDenied {
    self.title = @"Access Denied";
    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = @"Administrator access required.";
    lbl.textColor = [UIColor secondaryLabelColor];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.numberOfLines = 0;
    [self.view addSubview:lbl];
    [NSLayoutConstraint activateConstraints:@[
        [lbl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [lbl.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [lbl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [lbl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];
}

// ---------------------------------------------------------------------------
#pragma mark - Role selection
// ---------------------------------------------------------------------------

- (void)rolePickerChanged:(UISegmentedControl *)picker {
    [self selectRole:CPCanonicalRoles()[(NSUInteger)picker.selectedSegmentIndex]];
}

- (void)selectRole:(NSString *)roleName {
    self.selectedRole = roleName;
    // Build granted set from CPRBACService.
    NSArray *perms = [[CPRBACService sharedService] permissionsForRoleName:roleName];
    self.grantedSet = [NSMutableSet set];
    for (NSDictionary *p in perms) {
        NSString *key = [NSString stringWithFormat:@"%@:%@", p[@"resource"], p[@"action"]];
        [self.grantedSet addObject:key];
    }
    [self.tableView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.allPairs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPPermissionCell *cell = [tableView dequeueReusableCellWithIdentifier:kPermCellID forIndexPath:indexPath];
    NSDictionary *pair = self.allPairs[(NSUInteger)indexPath.row];
    NSString *resource = pair[@"resource"];
    NSString *action   = pair[@"action"];
    NSString *key = [NSString stringWithFormat:@"%@:%@", resource, action];

    cell.permissionLabel.text = [NSString stringWithFormat:@"%@ · %@", resource, action];
    cell.grantSwitch.on = [self.grantedSet containsObject:key];

    // Disable grant/revoke on the Administrator role — it always holds all permissions.
    cell.grantSwitch.enabled = ![self.selectedRole isEqualToString:@"Administrator"];

    __weak typeof(self) weakSelf = self;
    cell.onToggle = ^(BOOL granted) {
        [weakSelf togglePermission:action onResource:resource granted:granted key:key];
    };
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"Permissions for %@", self.selectedRole];
}

// ---------------------------------------------------------------------------
#pragma mark - Grant / Revoke
// ---------------------------------------------------------------------------

- (void)togglePermission:(NSString *)action
              onResource:(NSString *)resource
                 granted:(BOOL)granted
                     key:(NSString *)key {
    NSError *error = nil;
    BOOL ok;
    if (granted) {
        ok = [[CPRBACService sharedService] grantPermission:action
                                                 onResource:resource
                                                     toRole:self.selectedRole
                                                      error:&error];
        if (ok) { [self.grantedSet addObject:key]; }
    } else {
        ok = [[CPRBACService sharedService] revokePermission:action
                                                  onResource:resource
                                                    fromRole:self.selectedRole
                                                       error:&error];
        if (ok) { [self.grantedSet removeObject:key]; }
    }

    if (!ok) {
        NSString *msg = error.localizedDescription ?: @"Could not update permission.";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
            message:msg preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        // Revert the switch by reloading
        [self.tableView reloadData];
    }
}

@end
