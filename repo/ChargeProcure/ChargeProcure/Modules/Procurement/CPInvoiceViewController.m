// CPInvoiceViewController.m
// ChargeProcure
//
// Invoice detail view: header, variance section, line items, write-off
// (finance approver only, max $250), payment status, attachments, and share.

#import "CPInvoiceViewController.h"
#import "CPRBACService.h"
#import "CPAuditService.h"
#import "CPAuthService.h"
#import "CPProcurementService.h"
#import "CPAttachmentService.h"
#import "CPCoreDataStack.h"
#import "CPNumberFormatter.h"
#import "CPDateFormatter.h"
#import <CoreData/CoreData.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuickLook/QuickLook.h>

// ---------------------------------------------------------------------------
// MARK: - Section layout
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, CPInvoiceSection) {
    CPInvoiceSectionHeader      = 0,
    CPInvoiceSectionVariance    = 1,
    CPInvoiceSectionLineItems   = 2,
    CPInvoiceSectionWriteOff    = 3,
    CPInvoiceSectionPayment     = 4,
    CPInvoiceSectionAttachments = 5,
    CPInvoiceSectionCount       = 6,
};

// ---------------------------------------------------------------------------
// MARK: - Write-off limits
// ---------------------------------------------------------------------------

static CGFloat const kWriteOffMaxAmount     = 250.0;  // cumulative cap in USD

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface CPInvoiceViewController () <UITableViewDelegate, UITableViewDataSource,
                                        UIDocumentPickerDelegate,
                                        QLPreviewControllerDataSource,
                                        QLPreviewControllerDelegate>

@property (nonatomic, strong) UITableView   *tableView;

// Invoice data loaded from Core Data (NSManagedObject keyed approach)
// since Invoice may not have a typed class generated yet; we store in
// an NSMutableDictionary loaded from Core Data metadata or synthesised.
@property (nonatomic, strong) NSManagedObject *invoice;     // nullable — may not exist in Core Data
@property (nonatomic, strong) NSMutableDictionary *invoiceData;  // in-memory working copy

// Cached permissions
@property (nonatomic, assign) BOOL isFinanceApprover;
@property (nonatomic, assign) BOOL canViewInvoice;

// Write-off UI (reused across table reload)
@property (nonatomic, strong) UITextField *writeOffAmountField;
@property (nonatomic, strong) UITextField *writeOffReasonField;

// QLPreviewController data source backing URL
@property (nonatomic, strong) NSURL *previewURL;

@end

// ---------------------------------------------------------------------------
// MARK: - Implementation
// ---------------------------------------------------------------------------

@implementation CPInvoiceViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self checkPermissions];

    // Read-side authorization check — do NOT fetch or render invoice data
    // if the current user lacks read permission on invoices.
    if (!self.canViewInvoice) {
        self.title = @"Invoice";
        UIAlertController *denied = [UIAlertController
            alertControllerWithTitle:@"Access Denied"
            message:@"You do not have permission to view invoices."
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

    [self loadInvoice];
    [self buildTableView];
    [self buildNavButtons];
}

// ---------------------------------------------------------------------------
#pragma mark - Permissions
// ---------------------------------------------------------------------------

- (void)checkPermissions {
    CPRBACService *rbac = [CPRBACService sharedService];
    self.isFinanceApprover = [rbac currentUserCanPerform:CPActionApprove onResource:CPResourceWriteOff];
    self.canViewInvoice    = [rbac currentUserCanPerform:CPActionRead    onResource:CPResourceInvoice];
}

// ---------------------------------------------------------------------------
#pragma mark - Data Loading
// ---------------------------------------------------------------------------

- (void)loadInvoice {
    // Require a valid invoiceUUID. All finance state lives in Core Data.
    if (!self.invoiceUUID) {
        self.invoiceData = [@{
            @"invoiceNumber":       @"—",
            @"vendorInvoiceNumber": @"",
            @"amount":              [NSDecimalNumber zero],
            @"poAmount":            [NSDecimalNumber zero],
            @"dueDate":             [NSDate date],
            @"status":              @"No Invoice",
            @"lineItems":           @[],
            @"writeOffs":           @[],
            @"attachments":         @[],
        } mutableCopy];
        self.title = @"Invoice";
        return;
    }

    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", self.invoiceUUID];
    req.fetchLimit = 1;

    NSError *err = nil;
    NSArray *results = [ctx executeFetchRequest:req error:&err];
    if (err) {
        NSLog(@"[CPInvoiceVC] Failed to fetch Invoice entity: %@. Using in-memory data.", err.localizedDescription);
    }

    self.invoice = results.firstObject;

    if (self.invoice) {
        [self loadInvoiceDataFromManagedObject];
    } else {
        // Invoice entity does not exist yet. Show empty state — mutations require
        // a persisted Core Data entity created via CPProcurementService.
        self.invoiceData = [@{
            @"invoiceNumber":       @"—",
            @"vendorInvoiceNumber": @"",
            @"amount":              [NSDecimalNumber zero],
            @"poAmount":            [NSDecimalNumber zero],
            @"dueDate":             [NSDate date],
            @"status":              @"Pending",
            @"lineItems":           @[],
            @"writeOffs":           @[],
            @"attachments":         @[],
        } mutableCopy];
    }

    self.title = [NSString stringWithFormat:@"Invoice %@", self.invoiceData[@"invoiceNumber"] ?: @""];
}

- (void)loadInvoiceDataFromManagedObject {
    NSManagedObject *inv = self.invoice;
    NSString *invUUID = [inv valueForKey:@"uuid"];
    NSString *caseID  = [inv valueForKey:@"caseID"];

    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSMutableArray *lineItems = [NSMutableArray array];
    __block NSMutableArray *writeOffs = [NSMutableArray array];
    __block NSDecimalNumber *poAmount = [NSDecimalNumber zero];

    [ctx performBlockAndWait:^{
        // Fetch InvoiceLineItem entities for this invoice
        NSFetchRequest *liReq = [NSFetchRequest fetchRequestWithEntityName:@"InvoiceLineItem"];
        liReq.predicate = [NSPredicate predicateWithFormat:@"invoiceID == %@", invUUID];
        NSArray *liItems = [ctx executeFetchRequest:liReq error:nil] ?: @[];
        for (NSManagedObject *li in liItems) {
            NSDecimalNumber *totalPrice = [li valueForKey:@"totalPrice"] ?: [NSDecimalNumber zero];
            [lineItems addObject:@{
                @"description": [li valueForKey:@"description"] ?: @"—",
                @"qty":         [li valueForKey:@"quantity"]     ?: @1,
                @"total":       totalPrice.stringValue,
            }];
        }

        // Fetch WriteOff entities for this invoice
        NSFetchRequest *woReq = [NSFetchRequest fetchRequestWithEntityName:@"WriteOff"];
        woReq.predicate = [NSPredicate predicateWithFormat:@"invoiceID == %@", invUUID];
        NSArray *wos = [ctx executeFetchRequest:woReq error:nil] ?: @[];
        for (NSManagedObject *wo in wos) {
            NSDecimalNumber *amt = [wo valueForKey:@"amount"] ?: [NSDecimalNumber zero];
            [writeOffs addObject:@{
                @"amount": amt.stringValue,
                @"reason": [wo valueForKey:@"reason"] ?: @"",
            }];
        }

        // Fetch PurchaseOrder to derive poAmount for variance display
        if (caseID.length > 0) {
            NSFetchRequest *poReq = [NSFetchRequest fetchRequestWithEntityName:@"PurchaseOrder"];
            poReq.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", caseID];
            poReq.fetchLimit = 1;
            NSArray *pos = [ctx executeFetchRequest:poReq error:nil];
            poAmount = [pos.firstObject valueForKey:@"totalAmount"] ?: [NSDecimalNumber zero];
        }
    }];

    // Attachments from CPAttachmentService (Core Data + file sandbox)
    NSArray *attEntities = [[CPAttachmentService sharedService]
                            fetchAttachmentsForOwnerID:invUUID ownerType:@"Invoice"];
    NSMutableArray *attachmentData = [NSMutableArray array];
    for (NSManagedObject *att in attEntities) {
        [attachmentData addObject:@{
            @"name": [att valueForKey:@"filename"] ?: @"Attachment",
            @"type": @"PDF",
            @"uuid": [att valueForKey:@"uuid"]     ?: @"",
        }];
    }

    // Use totalAmount (the correct Invoice entity attribute, not "amount")
    self.invoiceData = [@{
        @"invoiceNumber":       [inv valueForKey:@"invoiceNumber"]       ?: @"INV-—",
        @"vendorInvoiceNumber": [inv valueForKey:@"vendorInvoiceNumber"] ?: @"",
        @"amount":              [inv valueForKey:@"totalAmount"]         ?: [NSDecimalNumber zero],
        @"poAmount":            poAmount,
        @"dueDate":             [inv valueForKey:@"dueDate"]             ?: [NSDate date],
        @"status":              [inv valueForKey:@"status"]              ?: @"Pending",
        @"lineItems":           [lineItems copy],
        @"writeOffs":           [writeOffs copy],
        @"attachments":         [attachmentData copy],
    } mutableCopy];
}

// loadOrCreateInvoiceFromUserDefaults and persistInvoiceToUserDefaults removed:
// all invoice state is persisted exclusively through Core Data via CPProcurementService.

// ---------------------------------------------------------------------------
#pragma mark - UI Construction
// ---------------------------------------------------------------------------

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 56;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildNavButtons {
    UIBarButtonItem *share = [[UIBarButtonItem alloc]
                              initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                              target:self
                              action:@selector(shareTapped)];
    share.accessibilityLabel = @"Share or export invoice";
    self.navigationItem.rightBarButtonItem = share;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CPInvoiceSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case CPInvoiceSectionHeader:      return nil;
        case CPInvoiceSectionVariance:    return @"Variance";
        case CPInvoiceSectionLineItems:   return @"Line Items";
        case CPInvoiceSectionWriteOff:    return self.isFinanceApprover ? @"Write-Off" : nil;
        case CPInvoiceSectionPayment:     return @"Payment";
        case CPInvoiceSectionAttachments: return @"Attachments";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CPInvoiceSectionHeader:    return 4; // inv#, vendor inv#, amount, due date
        case CPInvoiceSectionVariance:  return 2; // variance amount, percentage
        case CPInvoiceSectionLineItems: return MAX((NSInteger)((NSArray *)self.invoiceData[@"lineItems"]).count, 1);
        case CPInvoiceSectionWriteOff:  return self.isFinanceApprover ? 4 : 0; // cumul, remaining, fields, button
        case CPInvoiceSectionPayment:   return 2; // status + mark paid
        case CPInvoiceSectionAttachments: return (NSInteger)((NSArray *)self.invoiceData[@"attachments"]).count + 1;
        default: return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == CPInvoiceSectionWriteOff && !self.isFinanceApprover) return 0.01;
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

// ---------------------------------------------------------------------------
#pragma mark - Cell Dispatch
// ---------------------------------------------------------------------------

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case CPInvoiceSectionHeader:      return [self headerCellAtRow:indexPath.row];
        case CPInvoiceSectionVariance:    return [self varianceCellAtRow:indexPath.row];
        case CPInvoiceSectionLineItems:   return [self lineItemCellAtRow:indexPath.row];
        case CPInvoiceSectionWriteOff:    return [self writeOffCellAtRow:indexPath.row];
        case CPInvoiceSectionPayment:     return [self paymentCellAtRow:indexPath.row];
        case CPInvoiceSectionAttachments: return [self attachmentCellAtRow:indexPath.row];
        default: return [UITableViewCell new];
    }
}

// ---- Header cells ----

- (UITableViewCell *)headerCellAtRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    switch (row) {
        case 0:
            cell.textLabel.text = @"Invoice #";
            cell.detailTextLabel.text = self.invoiceData[@"invoiceNumber"] ?: @"—";
            cell.accessibilityLabel = [NSString stringWithFormat:@"Invoice number: %@",
                                       self.invoiceData[@"invoiceNumber"] ?: @"unknown"];
            break;
        case 1:
            cell.textLabel.text = @"Vendor Inv #";
            cell.detailTextLabel.text = self.invoiceData[@"vendorInvoiceNumber"] ?: @"—";
            break;
        case 2: {
            id amount = self.invoiceData[@"amount"];
            NSDecimalNumber *amt = [amount isKindOfClass:[NSDecimalNumber class]]
                ? amount
                : [NSDecimalNumber decimalNumberWithString:[amount description]];
            cell.textLabel.text = @"Amount";
            cell.detailTextLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:amt];
            cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
            break;
        }
        case 3: {
            cell.textLabel.text = @"Due Date";
            id dueDate = self.invoiceData[@"dueDate"];
            if ([dueDate isKindOfClass:[NSDate class]]) {
                cell.detailTextLabel.text = [[CPDateFormatter sharedFormatter] displayDateStringFromDate:dueDate];
            } else if ([dueDate isKindOfClass:[NSString class]]) {
                NSDate *d = [[CPDateFormatter sharedFormatter] dateFromISO8601String:dueDate];
                cell.detailTextLabel.text = d ? [[CPDateFormatter sharedFormatter] displayDateStringFromDate:d] : dueDate;
            } else {
                cell.detailTextLabel.text = @"—";
            }
            break;
        }
    }
    return cell;
}

// ---- Variance cells ----

- (UITableViewCell *)varianceCellAtRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    NSDecimalNumber *invoiceAmt = [self decimalFromData:self.invoiceData[@"amount"]];
    NSDecimalNumber *poAmt      = [self decimalFromData:self.invoiceData[@"poAmount"]];
    NSDecimalNumber *variance   = [invoiceAmt decimalNumberBySubtracting:poAmt];
    double varianceDouble = variance.doubleValue;
    double poDouble = poAmt.doubleValue > 0 ? poAmt.doubleValue : 1.0;
    double variancePct = (varianceDouble / poDouble) * 100.0;

    BOOL flagged = fabs(varianceDouble) > 25.0 || fabs(variancePct) > 2.0;

    switch (row) {
        case 0:
            cell.textLabel.text = @"Variance Amount";
            cell.detailTextLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:variance];
            if (flagged) {
                cell.detailTextLabel.textColor = UIColor.systemRedColor;
                cell.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.05];
            }
            cell.accessibilityLabel = [NSString stringWithFormat:@"Variance amount: %@%@",
                                       [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:variance],
                                       flagged ? @", flagged" : @""];
            break;
        case 1:
            cell.textLabel.text = @"Variance %";
            cell.detailTextLabel.text = [[CPNumberFormatter sharedFormatter] percentageStringFromDouble:variancePct];
            if (flagged) {
                cell.detailTextLabel.textColor = UIColor.systemRedColor;
                cell.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.05];
                // Red highlight badge
                UIImageView *flag = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
                flag.tintColor = UIColor.systemRedColor;
                flag.frame = CGRectMake(0, 0, 20, 20);
                cell.accessoryView = flag;
            }
            cell.accessibilityLabel = [NSString stringWithFormat:@"Variance percentage: %@%@",
                                       [[CPNumberFormatter sharedFormatter] percentageStringFromDouble:variancePct],
                                       flagged ? @", flagged" : @""];
            break;
    }
    return cell;
}

// ---- Line item cells ----

- (UITableViewCell *)lineItemCellAtRow:(NSInteger)row {
    NSArray *items = self.invoiceData[@"lineItems"] ?: @[];
    if (items.count == 0) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.textLabel.text = @"No line items";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    NSDictionary *item = items[row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    NSString *desc  = item[@"description"] ?: @"—";
    NSNumber *qty   = item[@"qty"];
    NSString *total = item[@"total"] ?: @"0.00";
    cell.textLabel.text = qty ? [NSString stringWithFormat:@"%@ (×%@)", desc, qty] : desc;

    NSDecimalNumber *totalNum = [NSDecimalNumber decimalNumberWithString:total];
    cell.detailTextLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:totalNum];
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, quantity %@, total %@",
                               desc, qty ?: @"1", cell.detailTextLabel.text];
    return cell;
}

// ---- Write-off cells ----

- (UITableViewCell *)writeOffCellAtRow:(NSInteger)row {
    switch (row) {
        case 0: return [self writeOffCumulativeCell];
        case 1: return [self writeOffRemainingCell];
        case 2: return [self writeOffInputCell];
        case 3: return [self writeOffApproveCell];
        default: return [UITableViewCell new];
    }
}

- (UITableViewCell *)writeOffCumulativeCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = @"Total Written Off";
    NSDecimalNumber *cumulativeWriteOff = [self cumulativeWriteOffAmount];
    cell.detailTextLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:cumulativeWriteOff];
    return cell;
}

- (UITableViewCell *)writeOffRemainingCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = @"Remaining Available";
    NSDecimalNumber *used = [self cumulativeWriteOffAmount];
    NSDecimalNumber *cap  = [NSDecimalNumber decimalNumberWithString:@"250.00"];
    NSDecimalNumber *remaining = [cap decimalNumberBySubtracting:used];
    if (remaining.doubleValue < 0) remaining = [NSDecimalNumber zero];
    cell.detailTextLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:remaining];

    BOOL atLimit = remaining.doubleValue <= 0;
    cell.detailTextLabel.textColor = atLimit ? UIColor.systemRedColor : UIColor.systemGreenColor;
    cell.accessibilityLabel = [NSString stringWithFormat:@"Remaining write-off available: %@%@",
                               [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:remaining],
                               atLimit ? @", limit reached" : @""];
    return cell;
}

- (UITableViewCell *)writeOffInputCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (!_writeOffAmountField) {
        _writeOffAmountField = [UITextField new];
        _writeOffAmountField.placeholder = @"Amount (max $250 cumulative)";
        _writeOffAmountField.keyboardType = UIKeyboardTypeDecimalPad;
        _writeOffAmountField.borderStyle = UITextBorderStyleRoundedRect;
        _writeOffAmountField.accessibilityLabel = @"Write-off amount";
    }
    if (!_writeOffReasonField) {
        _writeOffReasonField = [UITextField new];
        _writeOffReasonField.placeholder = @"Reason";
        _writeOffReasonField.borderStyle = UITextBorderStyleRoundedRect;
        _writeOffReasonField.accessibilityLabel = @"Write-off reason";
    }

    _writeOffAmountField.translatesAutoresizingMaskIntoConstraints = NO;
    _writeOffReasonField.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_writeOffAmountField, _writeOffReasonField]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
    ]];
    return cell;
}

- (UITableViewCell *)writeOffApproveCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    NSDecimalNumber *used = [self cumulativeWriteOffAmount];
    NSDecimalNumber *cap  = [NSDecimalNumber decimalNumberWithString:@"250.00"];
    BOOL atLimit = used.doubleValue >= kWriteOffMaxAmount;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"Approve Write-Off" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = atLimit ? UIColor.systemGrayColor : UIColor.systemBlueColor;
    button.layer.cornerRadius = 8;
    button.enabled = !atLimit;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = @"Approve write-off";
    button.accessibilityHint  = atLimit ? @"Write-off limit of $250 has been reached" : @"Approve and record the write-off";
    [button addTarget:self action:@selector(approveWriteOffTapped) forControlEvents:UIControlEventTouchUpInside];

    [cell.contentView addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [button.heightAnchor constraintEqualToConstant:44],
    ]];
    return cell;
}

// ---- Payment cells ----

- (UITableViewCell *)paymentCellAtRow:(NSInteger)row {
    if (row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"Payment Status";
        NSString *status = self.invoiceData[@"status"] ?: @"Pending";
        cell.detailTextLabel.text = status;
        BOOL paid = [status isEqualToString:@"Paid"];
        cell.detailTextLabel.textColor = paid ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
        cell.accessibilityLabel = [NSString stringWithFormat:@"Payment status: %@", status];
        return cell;
    }
    // Mark paid button
    NSString *status = self.invoiceData[@"status"] ?: @"Pending";
    BOOL alreadyPaid = [status isEqualToString:@"Paid"];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:alreadyPaid ? @"Payment Recorded" : @"Mark as Paid" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = alreadyPaid ? UIColor.systemGrayColor : UIColor.systemGreenColor;
    button.layer.cornerRadius = 8;
    button.enabled = !alreadyPaid;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = @"Mark invoice as paid";
    [button addTarget:self action:@selector(markPaidTapped) forControlEvents:UIControlEventTouchUpInside];

    [cell.contentView addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [button.heightAnchor constraintEqualToConstant:44],
    ]];
    return cell;
}

// ---- Attachment cells ----

- (UITableViewCell *)attachmentCellAtRow:(NSInteger)row {
    NSArray *attachments = self.invoiceData[@"attachments"] ?: @[];
    if (row < (NSInteger)attachments.count) {
        NSDictionary *att = attachments[row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = att[@"name"] ?: @"Attachment";
        cell.detailTextLabel.text = att[@"type"] ?: @"PDF";
        cell.imageView.image = [UIImage systemImageNamed:@"paperclip"];
        cell.imageView.tintColor = UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityLabel = [NSString stringWithFormat:@"Attachment: %@", att[@"name"] ?: @""];
        return cell;
    }

    // Add attachment button
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"Attach PDF Invoice" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = UIColor.systemBlueColor;
    button.layer.cornerRadius = 8;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = @"Attach a PDF invoice document";
    [button addTarget:self action:@selector(attachPDFTapped) forControlEvents:UIControlEventTouchUpInside];

    [cell.contentView addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [button.heightAnchor constraintEqualToConstant:44],
    ]];
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == CPInvoiceSectionAttachments) {
        NSArray *attachments = self.invoiceData[@"attachments"] ?: @[];
        if (indexPath.row < (NSInteger)attachments.count) {
            [self viewAttachmentAtIndex:indexPath.row];
        }
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)approveWriteOffTapped {
    NSString *amountStr = _writeOffAmountField.text;
    NSString *reason    = _writeOffReasonField.text;

    if (!amountStr.length || !reason.length) {
        [self showAlert:@"Missing Information" message:@"Please enter both an amount and a reason."];
        return;
    }

    double enteredAmount = amountStr.doubleValue;
    if (enteredAmount <= 0) {
        [self showAlert:@"Invalid Amount" message:@"Please enter a positive write-off amount."];
        return;
    }

    NSDecimalNumber *used      = [self cumulativeWriteOffAmount];
    double remainingAllowance  = kWriteOffMaxAmount - used.doubleValue;

    if (enteredAmount > remainingAllowance) {
        NSString *msg = [NSString stringWithFormat:
                         @"This write-off would exceed the $%.2f cumulative limit. You have $%.2f remaining.",
                         kWriteOffMaxAmount, remainingAllowance];
        [self showAlert:@"Exceeds Write-Off Limit" message:msg];
        return;
    }

    if (!self.invoiceUUID) {
        [self showAlert:@"No Invoice" message:@"Invoice must be saved to Core Data before applying a write-off."];
        return;
    }

    NSDecimalNumber *amount      = [NSDecimalNumber decimalNumberWithString:amountStr];
    NSString *approverUUID       = [CPAuthService sharedService].currentUserID;
    NSError *err                 = nil;
    BOOL success                 = [[CPProcurementService sharedService]
                                    createWriteOffForInvoice:self.invoiceUUID
                                    amount:amount
                                    reason:reason
                                    approverUUID:approverUUID ?: @""
                                    error:&err];

    if (success) {
        // Reload invoice data from Core Data to reflect updated write-off total
        [self loadInvoice];
        _writeOffAmountField.text = @"";
        _writeOffReasonField.text = @"";
        [_writeOffAmountField resignFirstResponder];
        [_writeOffReasonField resignFirstResponder];

        UINotificationFeedbackGenerator *f = [UINotificationFeedbackGenerator new];
        [f notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:CPInvoiceSectionWriteOff]
                      withRowAnimation:UITableViewRowAnimationNone];
    } else {
        [self showAlert:@"Write-Off Failed" message:err.localizedDescription ?: @"Could not apply write-off."];
    }
}

- (void)markPaidTapped {
    if (!self.invoiceUUID) {
        [self showAlert:@"No Invoice" message:@"Invoice must be saved to Core Data before recording payment."];
        return;
    }

    // Derive payment amount from the loaded invoice data
    NSDecimalNumber *amount = [self decimalFromData:self.invoiceData[@"amount"]];
    if (!amount || [amount compare:[NSDecimalNumber zero]] != NSOrderedDescending) {
        [self showAlert:@"Invalid Amount" message:@"Invoice amount must be greater than zero."];
        return;
    }

    NSError *err           = nil;
    NSString *paymentUUID  = [[CPProcurementService sharedService]
                               createPaymentForInvoice:self.invoiceUUID
                               amount:amount
                               method:@"ACH"
                               notes:nil
                               error:&err];

    if (paymentUUID) {
        [self loadInvoice];
        UINotificationFeedbackGenerator *f = [UINotificationFeedbackGenerator new];
        [f notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:CPInvoiceSectionPayment]
                      withRowAnimation:UITableViewRowAnimationNone];
    } else {
        [self showAlert:@"Payment Failed" message:err.localizedDescription ?: @"Could not record payment."];
    }
}

- (void)attachPDFTapped {
    if (@available(iOS 14.0, *)) {
        UTType *pdfType = UTTypePDF;
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[pdfType]];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.adobe.pdf"]
                                                                   inMode:UIDocumentPickerModeImport];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)viewAttachmentAtIndex:(NSInteger)index {
    NSDictionary *att = ((NSArray *)self.invoiceData[@"attachments"])[index];
    NSString *attachmentUUID = att[@"uuid"];
    NSString *fileName       = att[@"name"] ?: @"Attachment";

    if (!attachmentUUID.length) {
        [self showAlert:fileName message:@"No file is associated with this attachment."];
        return;
    }

    // Load the binary data from the attachment store.
    NSError *loadError = nil;
    NSData *fileData = [[CPAttachmentService sharedService]
                        loadAttachmentWithUUID:attachmentUUID error:&loadError];
    if (!fileData) {
        [self showAlert:@"Preview Unavailable"
                message:loadError.localizedDescription ?: @"The attachment file could not be loaded."];
        return;
    }

    // Write to a temp file so QLPreviewController can display it.
    NSString *tmpDir = NSTemporaryDirectory();
    NSURL *tmpURL = [NSURL fileURLWithPath:
                     [tmpDir stringByAppendingPathComponent:fileName]];
    NSError *writeError = nil;
    if (![fileData writeToURL:tmpURL options:NSDataWritingAtomic error:&writeError]) {
        [self showAlert:@"Preview Unavailable"
                message:writeError.localizedDescription ?: @"Could not write preview file."];
        return;
    }

    self.previewURL = tmpURL;
    QLPreviewController *ql = [[QLPreviewController alloc] init];
    ql.dataSource = self;
    ql.delegate   = self;
    [self presentViewController:ql animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - QLPreviewControllerDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.previewURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller
                    previewItemAtIndex:(NSInteger)index {
    return self.previewURL;
}

// ---------------------------------------------------------------------------
#pragma mark - QLPreviewControllerDelegate
// ---------------------------------------------------------------------------

- (void)previewControllerDidDismiss:(QLPreviewController *)controller {
    // Clean up the temp file after the user dismisses the preview.
    if (self.previewURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.previewURL error:nil];
        self.previewURL = nil;
    }
}

- (void)shareTapped {
    NSDecimalNumber *amount = [self decimalFromData:self.invoiceData[@"amount"]];
    NSString *summary = [NSString stringWithFormat:
                         @"Invoice %@\nVendor Inv: %@\nAmount: %@\nStatus: %@",
                         self.invoiceData[@"invoiceNumber"] ?: @"",
                         self.invoiceData[@"vendorInvoiceNumber"] ?: @"",
                         [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:amount],
                         self.invoiceData[@"status"] ?: @"Pending"];
    UIActivityViewController *vc = [[UIActivityViewController alloc]
                                    initWithActivityItems:@[summary]
                                    applicationActivities:nil];
    [self presentViewController:vc animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - UIDocumentPickerDelegate
// ---------------------------------------------------------------------------

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!self.invoiceUUID) {
        [self showAlert:@"No Invoice"
                message:@"Invoice must be saved to Core Data before adding attachments."];
        return;
    }
    for (NSURL *url in urls) {
        NSString *name = url.lastPathComponent ?: @"invoice.pdf";
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (!data) {
            [self showAlert:@"File Error"
                    message:[NSString stringWithFormat:@"Could not read file: %@", name]];
            continue;
        }
        NSError *attErr = nil;
        NSString *attUUID = [[CPAttachmentService sharedService]
                             saveAttachmentData:data
                             filename:name
                             ownerID:self.invoiceUUID
                             ownerType:@"Invoice"
                             error:&attErr];
        if (!attUUID) {
            [self showAlert:@"Attachment Failed"
                    message:attErr.localizedDescription ?: @"Could not save attachment."];
            continue;
        }
        // Update in-memory list for immediate display
        NSMutableArray *attachments = [NSMutableArray arrayWithArray:self.invoiceData[@"attachments"] ?: @[]];
        [attachments addObject:@{@"name": name, @"type": @"PDF", @"uuid": attUUID}];
        self.invoiceData[@"attachments"] = [attachments copy];
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:CPInvoiceSectionAttachments]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

- (NSDecimalNumber *)cumulativeWriteOffAmount {
    // Read the aggregate writeOffAmount maintained by CPProcurementService.createWriteOffForInvoice:
    // This is always up-to-date after each loadInvoice call.
    if (self.invoice) {
        id raw = [self.invoice valueForKey:@"writeOffAmount"];
        return [self decimalFromData:raw];
    }
    return [NSDecimalNumber zero];
}

- (NSDecimalNumber *)decimalFromData:(id)value {
    if ([value isKindOfClass:[NSDecimalNumber class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [NSDecimalNumber decimalNumberWithDecimal:[(NSNumber *)value decimalValue]];
    if ([value isKindOfClass:[NSString class]]) return [NSDecimalNumber decimalNumberWithString:value];
    return [NSDecimalNumber zero];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
