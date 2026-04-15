#import "CPVendorDetailViewController.h"
#import "CPVendorStatementViewController.h"
#import "CPProcurementCaseViewController.h"
#import "CPCoreDataStack.h"
#import "CPExportService.h"
#import "CPProcurementService.h"
#import "CPNumberFormatter.h"
#import "CPDateFormatter.h"
#import "CPIDGenerator.h"
#import "CPVendor+CoreDataClass.h"
#import "CPVendor+CoreDataProperties.h"
#import "CPProcurementCase+CoreDataClass.h"
#import "CPProcurementCase+CoreDataProperties.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
#pragma mark - Section / Row identifiers
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, CPVendorDetailSection) {
    CPVendorDetailSectionFields = 0,
    CPVendorDetailSectionStatus,
    CPVendorDetailSectionCases,
    CPVendorDetailSectionStatement,
    CPVendorDetailSectionCount,
};

static NSString * const kFieldCellID   = @"CPFieldCell";
static NSString * const kCaseCellID    = @"CPCaseCellID";
static NSString * const kBasicCellID   = @"CPBasicCellID";

// ---------------------------------------------------------------------------
#pragma mark - Inline text field cell
// ---------------------------------------------------------------------------

@interface CPTextFieldCell : UITableViewCell
@property (nonatomic, strong) UITextField *textField;
+ (instancetype)cellForTableView:(UITableView *)tv;
@end

@implementation CPTextFieldCell

+ (instancetype)cellForTableView:(UITableView *)tv {
    CPTextFieldCell *cell = [tv dequeueReusableCellWithIdentifier:kFieldCellID];
    if (!cell) {
        cell = [[CPTextFieldCell alloc] initWithStyle:UITableViewCellStyleDefault
                                     reuseIdentifier:kFieldCellID];
    }
    return cell;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _textField = [[UITextField alloc] init];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.font = [UIFont systemFontOfSize:16.0];
        _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _textField.returnKeyType = UIReturnKeyNext;
        [self.contentView addSubview:_textField];
        [NSLayoutConstraint activateConstraints:@[
            [_textField.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_textField.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],
            [_textField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_textField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_textField.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        ]];
    }
    return self;
}

@end

// ---------------------------------------------------------------------------
#pragma mark - View controller
// ---------------------------------------------------------------------------

@interface CPVendorDetailViewController () <UITableViewDelegate, UITableViewDataSource,
                                            UITextFieldDelegate>

// Model
@property (nonatomic, strong, nullable) CPVendor *vendor;
@property (nonatomic, strong) NSArray<CPProcurementCase *> *recentCases;

// UI
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIBarButtonItem *saveButton;

// Fields (sourced from text cells)
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *contactNameField;
@property (nonatomic, strong) UITextField *contactEmailField;
@property (nonatomic, strong) UITextField *contactPhoneField;
@property (nonatomic, strong) UITextField *addressField;
@property (nonatomic, strong) UISwitch *activeSwitch;

// Statement
@property (nonatomic, strong) NSDate *selectedStatementMonth;
@property (nonatomic, strong) UIDatePicker *monthPicker;

@end

@implementation CPVendorDetailViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self _loadVendor];
    [self _buildNavigationItems];
    [self _buildTableView];
    [self _initSelectedMonth];
}

- (void)_loadVendor {
    if (self.vendorUUID) {
        NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
        NSFetchRequest *req = [CPVendor fetchRequest];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", self.vendorUUID];
        req.fetchLimit = 1;
        NSArray *results = [ctx executeFetchRequest:req error:nil];
        _vendor = results.firstObject;
        self.title = _vendor.name ?: @"Vendor";
        [self _loadRecentCases];
    } else {
        self.title = @"New Vendor";
        _recentCases = @[];
    }
}

- (void)_loadRecentCases {
    if (!_vendor.uuid) { _recentCases = @[]; return; }
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [CPProcurementCase fetchRequest];
    req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", _vendor.name];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
    req.fetchLimit = 10;
    _recentCases = [ctx executeFetchRequest:req error:nil] ?: @[];
}

- (void)_initSelectedMonth {
    // Default to current month
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comps = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:[NSDate date]];
    _selectedStatementMonth = [cal dateFromComponents:comps];
}

// ---------------------------------------------------------------------------
#pragma mark - UI Construction
// ---------------------------------------------------------------------------

- (void)_buildNavigationItems {
    _saveButton = [[UIBarButtonItem alloc] initWithTitle:(_vendor ? @"Save" : @"Create")
                                                   style:UIBarButtonItemStyleDone
                                                  target:self
                                                  action:@selector(_handleSave)];
    self.navigationItem.rightBarButtonItem = _saveButton;

    if (!_vendor) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self
                                                                                      action:@selector(_handleCancel)];
        self.navigationItem.leftBarButtonItem = cancelButton;
    }
}

- (void)_buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (UIDatePicker *)_buildMonthPicker {
    UIDatePicker *picker = [[UIDatePicker alloc] init];
    picker.datePickerMode = UIDatePickerModeDate;
    if (@available(iOS 13.4, *)) {
        picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    }
    picker.maximumDate = [NSDate date];
    [picker addTarget:self action:@selector(_monthPickerChanged:) forControlEvents:UIControlEventValueChanged];
    if (_selectedStatementMonth) {
        picker.date = _selectedStatementMonth;
    }
    return picker;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CPVendorDetailSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((CPVendorDetailSection)section) {
        case CPVendorDetailSectionFields:    return 5; // name, contactName, email, phone, address
        case CPVendorDetailSectionStatus:   return 1;
        case CPVendorDetailSectionCases:    return MAX(1, (NSInteger)_recentCases.count);
        case CPVendorDetailSectionStatement: return 3; // month picker, generate button, export button
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ((CPVendorDetailSection)section) {
        case CPVendorDetailSectionFields:    return @"Vendor Information";
        case CPVendorDetailSectionStatus:   return @"Status";
        case CPVendorDetailSectionCases:    return @"Recent Procurement Cases";
        case CPVendorDetailSectionStatement: return @"Vendor Statement";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ((CPVendorDetailSection)indexPath.section) {
        case CPVendorDetailSectionFields:
            return [self _fieldCellForRow:indexPath.row tableView:tableView];
        case CPVendorDetailSectionStatus:
            return [self _statusCellForTableView:tableView];
        case CPVendorDetailSectionCases:
            return [self _caseCellForRow:indexPath.row tableView:tableView];
        case CPVendorDetailSectionStatement:
            return [self _statementCellForRow:indexPath.row tableView:tableView];
        default:
            return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    }
}

- (UITableViewCell *)_fieldCellForRow:(NSInteger)row tableView:(UITableView *)tableView {
    CPTextFieldCell *cell = [CPTextFieldCell cellForTableView:tableView];
    cell.textField.delegate = self;
    cell.textField.tag = row;

    switch (row) {
        case 0:
            cell.textField.placeholder = @"Vendor Name *";
            cell.textField.text = _vendor.name;
            cell.textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
            _nameField = cell.textField;
            break;
        case 1:
            cell.textField.placeholder = @"Contact Name";
            cell.textField.text = _vendor.contactName;
            cell.textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
            _contactNameField = cell.textField;
            break;
        case 2:
            cell.textField.placeholder = @"Contact Email";
            cell.textField.text = _vendor.contactEmail;
            cell.textField.keyboardType = UIKeyboardTypeEmailAddress;
            cell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            _contactEmailField = cell.textField;
            break;
        case 3:
            cell.textField.placeholder = @"Contact Phone";
            cell.textField.text = _vendor.contactPhone;
            cell.textField.keyboardType = UIKeyboardTypePhonePad;
            _contactPhoneField = cell.textField;
            break;
        case 4:
            cell.textField.placeholder = @"Address";
            cell.textField.text = _vendor.address;
            cell.textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
            _addressField = cell.textField;
            break;
    }
    return cell;
}

- (UITableViewCell *)_statusCellForTableView:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kBasicCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kBasicCellID];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = @"Active";

    if (!_activeSwitch) {
        _activeSwitch = [[UISwitch alloc] init];
        [_activeSwitch addTarget:self action:@selector(_activeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    }
    // Default new vendors to active
    _activeSwitch.on = _vendor ? [_vendor.isActive boolValue] : YES;
    cell.accessoryView = _activeSwitch;
    return cell;
}

- (UITableViewCell *)_caseCellForRow:(NSInteger)row tableView:(UITableView *)tableView {
    if (_recentCases.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kBasicCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kBasicCellID];
        }
        cell.textLabel.text = @"No procurement cases";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCaseCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCaseCellID];
    }
    CPProcurementCase *pc = _recentCases[row];
    cell.textLabel.text = pc.title ?: pc.caseNumber;
    NSString *amountStr = pc.estimatedAmount
        ? [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:pc.estimatedAmount]
        : @"—";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", pc.caseNumber ?: @"", amountStr];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)_statementCellForRow:(NSInteger)row tableView:(UITableView *)tableView {
    switch (row) {
        case 0: {
            // Month picker cell
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CPMonthPickerCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CPMonthPickerCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UIDatePicker *picker = [self _buildMonthPicker];
                _monthPicker = picker;
                picker.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:picker];
                [NSLayoutConstraint activateConstraints:@[
                    [picker.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
                    [picker.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
                    [picker.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
                ]];
            }
            return cell;
        }
        case 1: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CPGenerateStatementCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CPGenerateStatementCell"];
            }
            cell.textLabel.text = @"Generate Statement";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
        case 2: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CPExportStatementCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CPExportStatementCell"];
            }
            cell.textLabel.text = @"Export Statement";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
        default:
            return [[UITableViewCell alloc] init];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == CPVendorDetailSectionCases && _recentCases.count > 0) {
        CPProcurementCase *pc = _recentCases[indexPath.row];
        CPProcurementCaseViewController *vc = [[CPProcurementCaseViewController alloc] init];
        vc.caseUUID = pc.uuid;
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    if (indexPath.section == CPVendorDetailSectionStatement) {
        switch (indexPath.row) {
            case 1:
                [self _handleGenerateStatement];
                break;
            case 2:
                [self _handleExportStatement];
                break;
        }
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == CPVendorDetailSectionStatement && indexPath.row == 0) {
        return 180.0;
    }
    return UITableViewAutomaticDimension;
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)_activeSwitchChanged:(UISwitch *)sender {
    // will be applied on save
}

- (void)_monthPickerChanged:(UIDatePicker *)picker {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comps = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:picker.date];
    _selectedStatementMonth = [cal dateFromComponents:comps];
}

- (void)_handleGenerateStatement {
    if (!_vendor) {
        [self _showAlert:@"Save Vendor" message:@"Please save the vendor before generating a statement."];
        return;
    }

    NSArray *statementData = [[CPProcurementService sharedService]
                              generateVendorStatementForVendor:_vendor.uuid
                              month:_selectedStatementMonth];

    CPVendorStatementViewController *vc = [[CPVendorStatementViewController alloc] init];
    vc.vendorUUID = _vendor.uuid;
    vc.statementMonth = _selectedStatementMonth;
    [self.navigationController pushViewController:vc animated:YES];

    (void)statementData; // Used by CPVendorStatementViewController
}

- (void)_handleExportStatement {
    if (!_vendor) {
        [self _showAlert:@"Save Vendor" message:@"Please save the vendor before exporting a statement."];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Export Statement"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:@"Export as CSV"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf _exportStatementWithFormat:CPExportFormatCSV];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Export as PDF"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf _exportStatementWithFormat:CPExportFormatPDF];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0,
                                                                 self.view.bounds.size.height / 2.0,
                                                                 1.0, 1.0);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)_exportStatementWithFormat:(CPExportFormat)format {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comps = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth
                                     fromDate:_selectedStatementMonth ?: [NSDate date]];

    NSDictionary *params = @{
        @"vendorUUID": _vendor.uuid ?: @"",
        @"year": @(comps.year),
        @"month": @(comps.month),
    };

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

    __weak typeof(self) weakSelf = self;
    [[CPExportService sharedService] generateReport:CPReportTypeVendorStatement
                                             format:format
                                         parameters:params
                                         completion:^(NSURL *fileURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf _buildNavigationItems];
            if (error || !fileURL) {
                [weakSelf _showAlert:@"Export Failed"
                             message:error.localizedDescription ?: @"Could not generate export."];
                return;
            }
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                              applicationActivities:nil];
            avc.popoverPresentationController.barButtonItem = weakSelf.navigationItem.rightBarButtonItem;
            [weakSelf presentViewController:avc animated:YES completion:nil];
        });
    }];
}

- (void)_handleSave {
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        [self _showAlert:@"Required Field" message:@"Vendor Name is required."];
        [_nameField becomeFirstResponder];
        return;
    }

    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;

    if (!_vendor) {
        _vendor = [NSEntityDescription insertNewObjectForEntityForName:@"CPVendor"
                                                inManagedObjectContext:ctx];
        _vendor.uuid = [CPIDGenerator generateUUID];
        _vendor.createdAt = [NSDate date];
    }

    _vendor.name = name;
    _vendor.contactName = [_contactNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _vendor.contactEmail = [_contactEmailField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _vendor.contactPhone = [_contactPhoneField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _vendor.address = [_addressField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _vendor.isActive = @(_activeSwitch.on);

    NSError *saveError = nil;
    [ctx save:&saveError];

    if (saveError) {
        [self _showAlert:@"Save Failed" message:saveError.localizedDescription];
        return;
    }

    self.title = _vendor.name;
    self.vendorUUID = _vendor.uuid;

    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)_handleCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - UITextFieldDelegate
// ---------------------------------------------------------------------------

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSInteger nextTag = textField.tag + 1;
    UIView *next = [_tableView viewWithTag:nextTag];
    if ([next isKindOfClass:[UITextField class]]) {
        [next becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

- (void)_showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
