// CPChargerListViewController.m
// ChargeProcure
//
// Displays a filterable, searchable list of chargers backed by NSFetchedResultsController.

#import "CPChargerListViewController.h"
#import "CPChargerDetailViewController.h"
#import "CPCharger+CoreDataClass.h"
#import "CPCharger+CoreDataProperties.h"
#import "CPChargerService.h"
#import "CPCoreDataStack.h"
#import "CPDateFormatter.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// MARK: - Cell
// ---------------------------------------------------------------------------

@interface CPChargerCell : UITableViewCell
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UILabel *serialLabel;
@property (nonatomic, strong) UILabel *locationLabel;
@property (nonatomic, strong) UIView  *statusBadge;
@property (nonatomic, strong) UILabel *statusLabel;
- (void)configureWithCharger:(CPCharger *)charger;
@end

@implementation CPChargerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self buildLayout];
    }
    return self;
}

- (void)buildLayout {
    _modelLabel    = [UILabel new];
    _serialLabel   = [UILabel new];
    _locationLabel = [UILabel new];
    _statusBadge   = [UIView new];
    _statusLabel   = [UILabel new];

    _modelLabel.font    = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _serialLabel.font   = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _serialLabel.textColor = UIColor.secondaryLabelColor;
    _locationLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _locationLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.font   = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusLabel.textColor = UIColor.whiteColor;
    _statusLabel.textAlignment = NSTextAlignmentCenter;

    _statusBadge.layer.cornerRadius = 8;
    _statusBadge.clipsToBounds = YES;
    _statusBadge.isAccessibilityElement = YES;
    _statusBadge.accessibilityTraits = UIAccessibilityTraitStaticText;

    [_statusBadge addSubview:_statusLabel];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.centerXAnchor constraintEqualToAnchor:_statusBadge.centerXAnchor],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:_statusBadge.centerYAnchor],
    ]];

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_modelLabel, _serialLabel, _locationLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[textStack, _statusBadge]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    [self.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_statusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:72],
        [_statusBadge.heightAnchor constraintEqualToConstant:24],
    ]];
}

- (void)configureWithCharger:(CPCharger *)charger {
    _modelLabel.text    = charger.model ?: @"Unknown Model";
    _serialLabel.text   = [NSString stringWithFormat:@"SN: %@", charger.serialNumber ?: @"—"];
    _locationLabel.text = charger.location ?: @"No location";

    CPChargerStatus status = [charger chargerStatus];
    NSString *statusText = [CPChargerCell statusStringForStatus:status];
    UIColor  *badgeColor = [CPChargerCell badgeColorForStatus:status];

    _statusLabel.text = statusText;
    _statusBadge.backgroundColor = badgeColor;
    _statusBadge.accessibilityLabel = [NSString stringWithFormat:@"Status: %@", statusText];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, serial %@, %@, status %@",
                               charger.model ?: @"Unknown",
                               charger.serialNumber ?: @"unknown",
                               charger.location ?: @"no location",
                               statusText];
}

+ (NSString *)statusStringForStatus:(CPChargerStatus)status {
    switch (status) {
        case CPChargerStatusOnline:   return @"Online";
        case CPChargerStatusCharging: return @"Charging";
        case CPChargerStatusIdle:     return @"Idle";
        case CPChargerStatusFault:    return @"Fault";
        case CPChargerStatusOffline:  return @"Offline";
        default:                      return @"Unknown";
    }
}

+ (UIColor *)badgeColorForStatus:(CPChargerStatus)status {
    switch (status) {
        case CPChargerStatusOnline:   return [UIColor systemGreenColor];
        case CPChargerStatusCharging: return [UIColor systemBlueColor];
        case CPChargerStatusIdle:     return [UIColor systemYellowColor];
        case CPChargerStatusFault:    return [UIColor systemRedColor];
        case CPChargerStatusOffline:  return [UIColor systemGrayColor];
        default:                      return [UIColor systemGrayColor];
    }
}

@end

// ---------------------------------------------------------------------------
// MARK: - Status filter index
// ---------------------------------------------------------------------------
// Segment indices map to: 0=All, 1=Online, 2=Fault, 3=Offline
typedef NS_ENUM(NSInteger, CPChargerFilterSegment) {
    CPChargerFilterAll = 0,
    CPChargerFilterOnline,
    CPChargerFilterFault,
    CPChargerFilterOffline,
};

// ---------------------------------------------------------------------------
// MARK: - View Controller
// ---------------------------------------------------------------------------

static NSString * const kChargerCellID = @"CPChargerCell";

@interface CPChargerListViewController () <UITableViewDelegate, UITableViewDataSource,
                                            NSFetchedResultsControllerDelegate,
                                            UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong) UITableView                *tableView;
@property (nonatomic, strong) UISearchController         *searchController;
@property (nonatomic, strong) UISegmentedControl         *filterSegment;
@property (nonatomic, strong) UIRefreshControl           *refreshControl;
@property (nonatomic, strong) UIView                     *emptyStateView;
@property (nonatomic, strong) UILabel                    *emptyStateLabel;
@property (nonatomic, strong) NSFetchedResultsController *frc;
@end

@implementation CPChargerListViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chargers";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self buildFilterSegment];
    [self buildSearchController];
    [self buildTableView];
    [self buildEmptyState];
    [self buildFRC];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.tableView.indexPathForSelectedRow) {
        [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:animated];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - UI Construction
// ---------------------------------------------------------------------------

- (void)buildFilterSegment {
    _filterSegment = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Online", @"Fault", @"Offline"]];
    _filterSegment.selectedSegmentIndex = 0;
    [_filterSegment addTarget:self action:@selector(filterSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    _filterSegment.accessibilityLabel = @"Filter chargers by status";

    UIBarButtonItem *segItem = [[UIBarButtonItem alloc] initWithCustomView:_filterSegment];
    self.navigationItem.rightBarButtonItem = segItem;
}

- (void)buildSearchController {
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.delegate = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Search by serial or location";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
}

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 72;
    [_tableView registerClass:[CPChargerCell class] forCellReuseIdentifier:kChargerCellID];

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

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.slash.circle"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = UIColor.systemGrayColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    _emptyStateLabel = [UILabel new];
    _emptyStateLabel.text = @"No chargers found";
    _emptyStateLabel.textColor = UIColor.secondaryLabelColor;
    _emptyStateLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
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
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [CPCharger fetchRequest];
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"status" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"model"  ascending:YES],
    ];
    req.predicate = [self currentPredicate];

    _frc = [[NSFetchedResultsController alloc] initWithFetchRequest:req
                                               managedObjectContext:context
                                                 sectionNameKeyPath:nil
                                                          cacheName:nil];
    _frc.delegate = self;

    NSError *error = nil;
    if (![_frc performFetch:&error]) {
        NSLog(@"[CPChargerList] FRC performFetch error: %@", error.localizedDescription);
    }
    [self updateEmptyState];
}

- (NSPredicate *)currentPredicate {
    NSMutableArray *subPredicates = [NSMutableArray array];

    // Status filter
    CPChargerFilterSegment seg = (CPChargerFilterSegment)_filterSegment.selectedSegmentIndex;
    if (seg == CPChargerFilterOnline) {
        [subPredicates addObject:[NSPredicate predicateWithFormat:@"status ==[cd] 'Online'"]];
    } else if (seg == CPChargerFilterFault) {
        [subPredicates addObject:[NSPredicate predicateWithFormat:@"status ==[cd] 'Fault'"]];
    } else if (seg == CPChargerFilterOffline) {
        [subPredicates addObject:[NSPredicate predicateWithFormat:@"status ==[cd] 'Offline' OR status == nil"]];
    }

    // Search filter
    NSString *searchText = _searchController.searchBar.text;
    if (searchText.length > 0) {
        NSPredicate *serialPred   = [NSPredicate predicateWithFormat:@"serialNumber CONTAINS[cd] %@", searchText];
        NSPredicate *locationPred = [NSPredicate predicateWithFormat:@"location CONTAINS[cd] %@", searchText];
        [subPredicates addObject:[NSCompoundPredicate orPredicateWithSubpredicates:@[serialPred, locationPred]]];
    }

    if (subPredicates.count == 0) {
        return nil;
    }
    if (subPredicates.count == 1) {
        return subPredicates.firstObject;
    }
    return [NSCompoundPredicate andPredicateWithSubpredicates:subPredicates];
}

- (void)reloadFRCPredicate {
    _frc.fetchRequest.predicate = [self currentPredicate];
    NSError *error = nil;
    if (![_frc performFetch:&error]) {
        NSLog(@"[CPChargerList] reloadFRCPredicate error: %@", error.localizedDescription);
    }
    [_tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    NSInteger count = _frc.fetchedObjects.count;
    _emptyStateView.hidden = (count > 0);
    _tableView.hidden = (count == 0);

    if (count == 0) {
        NSString *searchText = _searchController.searchBar.text;
        _emptyStateLabel.text = (searchText.length > 0)
            ? [NSString stringWithFormat:@"No chargers matching \"%@\"", searchText]
            : @"No chargers found";
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)filterSegmentChanged:(UISegmentedControl *)sender {
    [self reloadFRCPredicate];
}

- (void)handleRefresh:(UIRefreshControl *)sender {
    // Simulate status updates via CPChargerService for each charger
    NSArray *chargers = _frc.fetchedObjects;
    dispatch_group_t group = dispatch_group_create();

    for (CPCharger *charger in chargers) {
        if (!charger.uuid) continue;
        dispatch_group_enter(group);
        // Simulate a status update — in production this would poll the vendor SDK
        NSArray *statuses = @[@"Online", @"Offline", @"Charging", @"Idle", @"Fault"];
        NSString *simStatus = statuses[arc4random_uniform((uint32_t)statuses.count)];
        [[CPChargerService sharedService] updateCharger:charger.uuid
                                                 status:simStatus
                                                 detail:@"Simulated status refresh"];
        dispatch_group_leave(group);
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [sender endRefreshing];
        [self->_tableView reloadData];
        [self updateEmptyState];
    });
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_frc.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id<NSFetchedResultsSectionInfo> sectionInfo = _frc.sections[section];
    return (NSInteger)sectionInfo.numberOfObjects;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPChargerCell *cell = [tableView dequeueReusableCellWithIdentifier:kChargerCellID forIndexPath:indexPath];
    CPCharger *charger = [_frc objectAtIndexPath:indexPath];
    [cell configureWithCharger:charger];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CPCharger *charger = [_frc objectAtIndexPath:indexPath];
    CPChargerDetailViewController *detail = [CPChargerDetailViewController new];
    detail.chargerUUID = charger.uuid;
    [self.navigationController pushViewController:detail animated:YES];
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
            CPChargerCell *cell = (CPChargerCell *)[_tableView cellForRowAtIndexPath:indexPath];
            if (cell) {
                [cell configureWithCharger:(CPCharger *)anObject];
            }
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

// ---------------------------------------------------------------------------
#pragma mark - UISearchResultsUpdating
// ---------------------------------------------------------------------------

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reloadFRCPredicate];
}

@end
