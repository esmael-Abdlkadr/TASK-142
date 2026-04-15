// CPProcurementListViewController.m
// ChargeProcure
//
// Filterable list of procurement cases backed by NSFetchedResultsController.

#import "CPProcurementListViewController.h"
#import "CPProcurementCaseViewController.h"
#import "CPProcurementCase+CoreDataClass.h"
#import "CPProcurementCase+CoreDataProperties.h"
#import "CPRBACService.h"
#import "CPCoreDataStack.h"
#import "CPNumberFormatter.h"
#import "CPDateFormatter.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// MARK: - Stage Filter Segments
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, CPProcurementFilterSegment) {
    CPProcurementFilterAll            = 0,
    CPProcurementFilterOpen           = 1,
    CPProcurementFilterVarianceFlagged = 2,
    CPProcurementFilterPendingReview  = 3,
};

// ---------------------------------------------------------------------------
// MARK: - Stage badge helpers (file-scope)
// ---------------------------------------------------------------------------

static NSString *CPStageName(CPProcurementStage stage) {
    switch (stage) {
        case CPProcurementStageDraft:          return @"Draft";
        case CPProcurementStageRequisition:    return @"Requisition";
        case CPProcurementStageRFQ:            return @"RFQ";
        case CPProcurementStagePO:             return @"PO";
        case CPProcurementStageReceipt:        return @"Receipt";
        case CPProcurementStageInvoice:        return @"Invoice";
        case CPProcurementStageReconciliation: return @"Reconciliation";
        case CPProcurementStagePayment:        return @"Payment";
        case CPProcurementStageClosed:         return @"Closed";
    }
    return @"Unknown";
}

static UIColor *CPStageBadgeColor(CPProcurementStage stage) {
    switch (stage) {
        case CPProcurementStageDraft:          return UIColor.systemGrayColor;
        case CPProcurementStageRequisition:    return UIColor.systemBlueColor;
        case CPProcurementStageRFQ:            return UIColor.systemPurpleColor;
        case CPProcurementStagePO:             return [UIColor colorWithRed:0.0 green:0.5 blue:0.5 alpha:1.0]; // teal
        case CPProcurementStageReceipt:        return UIColor.systemOrangeColor;
        case CPProcurementStageInvoice:        return UIColor.systemYellowColor;
        case CPProcurementStageReconciliation: return UIColor.systemPinkColor;
        case CPProcurementStagePayment:        return UIColor.systemGreenColor;
        case CPProcurementStageClosed:         return UIColor.systemGrayColor;
    }
    return UIColor.systemGrayColor;
}

// ---------------------------------------------------------------------------
// MARK: - Cell
// ---------------------------------------------------------------------------

@interface CPProcurementCell : UITableViewCell
@property (nonatomic, strong) UILabel *caseNumberLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *vendorLabel;
@property (nonatomic, strong) UILabel *amountLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView  *stageBadge;
@property (nonatomic, strong) UILabel *stageLabel;
@property (nonatomic, strong) UIImageView *varianceIcon;
- (void)configureWithCase:(CPProcurementCase *)procCase;
@end

@implementation CPProcurementCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) [self buildLayout];
    return self;
}

- (void)buildLayout {
    // Case number
    _caseNumberLabel = [UILabel new];
    _caseNumberLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _caseNumberLabel.textColor = UIColor.secondaryLabelColor;

    // Title
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.numberOfLines = 2;

    // Vendor
    _vendorLabel = [UILabel new];
    _vendorLabel.font = [UIFont systemFontOfSize:13];
    _vendorLabel.textColor = UIColor.secondaryLabelColor;

    // Amount
    _amountLabel = [UILabel new];
    _amountLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _amountLabel.textAlignment = NSTextAlignmentRight;

    // Date
    _dateLabel = [UILabel new];
    _dateLabel.font = [UIFont systemFontOfSize:12];
    _dateLabel.textColor = UIColor.tertiaryLabelColor;

    // Stage badge
    _stageBadge = [UIView new];
    _stageBadge.layer.cornerRadius = 6;
    _stageBadge.clipsToBounds = YES;
    _stageLabel = [UILabel new];
    _stageLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    _stageLabel.textColor = UIColor.whiteColor;
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_stageBadge addSubview:_stageLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_stageLabel.topAnchor constraintEqualToAnchor:_stageBadge.topAnchor constant:3],
        [_stageLabel.bottomAnchor constraintEqualToAnchor:_stageBadge.bottomAnchor constant:-3],
        [_stageLabel.leadingAnchor constraintEqualToAnchor:_stageBadge.leadingAnchor constant:6],
        [_stageLabel.trailingAnchor constraintEqualToAnchor:_stageBadge.trailingAnchor constant:-6],
    ]];

    // Variance icon
    _varianceIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
    _varianceIcon.tintColor = UIColor.systemRedColor;
    _varianceIcon.contentMode = UIViewContentModeScaleAspectFit;
    _varianceIcon.accessibilityLabel = @"Variance flagged";

    // Top row: case number + badge + variance icon
    UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[_caseNumberLabel, _stageBadge, _varianceIcon]];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.spacing = 8;
    topRow.alignment = UIStackViewAlignmentCenter;

    // Bottom row: vendor + amount
    UIStackView *bottomRow = [[UIStackView alloc] initWithArrangedSubviews:@[_vendorLabel, _amountLabel]];
    bottomRow.axis = UILayoutConstraintAxisHorizontal;
    bottomRow.distribution = UIStackViewDistributionEqualSpacing;

    // Date row
    UIStackView *dateRow = [[UIStackView alloc] initWithArrangedSubviews:@[_dateLabel]];
    dateRow.axis = UILayoutConstraintAxisHorizontal;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, _titleLabel, bottomRow, dateRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_varianceIcon.widthAnchor constraintEqualToConstant:16],
        [_varianceIcon.heightAnchor constraintEqualToConstant:16],
    ]];
}

- (void)configureWithCase:(CPProcurementCase *)procCase {
    CPProcurementStage stage = [procCase procurementStage];
    _caseNumberLabel.text = procCase.caseNumber ?: @"—";
    _titleLabel.text      = procCase.title ?: @"Untitled";
    _vendorLabel.text     = procCase.vendorName ?: @"No vendor";

    NSDecimalNumber *amount = procCase.estimatedAmount ?: [NSDecimalNumber zero];
    _amountLabel.text = [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:amount];

    _stageLabel.text = CPStageName(stage);
    _stageBadge.backgroundColor = CPStageBadgeColor(stage);
    _stageBadge.accessibilityLabel = [NSString stringWithFormat:@"Stage: %@", CPStageName(stage)];

    // Variance flag — read from the related Invoice entity's varianceFlag attribute.
    BOOL varianceFlagged = NO;
    NSSet *invoices = [procCase valueForKey:@"invoices"];
    for (NSManagedObject *invoice in invoices) {
        if ([[invoice valueForKey:@"varianceFlag"] boolValue]) {
            varianceFlagged = YES;
            break;
        }
    }
    _varianceIcon.hidden = !varianceFlagged;

    NSDate *date = procCase.updatedAt ?: procCase.createdAt;
    _dateLabel.text = date ? [[CPDateFormatter sharedFormatter] relativeStringFromDate:date] : @"";

    // Accessibility
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@ stage, %@%@",
                               procCase.caseNumber ?: @"",
                               procCase.title ?: @"",
                               CPStageName(stage),
                               [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:amount],
                               varianceFlagged ? @", variance flagged" : @""];
}

@end

// ---------------------------------------------------------------------------
// MARK: - View Controller
// ---------------------------------------------------------------------------

static NSString * const kProcurementCellID = @"CPProcurementCell";

@interface CPProcurementListViewController () <UITableViewDelegate, UITableViewDataSource,
                                               NSFetchedResultsControllerDelegate>
@property (nonatomic, strong) UITableView                *tableView;
@property (nonatomic, strong) UISegmentedControl         *filterSegment;
@property (nonatomic, strong) UIRefreshControl           *refreshControl;
@property (nonatomic, strong) UIView                     *emptyStateView;
@property (nonatomic, strong) UILabel                    *emptyStateLabel;
@property (nonatomic, strong) NSFetchedResultsController *frc;
@property (nonatomic, assign) BOOL                        canCreateCase;
@end

@implementation CPProcurementListViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Procurement";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self checkPermissions];
    [self buildFilterSegment];
    [self buildTableView];
    [self buildEmptyState];
    [self buildFRC];
    [self updateAddButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.tableView.indexPathForSelectedRow) {
        [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:animated];
    }
    // Refresh RBAC state in case role changed
    [self checkPermissions];
    [self updateAddButton];
}

// ---------------------------------------------------------------------------
#pragma mark - Permissions
// ---------------------------------------------------------------------------

- (void)checkPermissions {
    self.canCreateCase = [[CPRBACService sharedService] currentUserCanPerform:CPActionCreate
                                                                   onResource:CPResourceProcurement];
}

- (void)updateAddButton {
    if (self.canCreateCase) {
        UIBarButtonItem *addButton = [[UIBarButtonItem alloc]
                                      initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                      target:self
                                      action:@selector(addCaseTapped)];
        addButton.accessibilityLabel = @"Create new procurement case";
        self.navigationItem.rightBarButtonItem = addButton;
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - UI
// ---------------------------------------------------------------------------

- (void)buildFilterSegment {
    _filterSegment = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Open", @"Variance", @"Pending"]];
    _filterSegment.selectedSegmentIndex = 0;
    [_filterSegment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    _filterSegment.accessibilityLabel = @"Filter procurement cases";

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 48)];
    _filterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_filterSegment];
    [NSLayoutConstraint activateConstraints:@[
        [_filterSegment.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [_filterSegment.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
        [_filterSegment.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [_filterSegment.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
    ]];
}

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 90;
    [_tableView registerClass:[CPProcurementCell class] forCellReuseIdentifier:kProcurementCellID];

    // Segment as table header
    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 48)];
    _filterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [headerContainer addSubview:_filterSegment];
    [NSLayoutConstraint activateConstraints:@[
        [_filterSegment.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:8],
        [_filterSegment.bottomAnchor constraintEqualToAnchor:headerContainer.bottomAnchor constant:-8],
        [_filterSegment.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:16],
        [_filterSegment.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-16],
    ]];
    _tableView.tableHeaderView = headerContainer;

    _refreshControl = [UIRefreshControl new];
    [_refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildEmptyState {
    _emptyStateView = [UIView new];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"doc.text.magnifyingglass"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = UIColor.systemGrayColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    _emptyStateLabel = [UILabel new];
    _emptyStateLabel.text = @"No procurement cases";
    _emptyStateLabel.textColor = UIColor.secondaryLabelColor;
    _emptyStateLabel.font = [UIFont systemFontOfSize:16];
    _emptyStateLabel.textAlignment = NSTextAlignmentCenter;
    _emptyStateLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, _emptyStateLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyStateView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:56],
        [icon.heightAnchor constraintEqualToConstant:56],
        [stack.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:_emptyStateView.centerYAnchor],
    ]];

    [self.view addSubview:_emptyStateView];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_emptyStateView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    _emptyStateView.hidden = YES;
}

// ---------------------------------------------------------------------------
#pragma mark - Core Data
// ---------------------------------------------------------------------------

- (void)buildFRC {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [CPProcurementCase fetchRequest];
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"updatedAt" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"caseNumber" ascending:YES],
    ];
    req.predicate = [self currentPredicate];
    // Fetch in pages of 50 rows. NSFetchedResultsController fault-batches
    // on demand, preventing full-table loads on large datasets.
    req.fetchBatchSize = 50;

    _frc = [[NSFetchedResultsController alloc] initWithFetchRequest:req
                                               managedObjectContext:ctx
                                                 sectionNameKeyPath:nil
                                                          cacheName:nil];
    _frc.delegate = self;
    NSError *err = nil;
    if (![_frc performFetch:&err]) {
        NSLog(@"[CPProcurementList] FRC fetch error: %@", err.localizedDescription);
    }
    [self updateEmptyState];
}

- (NSPredicate *)currentPredicate {
    CPProcurementFilterSegment seg = (CPProcurementFilterSegment)_filterSegment.selectedSegmentIndex;
    switch (seg) {
        case CPProcurementFilterOpen:
            // Open = any stage before Closed
            return [NSPredicate predicateWithFormat:@"stage != %@", @"Closed"];

        case CPProcurementFilterVarianceFlagged:
            // Read varianceFlag from the Invoice entity related to this case.
            return [NSPredicate predicateWithFormat:@"ANY invoices.varianceFlag == YES"];

        case CPProcurementFilterPendingReview:
            // Requisition stage awaiting approval
            return [NSPredicate predicateWithFormat:@"stage == %@ OR stage == %@",
                    @"Requisition", @"Reconciliation"];

        default:
            return nil;
    }
}

- (void)reloadFRC {
    _frc.fetchRequest.predicate = [self currentPredicate];
    NSError *err = nil;
    if (![_frc performFetch:&err]) {
        NSLog(@"[CPProcurementList] reloadFRC error: %@", err.localizedDescription);
    }
    [_tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    BOOL empty = _frc.fetchedObjects.count == 0;
    _emptyStateView.hidden = !empty;
    _tableView.hidden = empty;
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)filterChanged:(UISegmentedControl *)sender {
    [self reloadFRC];
}

- (void)handleRefresh:(UIRefreshControl *)sender {
    // Simulate a data sync
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sender endRefreshing];
        [self reloadFRC];
    });
}

- (void)addCaseTapped {
    // Create a draft case and immediately navigate to it
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    CPProcurementCase *newCase = [CPProcurementCase insertInContext:ctx];
    newCase.title = @"New Procurement Case";
    NSError *saveError = nil;
    if (ctx.hasChanges && ![ctx save:&saveError]) {
        NSLog(@"[CPProcurementList] Failed to create draft case: %@", saveError.localizedDescription);
        return;
    }

    NSLog(@"[CPProcurementList] Created draft case %@ (%@)", newCase.caseNumber ?: @"<no-case-number>", newCase.uuid ?: @"<no-uuid>");

    CPProcurementCaseViewController *vc = [CPProcurementCaseViewController new];
    vc.caseUUID = newCase.uuid;

    if (self.navigationController) {
        NSLog(@"[CPProcurementList] Pushing case detail for %@", vc.caseUUID ?: @"<nil>");
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    NSLog(@"[CPProcurementList] Missing navigationController, presenting case detail modally for %@", vc.caseUUID ?: @"<nil>");
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_frc.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_frc.sections[section].numberOfObjects;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPProcurementCell *cell = [tableView dequeueReusableCellWithIdentifier:kProcurementCellID
                                                              forIndexPath:indexPath];
    CPProcurementCase *procCase = [_frc objectAtIndexPath:indexPath];
    [cell configureWithCase:procCase];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CPProcurementCase *procCase = [_frc objectAtIndexPath:indexPath];
    CPProcurementCaseViewController *vc = [CPProcurementCaseViewController new];
    vc.caseUUID = procCase.uuid;
    [self.navigationController pushViewController:vc animated:YES];
}

// ---------------------------------------------------------------------------
#pragma mark - NSFetchedResultsControllerDelegate
// ---------------------------------------------------------------------------

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    [_tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {
    switch (type) {
        case NSFetchedResultsChangeInsert:
            [_tableView insertRowsAtIndexPaths:@[newIndexPath]
                             withRowAnimation:UITableViewRowAnimationAutomatic];
            break;
        case NSFetchedResultsChangeDelete:
            [_tableView deleteRowsAtIndexPaths:@[indexPath]
                             withRowAnimation:UITableViewRowAnimationAutomatic];
            break;
        case NSFetchedResultsChangeUpdate: {
            CPProcurementCell *cell = (CPProcurementCell *)[_tableView cellForRowAtIndexPath:indexPath];
            if (cell) [cell configureWithCase:(CPProcurementCase *)anObject];
            break;
        }
        case NSFetchedResultsChangeMove:
            [_tableView moveRowAtIndexPath:indexPath toIndexPath:newIndexPath];
            break;
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [_tableView endUpdates];
    [self updateEmptyState];
}

@end
