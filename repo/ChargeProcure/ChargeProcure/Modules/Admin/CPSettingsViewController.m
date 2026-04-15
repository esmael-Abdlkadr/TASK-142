#import "CPSettingsViewController.h"
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "AppDelegate.h"
#import "CPExportService.h"
#import "CPAttachmentService.h"
#import "CPAuditLogViewController.h"
#import "CPUserManagementViewController.h"
#import "CPRolesPermissionsViewController.h"
#import "CPPricingRuleListViewController.h"
#import "CPDepositListViewController.h"
#import "CPCouponPackageListViewController.h"

// ---------------------------------------------------------------------------
#pragma mark - Section model
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, CPSettingsSection) {
    CPSettingsSectionAccount = 0,
    CPSettingsSectionAdministration,
    CPSettingsSectionData,
    CPSettingsSectionAbout,
    CPSettingsSectionLogout,
};

static NSString * const kSettingsCellID = @"CPSettingsCell";
static NSString * const kSettingsSwitchCellID = @"CPSettingsSwitchCell";

// ---------------------------------------------------------------------------
#pragma mark - Change password view controller (modal)
// ---------------------------------------------------------------------------

@interface CPChangePasswordViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *oldPasswordField;
@property (nonatomic, strong) UITextField *updatedPasswordField;
@property (nonatomic, strong) UITextField *confirmPasswordField;
@end

@implementation CPChangePasswordViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Change Password";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIBarButtonItem *cancelBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                               target:self
                                                                               action:@selector(_cancel)];
    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:@"Update"
                                                                style:UIBarButtonItemStyleDone
                                                               target:self
                                                               action:@selector(_submit)];
    self.navigationItem.leftBarButtonItem = cancelBtn;
    self.navigationItem.rightBarButtonItem = saveBtn;

    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:tv];
    tv.dataSource = (id<UITableViewDataSource>)self;
    tv.delegate = (id<UITableViewDelegate>)self;
    [tv registerClass:[UITableViewCell class] forCellReuseIdentifier:@"pwCell"];

    // Build fields
    _oldPasswordField = [self _makePasswordField:@"Current Password"];
    _updatedPasswordField = [self _makePasswordField:@"New Password (min 10 chars, 1 digit)"];
    _confirmPasswordField = [self _makePasswordField:@"Confirm New Password"];
}

- (UITextField *)_makePasswordField:(NSString *)placeholder {
    UITextField *f = [[UITextField alloc] init];
    f.placeholder = placeholder;
    f.secureTextEntry = YES;
    f.font = [UIFont systemFontOfSize:16.0];
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.delegate = self;
    return f;
}

// Minimal DataSource/Delegate via category trick – inline:

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"pwCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    // Remove previous subviews
    for (UIView *sub in cell.contentView.subviews) { [sub removeFromSuperview]; }

    UITextField *field;
    switch (indexPath.row) {
        case 0: field = _oldPasswordField; break;
        case 1: field = _updatedPasswordField; break;
        default: field = _confirmPasswordField; break;
    }
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [field.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];
    return cell;
}

- (void)_cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)_submit {
    NSString *old  = _oldPasswordField.text ?: @"";
    NSString *new1 = _updatedPasswordField.text ?: @"";
    NSString *new2 = _confirmPasswordField.text ?: @"";

    if (old.length == 0 || new1.length == 0 || new2.length == 0) {
        [self _showAlert:@"Missing Fields" message:@"All fields are required."];
        return;
    }
    if (![new1 isEqualToString:new2]) {
        [self _showAlert:@"Mismatch" message:@"New passwords do not match."];
        return;
    }

    NSError *error = nil;
    BOOL ok = [[CPAuthService sharedService] changePasswordForUserID:[CPAuthService sharedService].currentUserID
                                                         oldPassword:old
                                                         newPassword:new1
                                                               error:&error];
    if (!ok) {
        [self _showAlert:@"Failed" message:error.localizedDescription ?: @"Could not update password."];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)_showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - CPSettingsViewController
// ---------------------------------------------------------------------------

@interface CPSettingsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *biometricSwitch;
@property (nonatomic, assign) BOOL isAdmin;

// Section/row counts
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *rowTitles;
@end

@implementation CPSettingsViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _isAdmin = [[CPRBACService sharedService] currentUserCanPerform:CPActionCreate onResource:CPResourceUser];
    [self _buildTableView];
    [self _buildBiometricSwitch];
}

// ---------------------------------------------------------------------------
#pragma mark - UI
// ---------------------------------------------------------------------------

- (void)_buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kSettingsCellID];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kSettingsSwitchCellID];
    [self.view addSubview:_tableView];
}

- (void)_buildBiometricSwitch {
    _biometricSwitch = [[UISwitch alloc] init];
    // Reflect current setting via UserDefaults key used by CPAuthService
    _biometricSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"CPBiometricEnabled"];
    [_biometricSwitch addTarget:self action:@selector(_biometricToggled:) forControlEvents:UIControlEventValueChanged];
}

// ---------------------------------------------------------------------------
#pragma mark - Section helpers
// ---------------------------------------------------------------------------

- (NSInteger)_adminSectionIndex {
    return CPSettingsSectionAdministration;
}

- (NSInteger)_rowsInAccountSection {
    return 4; // Username, Role, Change Password, FaceID/TouchID
}

- (NSInteger)_rowsInAdminSection {
    return 6; // Manage Users, Roles & Permissions, Audit Log, Pricing Rules, Deposits, Coupons
}

- (NSInteger)_rowsInDataSection {
    return 2; // Export Data, Run Cleanup
}

- (NSInteger)_rowsInAboutSection {
    return 3; // Version, Build, Device Info
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _isAdmin ? 5 : 4; // Skip admin section for non-admins
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    CPSettingsSection sec = [self _settingsSectionForTableSection:section];
    switch (sec) {
        case CPSettingsSectionAccount:        return [self _rowsInAccountSection];
        case CPSettingsSectionAdministration: return [self _rowsInAdminSection];
        case CPSettingsSectionData:           return [self _rowsInDataSection];
        case CPSettingsSectionAbout:          return [self _rowsInAboutSection];
        case CPSettingsSectionLogout:         return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    CPSettingsSection sec = [self _settingsSectionForTableSection:section];
    switch (sec) {
        case CPSettingsSectionAccount:        return @"Account";
        case CPSettingsSectionAdministration: return @"Administration";
        case CPSettingsSectionData:           return @"Data";
        case CPSettingsSectionAbout:          return @"About";
        case CPSettingsSectionLogout:         return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPSettingsSection sec = [self _settingsSectionForTableSection:indexPath.section];

    switch (sec) {
        case CPSettingsSectionAccount:
            return [self _accountCellForRow:indexPath.row tableView:tableView];
        case CPSettingsSectionAdministration:
            return [self _adminCellForRow:indexPath.row tableView:tableView];
        case CPSettingsSectionData:
            return [self _dataCellForRow:indexPath.row tableView:tableView];
        case CPSettingsSectionAbout:
            return [self _aboutCellForRow:indexPath.row tableView:tableView];
        case CPSettingsSectionLogout:
            return [self _logoutCellForTableView:tableView];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Cell builders
// ---------------------------------------------------------------------------

- (UITableViewCell *)_accountCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kSettingsCellID];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    switch (row) {
        case 0: {
            cell.textLabel.text = @"Username";
            cell.detailTextLabel.text = [CPAuthService sharedService].currentUsername ?: @"—";
            cell = [self _valueCell:@"Username"
                             detail:[CPAuthService sharedService].currentUsername ?: @"—"
                          tableView:tv];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case 1: {
            cell = [self _valueCell:@"Role"
                             detail:[CPAuthService sharedService].currentUserRole ?: @"—"
                          tableView:tv];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case 2: {
            cell.textLabel.text = @"Change Password";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 3: {
            cell.textLabel.text = @"Face ID / Touch ID";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryView = _biometricSwitch;
            break;
        }
    }
    return cell;
}

- (UITableViewCell *)_adminCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kSettingsCellID];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryView = nil;

    NSArray *titles = @[@"Manage Users", @"Roles & Permissions", @"Audit Log", @"Pricing Rules",
                        @"Deposits & Pre-Auths", @"Coupon Packages"];
    cell.textLabel.text = titles[row];
    return cell;
}

- (UITableViewCell *)_dataCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kSettingsCellID];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    NSArray *titles = @[@"Export Data", @"Run Cleanup Now"];
    cell.textLabel.text = titles[row];
    return cell;
}

- (UITableViewCell *)_aboutCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"—";
    NSString *build = info[@"CFBundleVersion"] ?: @"—";
    UIDevice *device = [UIDevice currentDevice];
    NSString *deviceInfo = [NSString stringWithFormat:@"%@ · iOS %@", device.model, device.systemVersion];

    NSArray *titles = @[@"App Version", @"Build Number", @"Device"];
    NSArray *details = @[version, build, deviceInfo];

    UITableViewCell *cell = [self _valueCell:titles[row] detail:details[row] tableView:tv];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)_logoutCellForTableView:(UITableView *)tv {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kSettingsCellID];
    cell.textLabel.text = @"Log Out";
    cell.textLabel.textColor = [UIColor systemRedColor];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)_valueCell:(NSString *)title detail:(NSString *)detail tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CPSettingsSection sec = [self _settingsSectionForTableSection:indexPath.section];

    switch (sec) {
        case CPSettingsSectionAccount:
            [self _handleAccountRowTap:indexPath.row];
            break;
        case CPSettingsSectionAdministration:
            [self _handleAdminRowTap:indexPath.row];
            break;
        case CPSettingsSectionData:
            [self _handleDataRowTap:indexPath.row];
            break;
        case CPSettingsSectionAbout:
            break; // read-only
        case CPSettingsSectionLogout:
            [self _handleLogout];
            break;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Row tap handlers
// ---------------------------------------------------------------------------

- (void)_handleAccountRowTap:(NSInteger)row {
    switch (row) {
        case 2: { // Change Password
            CPChangePasswordViewController *vc = [[CPChangePasswordViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFormSheet;
            [self presentViewController:nav animated:YES completion:nil];
            break;
        }
        default:
            break;
    }
}

- (void)_handleAdminRowTap:(NSInteger)row {
    UIViewController *vc = nil;
    switch (row) {
        case 0: vc = [[CPUserManagementViewController alloc] init]; break;
        case 1: vc = [[CPRolesPermissionsViewController alloc] init]; break;
        case 2: vc = [[CPAuditLogViewController alloc] init]; break;
        case 3: vc = [[CPPricingRuleListViewController alloc] init]; break;
        case 4: vc = [[CPDepositListViewController alloc] init]; break;
        case 5: vc = [[CPCouponPackageListViewController alloc] init]; break;
    }
    if (vc) {
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)_handleDataRowTap:(NSInteger)row {
    switch (row) {
        case 0: // Export Data
            [self _handleExportData];
            break;
        case 1: // Run Cleanup
            [self _handleRunCleanup];
            break;
    }
}

- (void)_handleExportData {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Export Data"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    NSDictionary *reportNames = @{
        @"Procurement Summary (CSV)": @[@(CPReportTypeProcurementSummary), @(CPExportFormatCSV)],
        @"Procurement Summary (PDF)": @[@(CPReportTypeProcurementSummary), @(CPExportFormatPDF)],
        @"Vendor Statements (CSV)":   @[@(CPReportTypeVendorStatement),     @(CPExportFormatCSV)],
        @"Audit Log (CSV)":           @[@(CPReportTypeAuditLog),            @(CPExportFormatCSV)],
        @"Analytics Summary (PDF)":   @[@(CPReportTypeAnalyticsSummary),    @(CPExportFormatPDF)],
    };

    for (NSString *title in reportNames) {
        NSArray *params = reportNames[title];
        CPReportType rType = (CPReportType)[params[0] integerValue];
        CPExportFormat rFmt = (CPExportFormat)[params[1] integerValue];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf _exportReportType:rType format:rFmt];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0,
                                                                 self.view.bounds.size.height / 2.0, 1.0, 1.0);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)_exportReportType:(CPReportType)type format:(CPExportFormat)format {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    UIBarButtonItem *oldBtn = self.navigationItem.rightBarButtonItem;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

    __weak typeof(self) weakSelf = self;
    [[CPExportService sharedService] generateReport:type format:format parameters:nil
                                         completion:^(NSURL *fileURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.navigationItem.rightBarButtonItem = oldBtn;
            if (error || !fileURL) {
                [weakSelf _showAlert:@"Export Failed" message:error.localizedDescription ?: @"Unknown error."];
                return;
            }
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                              applicationActivities:nil];
            avc.popoverPresentationController.sourceView = weakSelf.view;
            [weakSelf presentViewController:avc animated:YES completion:nil];
        });
    }];
}

- (void)_handleRunCleanup {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Run Cleanup"
                                                                     message:@"This will delete unreferenced files and drafts older than 90 days. Continue?"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"Run Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [weakSelf _performCleanup];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)_performCleanup {
    // Show spinner in table footer
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    spinner.center = CGPointMake(footer.bounds.size.width / 2.0, footer.bounds.size.height / 2.0);
    [footer addSubview:spinner];
    _tableView.tableFooterView = footer;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[CPAttachmentService sharedService] runWeeklyCleanup];
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.tableView.tableFooterView = nil;
            [weakSelf _showAlert:@"Cleanup Complete" message:@"Orphaned files and old drafts have been removed."];
        });
    });
}

- (void)_handleLogout {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Log Out"
                                                                     message:@"Are you sure you want to log out?"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"Log Out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)weakSelf; // suppress unused warning
        [[CPAuthService sharedService] logout];
        // Delegate root-VC replacement to AppDelegate so the login screen is
        // guaranteed regardless of current navigation stack depth or device type.
        AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
        [appDelegate configureRootViewControllerForAuthState];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Biometric toggle
// ---------------------------------------------------------------------------

- (void)_biometricToggled:(UISwitch *)sender {
    [[CPAuthService sharedService] setBiometricEnabled:sender.isOn];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

/// Map from table section index → CPSettingsSection (skipping admin when not admin)
- (CPSettingsSection)_settingsSectionForTableSection:(NSInteger)section {
    if (_isAdmin) {
        return (CPSettingsSection)section;
    }
    // Non-admin: skip CPSettingsSectionAdministration (index 1)
    if (section >= CPSettingsSectionAdministration) {
        return (CPSettingsSection)(section + 1);
    }
    return (CPSettingsSection)section;
}

- (void)_showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
