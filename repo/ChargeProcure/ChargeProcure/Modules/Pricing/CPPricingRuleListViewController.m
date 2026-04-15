#import "CPPricingRuleListViewController.h"
#import <CoreData/CoreData.h>
#import "CPPricingRuleDetailViewController.h"

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
@class CPPricingService;
@class CPAuthService;

@interface CPPricingService : NSObject
+ (instancetype)sharedService;
- (NSManagedObjectContext *)mainContext;
@end

@interface CPAuthService : NSObject
+ (instancetype)sharedService;
- (BOOL)currentUserHasPermission:(NSString *)permission;
@end

// ---------------------------------------------------------------------------
// Cell
// ---------------------------------------------------------------------------
@interface CPPricingRuleCell : UITableViewCell
@property (nonatomic, strong) UILabel *serviceTypeLabel;
@property (nonatomic, strong) UILabel *scopeLabel;
@property (nonatomic, strong) UILabel *basePriceLabel;
@property (nonatomic, strong) UILabel *dateRangeLabel;
@property (nonatomic, strong) UILabel *versionBadge;
@end

@implementation CPPricingRuleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.serviceTypeLabel = [UILabel new];
    self.serviceTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.serviceTypeLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.contentView addSubview:self.serviceTypeLabel];

    self.versionBadge = [UILabel new];
    self.versionBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.versionBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.versionBadge.textColor = [UIColor systemBlueColor];
    self.versionBadge.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.1];
    self.versionBadge.layer.cornerRadius = 6;
    self.versionBadge.layer.masksToBounds = YES;
    [self.contentView addSubview:self.versionBadge];

    self.scopeLabel = [UILabel new];
    self.scopeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.scopeLabel.font = [UIFont systemFontOfSize:13];
    self.scopeLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.scopeLabel];

    self.basePriceLabel = [UILabel new];
    self.basePriceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.basePriceLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    self.basePriceLabel.textColor = [UIColor systemGreenColor];
    [self.contentView addSubview:self.basePriceLabel];

    self.dateRangeLabel = [UILabel new];
    self.dateRangeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dateRangeLabel.font = [UIFont systemFontOfSize:11];
    self.dateRangeLabel.textColor = [UIColor tertiaryLabelColor];
    [self.contentView addSubview:self.dateRangeLabel];

    const CGFloat p = 12;
    [NSLayoutConstraint activateConstraints:@[
        [self.serviceTypeLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:p],
        [self.serviceTypeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.serviceTypeLabel.trailingAnchor constraintEqualToAnchor:self.versionBadge.leadingAnchor constant:-8],

        [self.versionBadge.centerYAnchor constraintEqualToAnchor:self.serviceTypeLabel.centerYAnchor],
        [self.versionBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],

        [self.scopeLabel.topAnchor constraintEqualToAnchor:self.serviceTypeLabel.bottomAnchor constant:4],
        [self.scopeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.scopeLabel.trailingAnchor constraintEqualToAnchor:self.basePriceLabel.leadingAnchor constant:-8],

        [self.basePriceLabel.centerYAnchor constraintEqualToAnchor:self.scopeLabel.centerYAnchor],
        [self.basePriceLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],

        [self.dateRangeLabel.topAnchor constraintEqualToAnchor:self.scopeLabel.bottomAnchor constant:4],
        [self.dateRangeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.dateRangeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [self.dateRangeLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-p],
    ]];
    return self;
}

@end

// ---------------------------------------------------------------------------
// Main View Controller
// ---------------------------------------------------------------------------
@interface CPPricingRuleListViewController () <UITableViewDelegate, UITableViewDataSource, NSFetchedResultsControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIBarButtonItem *filterToggleButton;
@property (nonatomic, strong) NSFetchedResultsController *frc;
@property (nonatomic, assign) BOOL showActiveOnly;
@property (nonatomic, strong) NSArray<NSString *> *sectionServiceTypes;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation CPPricingRuleListViewController

static NSString * const kCellID = @"CPPricingRuleCell";

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Pricing Rules";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // Read-side authorization check — pricing rules are admin-only.
    if (![[CPAuthService sharedService] currentUserHasPermission:@"admin"]) {
        UIAlertController *denied = [UIAlertController
            alertControllerWithTitle:@"Access Denied"
            message:@"You do not have permission to view pricing rules."
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

    self.showActiveOnly = NO;

    self.dateFormatter = [NSDateFormatter new];
    self.dateFormatter.dateStyle = NSDateFormatterShortStyle;
    self.dateFormatter.timeStyle = NSDateFormatterNoStyle;

    [self setupTableView];
    [self setupNavigationBar];
    [self setupFRC];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[CPPricingRuleCell class] forCellReuseIdentifier:kCellID];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupNavigationBar {
    NSMutableArray *items = [NSMutableArray array];
    BOOL isAdmin = [[CPAuthService sharedService] currentUserHasPermission:@"admin"];
    if (isAdmin) {
        UIBarButtonItem *addBtn = [[UIBarButtonItem alloc]
            initWithImage:[UIImage systemImageNamed:@"plus"]
                    style:UIBarButtonItemStylePlain
                   target:self action:@selector(addRule)];
        [items addObject:addBtn];
    }
    self.filterToggleButton = [[UIBarButtonItem alloc]
        initWithTitle:@"Active Only"
                style:UIBarButtonItemStylePlain
               target:self action:@selector(toggleFilter)];
    [items addObject:self.filterToggleButton];
    self.navigationItem.rightBarButtonItems = items;
}

- (void)setupFRC {
    NSManagedObjectContext *ctx = [[CPPricingService sharedService] mainContext];
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];
    req.predicate = [self currentPredicate];
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"serviceType" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"effectiveStart" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO],
    ];
    self.frc = [[NSFetchedResultsController alloc]
        initWithFetchRequest:req
        managedObjectContext:ctx
        sectionNameKeyPath:@"serviceType"
        cacheName:nil];
    self.frc.delegate = self;
    NSError *err;
    [self.frc performFetch:&err];
    if (err) NSLog(@"[CPPricingRuleList] FRC fetch error: %@", err);
}

- (NSPredicate *)currentPredicate {
    if (self.showActiveOnly) {
        NSDate *now = [NSDate date];
        return [NSPredicate predicateWithFormat:
            @"effectiveStart <= %@ AND (effectiveEnd == nil OR effectiveEnd >= %@)",
            now, now];
    }
    return nil;
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)addRule {
    CPPricingRuleDetailViewController *detail = [CPPricingRuleDetailViewController new];
    detail.ruleUUID = nil;
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)toggleFilter {
    self.showActiveOnly = !self.showActiveOnly;
    self.filterToggleButton.title = self.showActiveOnly ? @"Show All" : @"Active Only";
    self.frc.fetchRequest.predicate = [self currentPredicate];
    NSError *err;
    [self.frc performFetch:&err];
    [self.tableView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.frc.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id<NSFetchedResultsSectionInfo> sec = self.frc.sections[section];
    return (NSInteger)sec.numberOfObjects;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    id<NSFetchedResultsSectionInfo> sec = self.frc.sections[section];
    return sec.name ?: @"Unknown Service";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPPricingRuleCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    NSManagedObject *rule = [self.frc objectAtIndexPath:indexPath];

    cell.serviceTypeLabel.text = [rule valueForKey:@"serviceType"] ?: @"—";

    NSMutableArray *scopeParts = [NSMutableArray array];
    NSString *vehicleClass = [rule valueForKey:@"vehicleClass"];
    NSString *storeID = [rule valueForKey:@"storeID"];
    if (vehicleClass.length > 0) [scopeParts addObject:[NSString stringWithFormat:@"Class: %@", vehicleClass]];
    if (storeID.length > 0) [scopeParts addObject:[NSString stringWithFormat:@"Store: %@", storeID]];
    cell.scopeLabel.text = scopeParts.count > 0 ? [scopeParts componentsJoinedByString:@" · "] : @"Global scope";

    NSDecimalNumber *price = [rule valueForKey:@"basePrice"];
    cell.basePriceLabel.text = price ? [NSString stringWithFormat:@"$%.2f", price.doubleValue] : @"$—";

    NSDate *start = [rule valueForKey:@"effectiveStart"];
    NSDate *end = [rule valueForKey:@"effectiveEnd"];
    NSString *startStr = start ? [self.dateFormatter stringFromDate:start] : @"?";
    NSString *endStr = end ? [self.dateFormatter stringFromDate:end] : @"∞";
    cell.dateRangeLabel.text = [NSString stringWithFormat:@"%@ – %@", startStr, endStr];

    NSNumber *version = [rule valueForKey:@"version"];
    cell.versionBadge.text = [NSString stringWithFormat:@" v%@ ", version ?: @"1"];

    // Strikethrough for inactive
    BOOL isActive = [self ruleIsActive:rule];
    if (!isActive) {
        NSDictionary *strikeAttrs = @{NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)};
        cell.serviceTypeLabel.attributedText = [[NSAttributedString alloc]
            initWithString:cell.serviceTypeLabel.text attributes:strikeAttrs];
        cell.contentView.alpha = 0.5;
    } else {
        cell.serviceTypeLabel.attributedText = nil;
        cell.serviceTypeLabel.text = [rule valueForKey:@"serviceType"] ?: @"—";
        cell.contentView.alpha = 1.0;
    }

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (BOOL)ruleIsActive:(NSManagedObject *)rule {
    NSDate *now = [NSDate date];
    NSDate *start = [rule valueForKey:@"effectiveStart"];
    NSDate *end = [rule valueForKey:@"effectiveEnd"];
    if (start && [start compare:now] == NSOrderedDescending) return NO;
    if (end && [end compare:now] == NSOrderedAscending) return NO;
    return YES;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSManagedObject *rule = [self.frc objectAtIndexPath:indexPath];
    CPPricingRuleDetailViewController *detail = [CPPricingRuleDetailViewController new];
    detail.ruleUUID = [rule valueForKey:@"uuid"];
    [self.navigationController pushViewController:detail animated:YES];
}

// ---------------------------------------------------------------------------
#pragma mark - NSFetchedResultsControllerDelegate
// ---------------------------------------------------------------------------

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {
    switch (type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
        case NSFetchedResultsChangeMove:
            [self.tableView moveRowAtIndexPath:indexPath toIndexPath:newIndexPath];
            break;
        case NSFetchedResultsChangeUpdate:
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            break;
    }
}

- (void)controller:(NSFetchedResultsController *)controller
  didChangeSection:(id<NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type {
    switch (type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
        default: break;
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
}

@end
