#import "CPCouponPackageListViewController.h"
#import "CPCouponService.h"
#import "CPCoreDataStack.h"
#import "CPAuthService.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
#pragma mark - Cell
// ---------------------------------------------------------------------------

@interface CPCouponCell : UITableViewCell
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *usageLabel;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UILabel *rangeLabel;
@end

@implementation CPCouponCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    _codeLabel = [UILabel new];
    _codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _codeLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.contentView addSubview:_codeLabel];

    _valueLabel = [UILabel new];
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    _valueLabel.textColor = [UIColor systemPurpleColor];
    [self.contentView addSubview:_valueLabel];

    _usageLabel = [UILabel new];
    _usageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usageLabel.font = [UIFont systemFontOfSize:13];
    _usageLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:_usageLabel];

    _statusBadge = [UILabel new];
    _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _statusBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusBadge.layer.cornerRadius = 6;
    _statusBadge.layer.masksToBounds = YES;
    _statusBadge.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:_statusBadge];

    _rangeLabel = [UILabel new];
    _rangeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _rangeLabel.font = [UIFont systemFontOfSize:11];
    _rangeLabel.textColor = [UIColor tertiaryLabelColor];
    [self.contentView addSubview:_rangeLabel];

    const CGFloat p = 12;
    [NSLayoutConstraint activateConstraints:@[
        [_codeLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:p],
        [_codeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [_codeLabel.trailingAnchor constraintEqualToAnchor:_valueLabel.leadingAnchor constant:-8],

        [_valueLabel.centerYAnchor constraintEqualToAnchor:_codeLabel.centerYAnchor],
        [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [_valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70],

        [_usageLabel.topAnchor constraintEqualToAnchor:_codeLabel.bottomAnchor constant:4],
        [_usageLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [_usageLabel.trailingAnchor constraintEqualToAnchor:_statusBadge.leadingAnchor constant:-8],

        [_statusBadge.centerYAnchor constraintEqualToAnchor:_usageLabel.centerYAnchor],
        [_statusBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [_statusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:64],

        [_rangeLabel.topAnchor constraintEqualToAnchor:_usageLabel.bottomAnchor constant:4],
        [_rangeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [_rangeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [_rangeLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-p],
    ]];
    return self;
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Create Coupon Form VC
// ---------------------------------------------------------------------------

@interface CPCouponCreateViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, copy) void (^onCreated)(void);
@end

@implementation CPCouponCreateViewController {
    UITextField *_codeField;
    UITextField *_descField;
    UITextField *_discountValueField;
    UITextField *_minAmountField;
    UITextField *_maxDiscountField;
    UITextField *_maxUsageField;
    UISegmentedControl *_typeSegment;
    UITableView *_formTable;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"New Coupon";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                            target:self action:@selector(_cancel)];
    UIBarButtonItem *save   = [[UIBarButtonItem alloc] initWithTitle:@"Create"
                                                               style:UIBarButtonItemStyleDone
                                                              target:self action:@selector(_submit)];
    self.navigationItem.leftBarButtonItem  = cancel;
    self.navigationItem.rightBarButtonItem = save;

    _codeField         = [self _field:@"Coupon Code (required, e.g. SUMMER20)"];
    _descField         = [self _field:@"Description (optional)"];
    _discountValueField = [self _field:@"Discount Value (e.g. 10 for 10% or $10)"];
    _minAmountField    = [self _field:@"Min Purchase Amount (optional)"];
    _maxDiscountField  = [self _field:@"Max Discount Cap (optional)"];
    _maxUsageField     = [self _field:@"Max Uses (optional, e.g. 100)"];

    _discountValueField.keyboardType = UIKeyboardTypeDecimalPad;
    _minAmountField.keyboardType     = UIKeyboardTypeDecimalPad;
    _maxDiscountField.keyboardType   = UIKeyboardTypeDecimalPad;
    _maxUsageField.keyboardType      = UIKeyboardTypeNumberPad;

    _typeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Percentage", @"Fixed Amount"]];
    _typeSegment.selectedSegmentIndex = 0;

    _formTable = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _formTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _formTable.dataSource = (id)self;
    _formTable.delegate   = (id)self;
    [_formTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cCell"];
    [self.view addSubview:_formTable];
}

- (UITextField *)_field:(NSString *)ph {
    UITextField *f = [UITextField new];
    f.placeholder = ph;
    f.font = [UIFont systemFontOfSize:15];
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.delegate = self;
    return f;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? 1 : 6; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"Discount Type" : @"Details";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cCell" forIndexPath:ip];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    if (ip.section == 0) {
        _typeSegment.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:_typeSegment];
        [NSLayoutConstraint activateConstraints:@[
            [_typeSegment.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [_typeSegment.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [_typeSegment.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [_typeSegment.heightAnchor constraintEqualToConstant:32],
            [cell.contentView.heightAnchor constraintEqualToConstant:52],
        ]];
        return cell;
    }

    UITextField *fields[] = {_codeField, _descField, _discountValueField, _minAmountField, _maxDiscountField, _maxUsageField};
    UITextField *f = fields[ip.row];
    [cell.contentView addSubview:f];
    [NSLayoutConstraint activateConstraints:@[
        [f.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [f.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [f.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [f.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [f.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return cell;
}

- (void)_cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)_submit {
    NSString *code = [_codeField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
    if (code.length == 0) {
        [self _alert:@"Missing Field" msg:@"Coupon code is required."];
        return;
    }

    NSString *discountType = (_typeSegment.selectedSegmentIndex == 0)
        ? CPCouponDiscountTypePercentage : CPCouponDiscountTypeFixed;

    NSDecimalNumber *discountValue = [NSDecimalNumber decimalNumberWithString:_discountValueField.text ?: @"0"];
    if ([discountValue isEqualToNumber:[NSDecimalNumber notANumber]] ||
        [discountValue compare:[NSDecimalNumber zero]] != NSOrderedDescending) {
        [self _alert:@"Invalid Value" msg:@"Discount value must be greater than zero."];
        return;
    }

    NSDecimalNumber *minAmt   = _minAmountField.text.length   ? [NSDecimalNumber decimalNumberWithString:_minAmountField.text]   : nil;
    NSDecimalNumber *maxDisc  = _maxDiscountField.text.length ? [NSDecimalNumber decimalNumberWithString:_maxDiscountField.text] : nil;
    NSNumber        *maxUsage = _maxUsageField.text.length    ? @([_maxUsageField.text integerValue]) : nil;

    NSError *err = nil;
    NSString *uuid = [[CPCouponService sharedService] createCouponWithCode:code
                                                               description:_descField.text.length ? _descField.text : nil
                                                              discountType:discountType
                                                             discountValue:discountValue
                                                                 minAmount:minAmt
                                                               maxDiscount:maxDisc
                                                                  maxUsage:maxUsage
                                                            effectiveStart:nil
                                                              effectiveEnd:nil
                                                                     error:&err];
    if (!uuid) {
        [self _alert:@"Create Failed" msg:err.localizedDescription ?: @"Unknown error."];
        return;
    }
    __weak typeof(self) ws = self;
    [self dismissViewControllerAnimated:YES completion:^{
        if (ws.onCreated) ws.onCreated();
    }];
}

- (void)_alert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - CPCouponPackageListViewController
// ---------------------------------------------------------------------------

@interface CPCouponPackageListViewController () <UITableViewDelegate, UITableViewDataSource,
                                                  NSFetchedResultsControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSFetchedResultsController *frc;
@property (nonatomic, strong) NSDateFormatter *df;
@end

@implementation CPCouponPackageListViewController

static NSString * const kCouponCellID = @"CPCouponCell";

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Coupon Packages";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // Read-side authorization check — only admins may view coupon packages.
    if (![[CPCouponService sharedService] currentUserCanManageCoupons]) {
        UIAlertController *denied = [UIAlertController
            alertControllerWithTitle:@"Access Denied"
            message:@"You do not have permission to view coupon packages."
            preferredStyle:UIAlertControllerStyleAlert];
        [denied addAction:[UIAlertAction actionWithTitle:@"OK"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:denied animated:YES completion:nil];
        });
        return;
    }

    _df = [NSDateFormatter new];
    _df.dateStyle = NSDateFormatterShortStyle;
    _df.timeStyle = NSDateFormatterNoStyle;

    [self _buildTable];
    [self _buildNavBar];
    [self _buildFRC];
}

// ---------------------------------------------------------------------------
#pragma mark - Setup
// ---------------------------------------------------------------------------

- (void)_buildTable {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate   = self;
    _tableView.dataSource = self;
    _tableView.rowHeight  = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 80;
    [_tableView registerClass:[CPCouponCell class] forCellReuseIdentifier:kCouponCellID];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)_buildNavBar {
    BOOL isAdmin = [[CPAuthService sharedService].currentUserRole isEqualToString:@"Administrator"];
    if (isAdmin) {
        UIBarButtonItem *add = [[UIBarButtonItem alloc]
            initWithImage:[UIImage systemImageNamed:@"plus"]
                    style:UIBarButtonItemStylePlain
                   target:self action:@selector(_addCoupon)];
        self.navigationItem.rightBarButtonItem = add;
    }
}

- (void)_buildFRC {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"code" ascending:YES]];
    req.fetchBatchSize = 50;
    _frc = [[NSFetchedResultsController alloc] initWithFetchRequest:req
                                               managedObjectContext:ctx
                                                 sectionNameKeyPath:nil
                                                          cacheName:nil];
    _frc.delegate = self;
    NSError *err = nil;
    [_frc performFetch:&err];
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)_addCoupon {
    CPCouponCreateViewController *form = [CPCouponCreateViewController new];
    __weak typeof(self) ws = self;
    form.onCreated = ^{ [ws.tableView reloadData]; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:form];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)_showActionsForCoupon:(NSManagedObject *)coupon {
    NSString *code = [coupon valueForKey:@"code"] ?: @"";
    NSString *uuid = [coupon valueForKey:@"uuid"];
    BOOL isActive  = [[coupon valueForKey:@"isActive"] boolValue];

    NSString *toggleTitle = isActive ? @"Deactivate" : @"Activate";
    UIAlertActionStyle toggleStyle = isActive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault;

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Coupon: %@", code]
                         message:isActive ? @"Active" : @"Inactive"
                  preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) ws = self;
    [sheet addAction:[UIAlertAction actionWithTitle:toggleTitle style:toggleStyle handler:^(UIAlertAction *a) {
        NSError *err = nil;
        BOOL ok;
        if (isActive) {
            ok = [[CPCouponService sharedService] deactivateCouponWithUUID:uuid error:&err];
        } else {
            ok = [[CPCouponService sharedService] activateCouponWithUUID:uuid error:&err];
        }
        if (!ok) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Action Failed"
                                                                           message:err.localizedDescription ?: @"Unknown error."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [ws presentViewController:alert animated:YES completion:nil];
        }
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return (NSInteger)_frc.sections.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)((id<NSFetchedResultsSectionInfo>)_frc.sections[s]).numberOfObjects;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CPCouponCell *cell = [tv dequeueReusableCellWithIdentifier:kCouponCellID forIndexPath:ip];
    NSManagedObject *c = [_frc objectAtIndexPath:ip];

    cell.codeLabel.text = [c valueForKey:@"code"] ?: @"—";

    NSString *dType    = [c valueForKey:@"discountType"] ?: @"";
    NSDecimalNumber *dVal = [c valueForKey:@"discountValue"];
    if ([dType isEqualToString:CPCouponDiscountTypePercentage]) {
        cell.valueLabel.text = dVal ? [NSString stringWithFormat:@"%.0f%%", dVal.doubleValue] : @"—";
    } else {
        cell.valueLabel.text = dVal ? [NSString stringWithFormat:@"$%.2f", dVal.doubleValue] : @"—";
    }

    NSNumber *usageCount = [c valueForKey:@"usageCount"];
    NSNumber *maxUsage   = [c valueForKey:@"maxUsage"];
    if (maxUsage) {
        cell.usageLabel.text = [NSString stringWithFormat:@"Used %@/%@",
                                usageCount ?: @0, maxUsage];
    } else {
        cell.usageLabel.text = [NSString stringWithFormat:@"Used %@× (unlimited)", usageCount ?: @0];
    }

    BOOL isActive = [[c valueForKey:@"isActive"] boolValue];
    // Also check date validity
    NSDate *now = [NSDate date];
    NSDate *start = [c valueForKey:@"effectiveStart"];
    NSDate *end   = [c valueForKey:@"effectiveEnd"];
    BOOL dateOk = (!start || [now compare:start] != NSOrderedAscending) &&
                  (!end   || [now compare:end]   != NSOrderedDescending);
    BOOL valid = isActive && dateOk;

    cell.statusBadge.text = valid ? @" Active " : (isActive ? @" Scheduled " : @" Inactive ");
    if (valid) {
        cell.statusBadge.textColor = [UIColor systemGreenColor];
        cell.statusBadge.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.12];
    } else if (isActive) {
        cell.statusBadge.textColor = [UIColor systemOrangeColor];
        cell.statusBadge.backgroundColor = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.12];
    } else {
        cell.statusBadge.textColor = [UIColor systemGrayColor];
        cell.statusBadge.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.12];
    }

    NSString *startStr = start ? [_df stringFromDate:start] : @"now";
    NSString *endStr   = end   ? [_df stringFromDate:end]   : @"∞";
    cell.rangeLabel.text = [NSString stringWithFormat:@"Valid: %@ – %@", startStr, endStr];

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.contentView.alpha = isActive ? 1.0 : 0.55;
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    BOOL isAdmin = [[CPAuthService sharedService].currentUserRole isEqualToString:@"Administrator"];
    if (!isAdmin) return;
    NSManagedObject *c = [_frc objectAtIndexPath:ip];
    [self _showActionsForCoupon:c];
}

// ---------------------------------------------------------------------------
#pragma mark - NSFetchedResultsControllerDelegate
// ---------------------------------------------------------------------------

- (void)controllerWillChangeContent:(NSFetchedResultsController *)c { [_tableView beginUpdates]; }

- (void)controller:(NSFetchedResultsController *)c
   didChangeObject:(id)obj
       atIndexPath:(NSIndexPath *)ip
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)nip {
    switch (type) {
        case NSFetchedResultsChangeInsert: [_tableView insertRowsAtIndexPaths:@[nip] withRowAnimation:UITableViewRowAnimationFade]; break;
        case NSFetchedResultsChangeDelete: [_tableView deleteRowsAtIndexPaths:@[ip]  withRowAnimation:UITableViewRowAnimationFade]; break;
        case NSFetchedResultsChangeUpdate: [_tableView reloadRowsAtIndexPaths:@[ip]  withRowAnimation:UITableViewRowAnimationNone]; break;
        case NSFetchedResultsChangeMove:   [_tableView moveRowAtIndexPath:ip toIndexPath:nip]; break;
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)c { [_tableView endUpdates]; }

@end
