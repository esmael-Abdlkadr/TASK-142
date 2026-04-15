// CPProcurementCaseViewController.m
// ChargeProcure
//
// Full procurement case detail view with workflow timeline, stage-specific
// action sections, documents, audit trail, notes, and RBAC gating.

#import "CPProcurementCaseViewController.h"
#import "CPInvoiceViewController.h"
#import "CPWriteOffViewController.h"
#import "CPProcurementService.h"
#import "CPProcurementCase+CoreDataClass.h"
#import "CPProcurementCase+CoreDataProperties.h"
#import "CPRBACService.h"
#import "CPAuditService.h"
#import "CPAuthService.h"
#import "CPAttachmentService.h"
#import "CPCoreDataStack.h"
#import "CPNumberFormatter.h"
#import "CPDateFormatter.h"
#import "CPIDGenerator.h"
#import <CoreData/CoreData.h>
#import <QuickLook/QuickLook.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ---------------------------------------------------------------------------
// MARK: - Section layout
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, CPCaseSection) {
    CPCaseSectionHeader        = 0,
    CPCaseSectionTimeline      = 1,
    CPCaseSectionStageActions  = 2,
    CPCaseSectionDocuments     = 3,
    CPCaseSectionAuditTrail    = 4,
    CPCaseSectionNotes         = 5,
    CPCaseSectionCount         = 6,
};

// ---------------------------------------------------------------------------
// MARK: - File-scope stage helpers
// ---------------------------------------------------------------------------

static NSString *CPCaseStageName(CPProcurementStage stage) {
    switch (stage) {
        case CPProcurementStageDraft:          return @"Draft";
        case CPProcurementStageRequisition:    return @"Requisition";
        case CPProcurementStageRFQ:            return @"RFQ";
        case CPProcurementStagePO:             return @"Purchase Order";
        case CPProcurementStageReceipt:        return @"Receipt";
        case CPProcurementStageInvoice:        return @"Invoice";
        case CPProcurementStageReconciliation: return @"Reconciliation";
        case CPProcurementStagePayment:        return @"Payment";
        case CPProcurementStageClosed:         return @"Closed";
    }
    return @"Unknown";
}

static UIColor *CPCaseStageBadgeColor(CPProcurementStage stage) {
    switch (stage) {
        case CPProcurementStageDraft:          return UIColor.systemGrayColor;
        case CPProcurementStageRequisition:    return UIColor.systemBlueColor;
        case CPProcurementStageRFQ:            return UIColor.systemPurpleColor;
        case CPProcurementStagePO:             return [UIColor colorWithRed:0.0 green:0.5 blue:0.5 alpha:1.0];
        case CPProcurementStageReceipt:        return UIColor.systemOrangeColor;
        case CPProcurementStageInvoice:        return UIColor.systemYellowColor;
        case CPProcurementStageReconciliation: return UIColor.systemPinkColor;
        case CPProcurementStagePayment:        return UIColor.systemGreenColor;
        case CPProcurementStageClosed:         return UIColor.systemGrayColor;
    }
    return UIColor.systemGrayColor;
}

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface CPProcurementCaseViewController () <UITableViewDelegate, UITableViewDataSource,
                                               UIDocumentPickerDelegate,
                                               QLPreviewControllerDataSource,
                                               QLPreviewControllerDelegate>

@property (nonatomic, strong) UITableView       *tableView;
@property (nonatomic, strong) CPProcurementCase *procCase;
@property (nonatomic, strong) NSArray           *auditEvents;
@property (nonatomic, strong) NSArray           *documents;      // array of NSDictionary metadata
@property (nonatomic, strong) NSArray           *bids;           // array of NSDictionary for RFQ bids
@property (nonatomic, strong) UITextView        *notesTextView;

// RBAC
@property (nonatomic, assign) BOOL canApprove;
@property (nonatomic, assign) BOOL canUpdate;
@property (nonatomic, assign) BOOL canCreate;
@property (nonatomic, assign) BOOL isFinanceApprover;

// QLPreviewController backing URL
@property (nonatomic, strong) NSURL *previewURL;

@end

// ---------------------------------------------------------------------------
// MARK: - Implementation
// ---------------------------------------------------------------------------

@implementation CPProcurementCaseViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self loadCase];
    [self checkPermissions];
    [self buildTableView];
    [self buildNavButtons];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - Data
// ---------------------------------------------------------------------------

- (void)loadCase {
    if (!self.caseUUID) return;
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [CPProcurementCase fetchRequest];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", self.caseUUID];
    req.fetchLimit = 1;
    NSError *err = nil;
    NSArray *results = [ctx executeFetchRequest:req error:&err];
    self.procCase = results.firstObject;

    self.title = self.procCase.caseNumber ?: @"Procurement Case";

    // Audit events (last 5)
    NSArray *all = [[CPAuditService sharedService] fetchEventsForResource:@"Procurement"
                                                               resourceID:self.caseUUID];
    self.auditEvents = (all.count > 5) ? [all subarrayWithRange:NSMakeRange(0, 5)] : all;

    // Simulated documents from metadata JSON
    [self loadDocumentsFromMetadata];
    [self loadBidsFromMetadata];
}

- (void)loadDocumentsFromMetadata {
    if (!self.procCase.metadata) { self.documents = @[]; return; }
    NSData *data = [self.procCase.metadata dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    self.documents = meta[@"documents"] ?: @[];
}

- (void)loadBidsFromMetadata {
    if (!self.procCase.metadata) { self.bids = @[]; return; }
    NSData *data = [self.procCase.metadata dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    self.bids = meta[@"bids"] ?: @[];
}

- (void)reloadData {
    [self loadCase];
    [self checkPermissions];
    [self.tableView reloadData];
}

- (void)saveMetadata:(NSDictionary *)updatedMeta {
    NSError *jsonErr = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:updatedMeta options:0 error:&jsonErr];
    if (!jsonErr && data) {
        self.procCase.metadata = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        self.procCase.updatedAt = [NSDate date];
        [[CPCoreDataStack sharedStack] saveMainContext];
    }
}

- (NSMutableDictionary *)currentMeta {
    if (!self.procCase.metadata) return [NSMutableDictionary dictionary];
    NSData *data = [self.procCase.metadata dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return meta ? [meta mutableCopy] : [NSMutableDictionary dictionary];
}

// ---------------------------------------------------------------------------
#pragma mark - RBAC
// ---------------------------------------------------------------------------

- (void)checkPermissions {
    CPRBACService *rbac = [CPRBACService sharedService];
    self.canApprove        = [rbac currentUserCanPerform:CPActionApprove onResource:CPResourceProcurement];
    self.canUpdate         = [rbac currentUserCanPerform:CPActionUpdate  onResource:CPResourceProcurement];
    self.canCreate         = [rbac currentUserCanPerform:CPActionCreate  onResource:CPResourceProcurement];
    self.isFinanceApprover = [rbac currentUserCanPerform:CPActionApprove onResource:CPResourceWriteOff];
}

// ---------------------------------------------------------------------------
#pragma mark - UI
// ---------------------------------------------------------------------------

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildNavButtons {
    // Share button for everyone who can read
    UIBarButtonItem *share = [[UIBarButtonItem alloc]
                              initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                              target:self
                              action:@selector(shareCaseTapped)];
    share.accessibilityLabel = @"Share case";
    self.navigationItem.rightBarButtonItem = share;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CPCaseSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case CPCaseSectionHeader:        return nil;
        case CPCaseSectionTimeline:      return @"Workflow";
        case CPCaseSectionStageActions:  return @"Stage Actions";
        case CPCaseSectionDocuments:     return @"Documents";
        case CPCaseSectionAuditTrail:    return @"Recent Activity";
        case CPCaseSectionNotes:         return @"Notes";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CPCaseSectionHeader:       return 1;
        case CPCaseSectionTimeline:     return 9; // all 9 stages
        case CPCaseSectionStageActions: return [self stageActionRowCount];
        case CPCaseSectionDocuments:    return MAX((NSInteger)self.documents.count, 1) + 1; // +1 for add button
        case CPCaseSectionAuditTrail:   return MAX((NSInteger)self.auditEvents.count, 1);
        case CPCaseSectionNotes:        return 1;
        default: return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == CPCaseSectionHeader) return 120;
    if (indexPath.section == CPCaseSectionNotes)  return 120;
    return UITableViewAutomaticDimension;
}

// ---------------------------------------------------------------------------
#pragma mark - Cell Dispatch
// ---------------------------------------------------------------------------

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case CPCaseSectionHeader:       return [self headerCell];
        case CPCaseSectionTimeline:     return [self timelineCellForStage:(CPProcurementStage)indexPath.row];
        case CPCaseSectionStageActions: return [self stageActionCellAtRow:indexPath.row];
        case CPCaseSectionDocuments:    return [self documentCellAtRow:indexPath.row];
        case CPCaseSectionAuditTrail:   return [self auditCellAtRow:indexPath.row];
        case CPCaseSectionNotes:        return [self notesCell];
        default: return [UITableViewCell new];
    }
}

// ---- Header ----

- (UITableViewCell *)headerCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    CPProcurementCase *c = self.procCase;
    if (!c) return cell;

    CPProcurementStage stage = [c procurementStage];

    UILabel *caseNum = [UILabel new];
    caseNum.text = c.caseNumber ?: @"—";
    caseNum.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    caseNum.textColor = UIColor.secondaryLabelColor;

    UILabel *title = [UILabel new];
    title.text = c.title ?: @"Untitled";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    title.numberOfLines = 2;

    UILabel *vendor = [UILabel new];
    vendor.text = c.vendorName ?: @"No vendor";
    vendor.font = [UIFont systemFontOfSize:14];
    vendor.textColor = UIColor.secondaryLabelColor;

    NSDecimalNumber *amount = c.estimatedAmount ?: [NSDecimalNumber zero];
    UILabel *amountLabel = [UILabel new];
    amountLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:amount];
    amountLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];

    // Stage badge
    UIView *badge = [UIView new];
    badge.backgroundColor = CPCaseStageBadgeColor(stage);
    badge.layer.cornerRadius = 8;
    badge.clipsToBounds = YES;
    badge.accessibilityLabel = [NSString stringWithFormat:@"Stage: %@", CPCaseStageName(stage)];
    badge.isAccessibilityElement = YES;

    UILabel *badgeLabel = [UILabel new];
    badgeLabel.text = CPCaseStageName(stage);
    badgeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    badgeLabel.textColor = UIColor.whiteColor;
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:badgeLabel];
    [NSLayoutConstraint activateConstraints:@[
        [badgeLabel.topAnchor constraintEqualToAnchor:badge.topAnchor constant:3],
        [badgeLabel.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor constant:-3],
        [badgeLabel.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:8],
        [badgeLabel.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-8],
    ]];

    UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[caseNum, badge]];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.spacing = 8;
    topRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *amountRow = [[UIStackView alloc] initWithArrangedSubviews:@[vendor, amountLabel]];
    amountRow.axis = UILayoutConstraintAxisHorizontal;
    amountRow.distribution = UIStackViewDistributionEqualSpacing;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, title, amountRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
    ]];
    return cell;
}

// ---- Timeline ----

- (UITableViewCell *)timelineCellForStage:(CPProcurementStage)stageForRow {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (!self.procCase) return cell;

    CPProcurementStage currentStage = [self.procCase procurementStage];
    BOOL isCompleted = (stageForRow < currentStage);
    BOOL isCurrent   = (stageForRow == currentStage);

    // Checkmark / circle
    UIImageView *indicator;
    if (isCompleted) {
        indicator = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
        indicator.tintColor = UIColor.systemGreenColor;
    } else if (isCurrent) {
        indicator = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right.circle.fill"]];
        indicator.tintColor = UIColor.systemBlueColor;
    } else {
        indicator = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"circle"]];
        indicator.tintColor = UIColor.systemGrayColor;
    }
    indicator.contentMode = UIViewContentModeScaleAspectFit;
    indicator.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *nameLabel = [UILabel new];
    nameLabel.text = CPCaseStageName(stageForRow);
    nameLabel.font = isCurrent
        ? [UIFont systemFontOfSize:14 weight:UIFontWeightBold]
        : [UIFont systemFontOfSize:14];
    nameLabel.textColor = isCompleted ? UIColor.secondaryLabelColor : UIColor.labelColor;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[indicator, nameLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [indicator.widthAnchor constraintEqualToConstant:22],
        [indicator.heightAnchor constraintEqualToConstant:22],
        [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [row.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
    ]];

    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@",
                               CPCaseStageName(stageForRow),
                               isCompleted ? @"completed" : (isCurrent ? @"current stage" : @"not yet reached")];
    return cell;
}

// ---- Stage Actions ----

- (NSInteger)stageActionRowCount {
    if (!self.procCase) return 0;
    switch ([self.procCase procurementStage]) {
        case CPProcurementStageDraft:          return 1;  // Submit for Requisition
        case CPProcurementStageRequisition:    return 1;  // Approve
        case CPProcurementStageRFQ:            return (NSInteger)self.bids.count + 2; // bids + Add Bid + Select Bid
        case CPProcurementStagePO:             return 2;  // View PO + Mark Received
        case CPProcurementStageReceipt:        return 2;  // Log Return + Proceed to Invoice
        case CPProcurementStageInvoice:        return 2;  // Create Invoice + variance label
        case CPProcurementStageReconciliation: return self.isFinanceApprover ? 2 : 1; // Reconcile + Write-Off
        case CPProcurementStagePayment:        return 1;  // Record Payment
        case CPProcurementStageClosed:         return 1;  // Closed info
        default: return 0;
    }
}

- (UITableViewCell *)stageActionCellAtRow:(NSInteger)row {
    CPProcurementStage stage = self.procCase ? [self.procCase procurementStage] : CPProcurementStageDraft;
    switch (stage) {
        case CPProcurementStageDraft:          return [self draftActionCellAtRow:row];
        case CPProcurementStageRequisition:    return [self requisitionActionCellAtRow:row];
        case CPProcurementStageRFQ:            return [self rfqActionCellAtRow:row];
        case CPProcurementStagePO:             return [self poActionCellAtRow:row];
        case CPProcurementStageReceipt:        return [self receiptActionCellAtRow:row];
        case CPProcurementStageInvoice:        return [self invoiceActionCellAtRow:row];
        case CPProcurementStageReconciliation: return [self reconciliationActionCellAtRow:row];
        case CPProcurementStagePayment:        return [self paymentActionCellAtRow:row];
        case CPProcurementStageClosed:         return [self closedInfoCell];
    }
    return [UITableViewCell new];
}

- (UITableViewCell *)draftActionCellAtRow:(NSInteger)row {
    return [self actionCellWithTitle:@"Submit for Requisition"
                               color:UIColor.systemBlueColor
                             enabled:self.canUpdate
                              action:^{ [self advanceStageTo:CPProcurementStageRequisition]; }
                       accessibilityLabel:@"Submit this case for requisition approval"];
}

- (UITableViewCell *)requisitionActionCellAtRow:(NSInteger)row {
    return [self actionCellWithTitle:@"Approve Requisition"
                               color:UIColor.systemGreenColor
                             enabled:self.canApprove
                              action:^{
        NSString *approverID = [CPAuthService sharedService].currentUserID ?: @"";
        NSError *err = nil;
        BOOL ok = [[CPProcurementService sharedService]
                   approveRequisition:self.caseUUID
                   approverUUID:approverID
                   error:&err];
        if (!ok) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Approval Failed"
                message:err.localizedDescription ?: @"Could not approve requisition."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        [self reloadData];
    }
                       accessibilityLabel:@"Approve the requisition and advance to RFQ stage"];
}

- (UITableViewCell *)rfqActionCellAtRow:(NSInteger)row {
    NSInteger bidCount = (NSInteger)self.bids.count;
    if (row < bidCount) {
        // Bid comparison row
        NSDictionary *bid = self.bids[row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = bid[@"vendorName"] ?: @"Unknown Vendor";
        NSDecimalNumber *bidAmt = [NSDecimalNumber decimalNumberWithString:bid[@"amount"] ?: @"0"];
        cell.detailTextLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:bidAmt];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessibilityLabel = [NSString stringWithFormat:@"Bid from %@: %@",
                                   bid[@"vendorName"] ?: @"unknown",
                                   cell.detailTextLabel.text];
        return cell;
    } else if (row == bidCount) {
        return [self actionCellWithTitle:@"Add Bid"
                                   color:UIColor.systemPurpleColor
                                 enabled:self.canUpdate
                                  action:^{ [self addBidTapped]; }
                           accessibilityLabel:@"Add a vendor bid"];
    } else {
        return [self actionCellWithTitle:@"Select Winning Bid"
                                   color:UIColor.systemGreenColor
                                 enabled:(self.canApprove && bidCount > 0)
                                  action:^{ [self selectBidTapped]; }
                           accessibilityLabel:@"Select the winning bid and advance to Purchase Order stage"];
    }
}

- (UITableViewCell *)poActionCellAtRow:(NSInteger)row {
    if (row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = @"PO Number";
        cell.detailTextLabel.text = self.procCase.poNumber ?: @"—";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    return [self actionCellWithTitle:@"Mark Items Received"
                               color:UIColor.systemOrangeColor
                             enabled:self.canUpdate
                              action:^{ [self markItemsReceivedTapped]; }
                       accessibilityLabel:@"Mark goods or services as received"];
}

- (UITableViewCell *)receiptActionCellAtRow:(NSInteger)row {
    if (row == 0) {
        return [self actionCellWithTitle:@"Log Return"
                                   color:UIColor.systemOrangeColor
                                 enabled:self.canUpdate
                                  action:^{ [self logReturnTapped]; }
                           accessibilityLabel:@"Log a return of received items"];
    }
    return [self actionCellWithTitle:@"Create / View Invoice"
                               color:UIColor.systemYellowColor
                             enabled:self.canUpdate
                              action:^{ [self createOrViewInvoiceTapped]; }
                       accessibilityLabel:@"Create or view the invoice for this case"];
}

- (UITableViewCell *)invoiceActionCellAtRow:(NSInteger)row {
    if (row == 0) {
        // Variance flag indicator
        BOOL varianceFlagged = [self isVarianceFlagged];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (varianceFlagged) {
            UILabel *warn = [UILabel new];
            warn.text = @"⚠ Variance Flagged: Invoice amount differs from PO amount";
            warn.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            warn.textColor = UIColor.systemRedColor;
            warn.numberOfLines = 0;
            warn.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:warn];
            [NSLayoutConstraint activateConstraints:@[
                [warn.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
                [warn.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
                [warn.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [warn.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            ]];
            cell.accessibilityLabel = @"Warning: Variance flagged";
        } else {
            cell.textLabel.text = @"No variance detected";
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
        }
        return cell;
    }
    return [self actionCellWithTitle:@"Create / View Invoice"
                               color:UIColor.systemYellowColor
                             enabled:self.canCreate
                              action:^{ [self createOrViewInvoiceTapped]; }
                       accessibilityLabel:@"Create or view the invoice for this case"];
}

- (UITableViewCell *)reconciliationActionCellAtRow:(NSInteger)row {
    if (row == 0) {
        return [self actionCellWithTitle:@"Reconcile"
                                   color:UIColor.systemPinkColor
                                 enabled:self.canApprove
                                  action:^{ [self reconcileTapped]; }
                           accessibilityLabel:@"Reconcile and advance to Payment stage"];
    }
    // Write-off — finance approver only
    return [self actionCellWithTitle:@"Write-Off Amount"
                               color:UIColor.systemRedColor
                             enabled:self.isFinanceApprover
                              action:^{ [self writeOffTapped]; }
                       accessibilityLabel:@"Write off a variance amount, requires finance approver role"];
}

- (UITableViewCell *)paymentActionCellAtRow:(NSInteger)row {
    return [self actionCellWithTitle:@"Record Payment"
                               color:UIColor.systemGreenColor
                             enabled:self.canApprove
                              action:^{ [self recordPaymentTapped]; }
                       accessibilityLabel:@"Record that payment has been made and close the case"];
}

- (UITableViewCell *)closedInfoCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = @"Case Closed";
    cell.textLabel.textColor = UIColor.secondaryLabelColor;
    if (self.procCase.closedAt) {
        cell.detailTextLabel.text = [[CPDateFormatter sharedFormatter]
                                     displayDateTimeStringFromDate:self.procCase.closedAt];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// ---- Documents ----

- (UITableViewCell *)documentCellAtRow:(NSInteger)row {
    NSInteger docCount = (NSInteger)self.documents.count;
    if (row < docCount) {
        NSDictionary *doc = self.documents[row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = doc[@"name"] ?: @"Document";
        cell.detailTextLabel.text = doc[@"type"] ?: @"";
        cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];
        cell.imageView.tintColor = UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityLabel = [NSString stringWithFormat:@"Document: %@", doc[@"name"] ?: @""];
        return cell;
    }
    // Add document button row
    return [self actionCellWithTitle:@"Add Document"
                               color:UIColor.systemBlueColor
                             enabled:self.canUpdate
                              action:^{ [self addDocumentTapped]; }
                       accessibilityLabel:@"Attach a document to this procurement case"];
}

// ---- Audit Trail ----

- (UITableViewCell *)auditCellAtRow:(NSInteger)row {
    if (self.auditEvents.count == 0) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.textLabel.text = @"No activity recorded";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    NSManagedObject *event = self.auditEvents[row];
    NSString *action = [event valueForKey:@"action"] ?: @"—";
    NSString *detail = [event valueForKey:@"detail"] ?: @"";
    NSDate   *date   = [event valueForKey:@"createdAt"];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = action;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@",
                                 date ? [[CPDateFormatter sharedFormatter] relativeStringFromDate:date] : @"",
                                 detail];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// ---- Notes ----

- (UITableViewCell *)notesCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (!_notesTextView) {
        _notesTextView = [UITextView new];
        _notesTextView.font = [UIFont systemFontOfSize:14];
        _notesTextView.layer.cornerRadius = 6;
        _notesTextView.layer.borderColor = UIColor.separatorColor.CGColor;
        _notesTextView.layer.borderWidth = 0.5;
        _notesTextView.accessibilityLabel = @"Case notes";
    }
    NSDictionary *meta = [self currentMeta];
    _notesTextView.text = meta[@"notes"] ?: @"";
    _notesTextView.editable = self.canUpdate;

    _notesTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:_notesTextView];
    [NSLayoutConstraint activateConstraints:@[
        [_notesTextView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [_notesTextView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [_notesTextView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [_notesTextView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
    ]];

    if (self.canUpdate) {
        UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
        [save setTitle:@"Save Notes" forState:UIControlStateNormal];
        save.translatesAutoresizingMaskIntoConstraints = NO;
        save.accessibilityLabel = @"Save case notes";
        [save addTarget:self action:@selector(saveNotesTapped) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:save];
        [NSLayoutConstraint activateConstraints:@[
            [save.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [save.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
        ]];
    }
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == CPCaseSectionDocuments) {
        NSInteger docCount = (NSInteger)self.documents.count;
        if (indexPath.row < docCount) {
            [self viewDocumentAtIndex:indexPath.row];
        }
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Action Helpers
// ---------------------------------------------------------------------------

- (void)advanceStageTo:(CPProcurementStage)targetStage {
    if (!self.procCase) return;
    // Advance through stages if needed
    while ([self.procCase procurementStage] < targetStage) {
        if (![self.procCase advanceStage]) break;
    }
    [[CPCoreDataStack sharedStack] saveMainContext];
    [[CPAuditService sharedService] logAction:@"stage_advanced"
                                     resource:@"Procurement"
                                   resourceID:self.caseUUID
                                       detail:[NSString stringWithFormat:@"Advanced to %@", CPCaseStageName(targetStage)]];
    [self reloadData];
}

- (void)addBidTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Bid"
                                                                   message:@"Enter vendor and bid amount"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Vendor name"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Amount (e.g. 1500.00)";
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *vendor = alert.textFields[0].text;
        NSString *amount = alert.textFields[1].text;
        if (!vendor.length || !amount.length) return;
        NSMutableDictionary *meta = [self currentMeta];
        NSMutableArray *bids = [NSMutableArray arrayWithArray:meta[@"bids"] ?: @[]];
        [bids addObject:@{@"vendorName": vendor, @"amount": amount}];
        meta[@"bids"] = [bids copy];
        [self saveMetadata:meta];
        [self reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectBidTapped {
    if (self.bids.count == 0) return;
    // Show picker of bids
    NSMutableArray *actions = [NSMutableArray array];
    for (NSDictionary *bid in self.bids) {
        NSString *title = [NSString stringWithFormat:@"%@ — %@",
                           bid[@"vendorName"] ?: @"Unknown",
                           bid[@"amount"] ?: @"0"];
        [actions addObject:[UIAlertAction actionWithTitle:title
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            // Insert the chosen bid into Core Data then select it via the service,
            // which enforces RBAC and advances the case to PO stage.
            NSString *vendorName = bid[@"vendorName"] ?: @"Unknown";
            NSDecimalNumber *total = [NSDecimalNumber decimalNumberWithString:bid[@"amount"] ?: @"0"];
            NSError *bidErr = nil;
            BOOL added = [[CPProcurementService sharedService]
                          addRFQBidForCase:self.caseUUID
                          vendorUUID:[[NSUUID UUID] UUIDString]
                          vendorName:vendorName
                          unitPrice:total
                          totalPrice:total
                          taxAmount:[NSDecimalNumber zero]
                          notes:nil
                          error:&bidErr];
            if (!added) {
                UIAlertController *errAlert = [UIAlertController
                    alertControllerWithTitle:@"Bid Error"
                    message:bidErr.localizedDescription ?: @"Could not add bid."
                    preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
                return;
            }
            // Fetch the newly inserted bid's UUID from the shared store
            NSManagedObjectContext *mainCtx = [CPCoreDataStack sharedStack].mainContext;
            __block NSString *newBidUUID = nil;
            [mainCtx performBlockAndWait:^{
                NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
                req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", vendorName];
                req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"submittedAt" ascending:NO]];
                req.fetchLimit = 1;
                NSArray *results = [mainCtx executeFetchRequest:req error:nil];
                newBidUUID = [results.firstObject valueForKey:@"uuid"];
            }];
            if (!newBidUUID) { return; }
            NSError *selectErr = nil;
            BOOL ok = [[CPProcurementService sharedService]
                       selectRFQBid:newBidUUID
                       forCase:self.caseUUID
                       error:&selectErr];
            if (!ok) {
                UIAlertController *errAlert = [UIAlertController
                    alertControllerWithTitle:@"Selection Failed"
                    message:selectErr.localizedDescription ?: @"Could not select bid."
                    preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
            }
            [self reloadData];
        }]];
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Select Winning Bid"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (UIAlertAction *a in actions) [sheet addAction:a];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)markItemsReceivedTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mark Items Received"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Partial Receipt"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        NSMutableDictionary *meta = [self currentMeta];
        meta[@"receiptType"] = @"partial";
        [self saveMetadata:meta];
        [[CPAuditService sharedService] logAction:@"partial_receipt"
                                         resource:@"Procurement"
                                       resourceID:self.caseUUID
                                           detail:@"Partial receipt logged"];
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Full Receipt"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        // Route through service: createReceiptForCase: handles RBAC,
        // advances PO→Receipt, creates the receipt entity, and (if full)
        // auto-advances Receipt→Invoice.
        NSError *err = nil;
        NSString *receiptUUID = [[CPProcurementService sharedService]
                                 createReceiptForCase:self.caseUUID
                                 receivedItems:@[@{@"description": @"Full receipt", @"receivedQty": [NSDecimalNumber one]}]
                                 isPartial:NO
                                 notes:@"Full receipt recorded"
                                 error:&err];
        if (!receiptUUID) {
            UIAlertController *errAlert = [UIAlertController
                alertControllerWithTitle:@"Receipt Failed"
                message:err.localizedDescription ?: @"Could not create receipt."
                preferredStyle:UIAlertControllerStyleAlert];
            [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:errAlert animated:YES completion:nil];
        }
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)logReturnTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Log Return"
                                                                   message:@"Reason for return"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Reason"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Log" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *reason = alert.textFields.firstObject.text ?: @"";
        [[CPAuditService sharedService] logAction:@"return_logged"
                                         resource:@"Procurement"
                                       resourceID:self.caseUUID
                                           detail:[NSString stringWithFormat:@"Return: %@", reason]];
        [self reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// Returns the UUID of the Core Data Invoice entity associated with this case,
/// or nil if no invoice has been created yet.
- (nullable NSString *)currentInvoiceUUIDForCase {
    if (!self.caseUUID) return nil;
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
    req.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", self.caseUUID];
    req.fetchLimit = 1;
    NSArray *results = [ctx executeFetchRequest:req error:nil];
    return [results.firstObject valueForKey:@"uuid"];
}

- (void)createOrViewInvoiceTapped {
    // Look up or create the Invoice entity in Core Data via CPProcurementService.
    // This ensures invoice data is persisted in the service layer, not UserDefaults.
    NSString *invoiceUUID = [self currentInvoiceUUIDForCase];

    if (!invoiceUUID) {
        // Create the invoice entity through the service
        NSError *err = nil;
        NSDecimalNumber *amount = self.procCase.estimatedAmount ?: [NSDecimalNumber zero];
        NSDate *dueDate = [NSDate dateWithTimeIntervalSinceNow:30 * 24 * 60 * 60];
        NSString *invNumber = [[CPIDGenerator sharedGenerator] generateInvoiceID];
        invoiceUUID = [[CPProcurementService sharedService]
                       createInvoiceForCase:self.caseUUID
                       invoiceNumber:invNumber
                       vendorInvoiceNumber:@""
                       totalAmount:amount
                       taxAmount:[NSDecimalNumber zero]
                       dueDate:dueDate
                       lineItems:@[]
                       error:&err];
        if (!invoiceUUID) {
            NSString *msg = err.localizedDescription ?: @"Could not create invoice. Ensure the case has reached Receipt stage.";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invoice Error"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    }

    CPInvoiceViewController *vc = [CPInvoiceViewController new];
    vc.invoiceUUID = invoiceUUID;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)reconcileTapped {
    NSString *invoiceUUID = [self currentInvoiceUUIDForCase];
    if (!invoiceUUID) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"No Invoice"
            message:@"An invoice must be created before reconciling."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"";
    NSError *err = nil;
    BOOL ok = [[CPProcurementService sharedService]
               reconcileInvoice:invoiceUUID
               reconciledByUUID:userID
               error:&err];
    if (!ok) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Reconciliation Failed"
            message:err.localizedDescription ?: @"Could not reconcile invoice."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    [self reloadData];
}

- (void)writeOffTapped {
    // Navigate to CPWriteOffViewController — the dedicated write-off form
    // that routes all mutations through CPProcurementService.createWriteOffForInvoice:
    NSString *invoiceUUID = [self currentInvoiceUUIDForCase];
    if (!invoiceUUID) {
        UIAlertController *alert = [UIAlertController
                                    alertControllerWithTitle:@"No Invoice"
                                    message:@"An invoice must be created before recording a write-off."
                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    CPWriteOffViewController *vc = [CPWriteOffViewController new];
    vc.invoiceUUID = invoiceUUID;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)recordPaymentTapped {
    NSString *invoiceUUID = [self currentInvoiceUUIDForCase];
    if (!invoiceUUID) {
        UIAlertController *alert = [UIAlertController
                                    alertControllerWithTitle:@"No Invoice"
                                    message:@"An invoice must exist before recording payment."
                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Record Payment"
                                                                   message:@"Enter amount and payment method"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Amount (e.g. 1500.00)";
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Method (ACH, Wire, Check…)"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Record" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *amountStr = alert.textFields[0].text;
        NSString *method    = alert.textFields[1].text.length > 0 ? alert.textFields[1].text : @"ACH";
        if (!amountStr.length) return;

        NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:amountStr];
        NSError *err = nil;
        NSString *paymentUUID = [[CPProcurementService sharedService]
                                 createPaymentForInvoice:invoiceUUID
                                 amount:amount
                                 method:method
                                 notes:nil
                                 error:&err];
        if (paymentUUID) {
            [self reloadData];
        } else {
            UIAlertController *errAlert = [UIAlertController
                                           alertControllerWithTitle:@"Payment Failed"
                                           message:err.localizedDescription ?: @"Could not record payment."
                                           preferredStyle:UIAlertControllerStyleAlert];
            [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:errAlert animated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addDocumentTapped {
    // Present a document picker so the user selects an actual file.
    // The saved attachment UUID is stored in metadata so viewDocumentAtIndex: can load it.
    NSArray *contentTypes;
    if (@available(iOS 14.0, *)) {
        contentTypes = @[UTTypeItem.identifier];
    } else {
        contentTypes = @[@"public.item"];
    }
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc]
                  initForOpeningContentTypes:@[UTTypeItem]];
    } else {
        picker = [[UIDocumentPickerViewController alloc]
                  initWithDocumentTypes:contentTypes
                                 inMode:UIDocumentPickerModeImport];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)viewDocumentAtIndex:(NSInteger)index {
    NSDictionary *doc = self.documents[index];
    NSString *attachmentUUID = doc[@"uuid"];
    NSString *fileName       = doc[@"name"] ?: @"Document";

    if (!attachmentUUID.length) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:fileName
            message:@"No file has been uploaded for this document."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    NSError *loadError = nil;
    NSData *fileData = [[CPAttachmentService sharedService]
                        loadAttachmentWithUUID:attachmentUUID error:&loadError];
    if (!fileData) {
        UIAlertController *err = [UIAlertController
            alertControllerWithTitle:@"Preview Unavailable"
            message:loadError.localizedDescription ?: @"The document file could not be loaded."
            preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    NSString *tmpDir = NSTemporaryDirectory();
    NSURL *tmpURL = [NSURL fileURLWithPath:[tmpDir stringByAppendingPathComponent:fileName]];
    NSError *writeError = nil;
    if (![fileData writeToURL:tmpURL options:NSDataWritingAtomic error:&writeError]) {
        UIAlertController *err = [UIAlertController
            alertControllerWithTitle:@"Preview Unavailable"
            message:writeError.localizedDescription ?: @"Could not write preview file."
            preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    self.previewURL = tmpURL;
    QLPreviewController *ql = [[QLPreviewController alloc] init];
    ql.dataSource = self;
    ql.delegate   = self;
    [self presentViewController:ql animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - UIDocumentPickerDelegate
// ---------------------------------------------------------------------------

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!self.procCase) return;
    NSURL *url = urls.firstObject;
    if (!url) return;

    NSString *name = url.lastPathComponent ?: @"document";
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) {
        UIAlertController *err = [UIAlertController
            alertControllerWithTitle:@"File Error"
            message:[NSString stringWithFormat:@"Could not read file: %@", name]
            preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    NSError *attErr = nil;
    NSString *caseUUID = self.procCase.uuid;
    NSString *attUUID = [[CPAttachmentService sharedService]
                         saveAttachmentData:data
                         filename:name
                         ownerID:caseUUID
                         ownerType:@"ProcurementCase"
                         error:&attErr];
    if (!attUUID) {
        UIAlertController *err = [UIAlertController
            alertControllerWithTitle:@"Attachment Failed"
            message:attErr.localizedDescription ?: @"Could not save document."
            preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    // Persist the CPAttachmentService UUID so viewDocumentAtIndex: can load it.
    NSMutableDictionary *meta = [self currentMeta];
    NSMutableArray *docs = [NSMutableArray arrayWithArray:meta[@"documents"] ?: @[]];
    [docs addObject:@{@"name": name, @"type": @"PDF", @"uuid": attUUID}];
    meta[@"documents"] = [docs copy];
    [self saveMetadata:meta];
    [self reloadData];
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
    if (self.previewURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.previewURL error:nil];
        self.previewURL = nil;
    }
}

- (void)saveNotesTapped {
    NSMutableDictionary *meta = [self currentMeta];
    meta[@"notes"] = _notesTextView.text ?: @"";
    [self saveMetadata:meta];
    [_notesTextView resignFirstResponder];
    UINotificationFeedbackGenerator *f = [UINotificationFeedbackGenerator new];
    [f notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)shareCaseTapped {
    if (!self.procCase) return;
    NSString *summary = [NSString stringWithFormat:
                         @"Procurement Case %@\nTitle: %@\nStage: %@\nVendor: %@\nAmount: %@",
                         self.procCase.caseNumber ?: @"",
                         self.procCase.title ?: @"",
                         CPCaseStageName([self.procCase procurementStage]),
                         self.procCase.vendorName ?: @"",
                         [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:
                          self.procCase.estimatedAmount ?: [NSDecimalNumber zero]]];
    UIActivityViewController *vc = [[UIActivityViewController alloc]
                                    initWithActivityItems:@[summary]
                                    applicationActivities:nil];
    [self presentViewController:vc animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

- (BOOL)isVarianceFlagged {
    // Read varianceFlag from the Invoice entity related to this case, not from
    // case metadata (which is not written by CPProcurementService).
    NSSet *invoices = [self.procCase valueForKey:@"invoices"];
    for (NSManagedObject *invoice in invoices) {
        if ([[invoice valueForKey:@"varianceFlag"] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (UITableViewCell *)actionCellWithTitle:(NSString *)title
                                   color:(UIColor *)color
                                 enabled:(BOOL)enabled
                                  action:(void (^)(void))action
                       accessibilityLabel:(NSString *)a11yLabel {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = enabled ? color : UIColor.systemGrayColor;
    button.layer.cornerRadius = 8;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.enabled = enabled;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = a11yLabel;
    button.accessibilityHint = enabled ? nil : @"You do not have permission to perform this action";

    void (^capturedAction)(void) = action;
    [button addAction:[UIAction actionWithTitle:@"" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        if (capturedAction) capturedAction();
    }] forControlEvents:UIControlEventTouchUpInside];

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

@end
