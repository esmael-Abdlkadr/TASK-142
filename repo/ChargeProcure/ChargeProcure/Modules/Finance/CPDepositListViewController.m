#import "CPDepositListViewController.h"
#import "CPDepositService.h"
#import "CPCoreDataStack.h"
#import "CPRBACService.h"
#import "CPAuthService.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
#pragma mark - Cell
// ---------------------------------------------------------------------------

@interface CPDepositCell : UITableViewCell
@property (nonatomic, strong) UILabel *chargerLabel;
@property (nonatomic, strong) UILabel *amountLabel;
@property (nonatomic, strong) UILabel *customerLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *statusBadge;
@end

@implementation CPDepositCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    _chargerLabel = [UILabel new];
    _chargerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _chargerLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.contentView addSubview:_chargerLabel];

    _amountLabel = [UILabel new];
    _amountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _amountLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    _amountLabel.textColor = [UIColor systemGreenColor];
    [self.contentView addSubview:_amountLabel];

    _customerLabel = [UILabel new];
    _customerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _customerLabel.font = [UIFont systemFontOfSize:13];
    _customerLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:_customerLabel];

    _statusBadge = [UILabel new];
    _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _statusBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusBadge.layer.cornerRadius = 6;
    _statusBadge.layer.masksToBounds = YES;
    _statusBadge.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:_statusBadge];

    _dateLabel = [UILabel new];
    _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _dateLabel.font = [UIFont systemFontOfSize:11];
    _dateLabel.textColor = [UIColor tertiaryLabelColor];
    [self.contentView addSubview:_dateLabel];

    const CGFloat p = 12;
    [NSLayoutConstraint activateConstraints:@[
        [_chargerLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:p],
        [_chargerLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [_chargerLabel.trailingAnchor constraintEqualToAnchor:_amountLabel.leadingAnchor constant:-8],

        [_amountLabel.centerYAnchor constraintEqualToAnchor:_chargerLabel.centerYAnchor],
        [_amountLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [_amountLabel.widthAnchor constraintGreaterThanOrEqualToConstant:80],

        [_customerLabel.topAnchor constraintEqualToAnchor:_chargerLabel.bottomAnchor constant:4],
        [_customerLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [_customerLabel.trailingAnchor constraintEqualToAnchor:_statusBadge.leadingAnchor constant:-8],

        [_statusBadge.centerYAnchor constraintEqualToAnchor:_customerLabel.centerYAnchor],
        [_statusBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [_statusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:72],

        [_dateLabel.topAnchor constraintEqualToAnchor:_customerLabel.bottomAnchor constant:4],
        [_dateLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [_dateLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [_dateLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-p],
    ]];
    return self;
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Create Deposit Form VC
// ---------------------------------------------------------------------------

@interface CPDepositCreateViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, copy) void (^onCreated)(void);
@end

@implementation CPDepositCreateViewController {
    UITextField *_chargerField;
    UITextField *_customerField;
    UITextField *_depositField;
    UITextField *_preAuthField;
    UITextField *_notesField;
    UITableView *_formTable;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"New Deposit";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                            target:self action:@selector(_cancel)];
    UIBarButtonItem *save   = [[UIBarButtonItem alloc] initWithTitle:@"Create"
                                                               style:UIBarButtonItemStyleDone
                                                              target:self action:@selector(_submit)];
    self.navigationItem.leftBarButtonItem  = cancel;
    self.navigationItem.rightBarButtonItem = save;

    _chargerField  = [self _field:@"Charger ID (required)" secure:NO];
    _customerField = [self _field:@"Customer Reference" secure:NO];
    _depositField  = [self _field:@"Deposit Amount (e.g. 50.00)" secure:NO];
    _preAuthField  = [self _field:@"Pre-Auth Amount (e.g. 100.00)" secure:NO];
    _notesField    = [self _field:@"Notes" secure:NO];
    _depositField.keyboardType  = UIKeyboardTypeDecimalPad;
    _preAuthField.keyboardType  = UIKeyboardTypeDecimalPad;

    _formTable = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _formTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _formTable.dataSource = (id)self;
    _formTable.delegate   = (id)self;
    [_formTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"fCell"];
    [self.view addSubview:_formTable];
}

- (UITextField *)_field:(NSString *)placeholder secure:(BOOL)secure {
    UITextField *f = [UITextField new];
    f.placeholder = placeholder;
    f.secureTextEntry = secure;
    f.font = [UIFont systemFontOfSize:16];
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.delegate = self;
    return f;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 5; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"fCell" forIndexPath:ip];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    UITextField *fields[] = {_chargerField, _customerField, _depositField, _preAuthField, _notesField};
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
    NSString *charger  = _chargerField.text ?: @"";
    NSString *customer = _customerField.text;
    NSString *notes    = _notesField.text;
    NSDecimalNumber *deposit  = [NSDecimalNumber decimalNumberWithString:_depositField.text ?: @"0"];
    NSDecimalNumber *preAuth  = [NSDecimalNumber decimalNumberWithString:_preAuthField.text ?: @"0"];

    if (charger.length == 0) {
        [self _alert:@"Missing Field" msg:@"Charger ID is required."];
        return;
    }
    if ([deposit isEqualToNumber:[NSDecimalNumber notANumber]] ||
        [preAuth isEqualToNumber:[NSDecimalNumber notANumber]]) {
        [self _alert:@"Invalid Amount" msg:@"Enter valid numeric amounts."];
        return;
    }

    NSError *err = nil;
    NSString *uuid = [[CPDepositService sharedService] createDepositForChargerID:charger
                                                                     customerRef:customer.length ? customer : nil
                                                                   depositAmount:deposit
                                                                   preAuthAmount:preAuth
                                                                           notes:notes.length ? notes : nil
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
#pragma mark - CPDepositListViewController
// ---------------------------------------------------------------------------

@interface CPDepositListViewController () <UITableViewDelegate, UITableViewDataSource,
                                           NSFetchedResultsControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSFetchedResultsController *frc;
@property (nonatomic, strong) NSDateFormatter *df;
@end

@implementation CPDepositListViewController

static NSString * const kDepositCellID = @"CPDepositCell";

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Deposits & Pre-Auths";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // Read-side authorization check — only users who can manage deposits may view them.
    if (![[CPDepositService sharedService] currentUserCanManageDeposits]) {
        UIAlertController *denied = [UIAlertController
            alertControllerWithTitle:@"Access Denied"
            message:@"You do not have permission to view deposits."
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
    _df.timeStyle = NSDateFormatterShortStyle;

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
    [_tableView registerClass:[CPDepositCell class] forCellReuseIdentifier:kDepositCellID];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)_buildNavBar {
    BOOL canManage = [[CPDepositService sharedService] currentUserCanManageDeposits];
    if (canManage) {
        UIBarButtonItem *add = [[UIBarButtonItem alloc]
            initWithImage:[UIImage systemImageNamed:@"plus"]
                    style:UIBarButtonItemStylePlain
                   target:self action:@selector(_addDeposit)];
        self.navigationItem.rightBarButtonItem = add;
    }
}

- (void)_buildFRC {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"DepositTracking"];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"capturedAt" ascending:NO]];
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

- (void)_addDeposit {
    CPDepositCreateViewController *form = [CPDepositCreateViewController new];
    __weak typeof(self) ws = self;
    form.onCreated = ^{ [ws.tableView reloadData]; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:form];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)_showActionsForDeposit:(NSManagedObject *)deposit {
    NSString *status = [deposit valueForKey:@"status"] ?: @"";
    NSString *uuid   = [deposit valueForKey:@"uuid"];
    NSString *charger = [deposit valueForKey:@"chargerID"] ?: @"";

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Deposit – %@", charger]
                         message:[NSString stringWithFormat:@"Status: %@", status]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) ws = self;

    if ([status isEqualToString:CPDepositStatusPending]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Capture"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [ws _transition:@"capture" uuid:uuid];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Mark Failed"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a) {
            [ws _transition:@"fail" uuid:uuid];
        }]];
    }
    if ([status isEqualToString:CPDepositStatusPending] ||
        [status isEqualToString:CPDepositStatusCaptured]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Release"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [ws _transition:@"release" uuid:uuid];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)_transition:(NSString *)action uuid:(NSString *)uuid {
    NSError *err = nil;
    BOOL ok = NO;
    if ([action isEqualToString:@"capture"]) {
        ok = [[CPDepositService sharedService] captureDepositWithUUID:uuid error:&err];
    } else if ([action isEqualToString:@"release"]) {
        ok = [[CPDepositService sharedService] releaseDepositWithUUID:uuid error:&err];
    } else if ([action isEqualToString:@"fail"]) {
        ok = [[CPDepositService sharedService] markDepositFailedWithUUID:uuid error:&err];
    }
    if (!ok) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Action Failed"
                                                                   message:err.localizedDescription ?: @"Unknown error."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return (NSInteger)_frc.sections.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)((id<NSFetchedResultsSectionInfo>)_frc.sections[section]).numberOfObjects;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CPDepositCell *cell = [tv dequeueReusableCellWithIdentifier:kDepositCellID forIndexPath:ip];
    NSManagedObject *dep = [_frc objectAtIndexPath:ip];

    cell.chargerLabel.text  = [NSString stringWithFormat:@"Charger: %@", [dep valueForKey:@"chargerID"] ?: @"—"];
    NSDecimalNumber *amt    = [dep valueForKey:@"depositAmount"];
    cell.amountLabel.text   = amt ? [NSString stringWithFormat:@"$%.2f", amt.doubleValue] : @"$—";
    NSString *cust = [dep valueForKey:@"customerRef"];
    cell.customerLabel.text = cust.length ? cust : @"No customer ref";

    NSDate *date            = [dep valueForKey:@"capturedAt"];
    cell.dateLabel.text     = date ? [_df stringFromDate:date] : @"—";

    NSString *status        = [dep valueForKey:@"status"] ?: @"";
    cell.statusBadge.text   = [NSString stringWithFormat:@" %@ ", status];
    [self _styleStatus:status badge:cell.statusBadge];

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)_styleStatus:(NSString *)status badge:(UILabel *)badge {
    UIColor *color;
    if ([status isEqualToString:CPDepositStatusPending]) {
        color = [UIColor systemOrangeColor];
    } else if ([status isEqualToString:CPDepositStatusCaptured]) {
        color = [UIColor systemBlueColor];
    } else if ([status isEqualToString:CPDepositStatusReleased]) {
        color = [UIColor systemGreenColor];
    } else {
        color = [UIColor systemRedColor];
    }
    badge.textColor = color;
    badge.backgroundColor = [color colorWithAlphaComponent:0.12];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    BOOL canManage = [[CPDepositService sharedService] currentUserCanManageDeposits];
    if (!canManage) return;
    NSManagedObject *dep = [_frc objectAtIndexPath:ip];
    [self _showActionsForDeposit:dep];
}

// ---------------------------------------------------------------------------
#pragma mark - NSFetchedResultsControllerDelegate
// ---------------------------------------------------------------------------

- (void)controllerWillChangeContent:(NSFetchedResultsController *)c {
    [_tableView beginUpdates];
}

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

- (void)controllerDidChangeContent:(NSFetchedResultsController *)c {
    [_tableView endUpdates];
}

@end
