#import "CPVendorListViewController.h"
#import "CPVendorDetailViewController.h"
#import "CPCoreDataStack.h"
#import "CPRBACService.h"
#import "CPVendor+CoreDataClass.h"
#import "CPVendor+CoreDataProperties.h"
#import <CoreData/CoreData.h>

static NSString * const kVendorCellIdentifier = @"CPVendorCell";

// ---------------------------------------------------------------------------
#pragma mark - Badge label helper
// ---------------------------------------------------------------------------

@interface CPStatusBadgeLabel : UILabel
- (void)configureAsActive:(BOOL)active;
@end

@implementation CPStatusBadgeLabel

- (instancetype)init {
    self = [super init];
    if (self) {
        self.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        self.textAlignment = NSTextAlignmentCenter;
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)configureAsActive:(BOOL)active {
    if (active) {
        self.text = @"Active";
        self.backgroundColor = [UIColor systemGreenColor];
        self.textColor = [UIColor whiteColor];
    } else {
        self.text = @"Inactive";
        self.backgroundColor = [UIColor systemGrayColor];
        self.textColor = [UIColor whiteColor];
    }
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Vendor table view cell
// ---------------------------------------------------------------------------

@interface CPVendorCell : UITableViewCell
@property (nonatomic, strong) UILabel *vendorNameLabel;
@property (nonatomic, strong) UILabel *contactNameLabel;
@property (nonatomic, strong) CPStatusBadgeLabel *statusBadge;
- (void)configureWithVendor:(CPVendor *)vendor;
@end

@implementation CPVendorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self _buildUI];
    }
    return self;
}

- (void)_buildUI {
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    _vendorNameLabel = [[UILabel alloc] init];
    _vendorNameLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    _vendorNameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _contactNameLabel = [[UILabel alloc] init];
    _contactNameLabel.font = [UIFont systemFontOfSize:13.0];
    _contactNameLabel.textColor = [UIColor secondaryLabelColor];
    _contactNameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _statusBadge = [[CPStatusBadgeLabel alloc] init];

    [self.contentView addSubview:_vendorNameLabel];
    [self.contentView addSubview:_contactNameLabel];
    [self.contentView addSubview:_statusBadge];

    [NSLayoutConstraint activateConstraints:@[
        [_vendorNameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],
        [_vendorNameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [_vendorNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusBadge.leadingAnchor constant:-8.0],

        [_contactNameLabel.topAnchor constraintEqualToAnchor:_vendorNameLabel.bottomAnchor constant:3.0],
        [_contactNameLabel.leadingAnchor constraintEqualToAnchor:_vendorNameLabel.leadingAnchor],
        [_contactNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusBadge.leadingAnchor constant:-8.0],
        [_contactNameLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],

        [_statusBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_statusBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [_statusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:60.0],
        [_statusBadge.heightAnchor constraintEqualToConstant:20.0],
    ]];
}

- (void)configureWithVendor:(CPVendor *)vendor {
    _vendorNameLabel.text = vendor.name ?: @"Unnamed Vendor";
    _contactNameLabel.text = vendor.contactName.length ? vendor.contactName : @"No contact";
    [_statusBadge configureAsActive:[vendor.isActive boolValue]];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Empty state view
// ---------------------------------------------------------------------------

@interface CPVendorEmptyView : UIView
- (void)setSearchActive:(BOOL)searching;
@end

@implementation CPVendorEmptyView {
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"building.2"]];
        _iconView.tintColor = [UIColor tertiaryLabelColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightMedium];
        _titleLabel.textColor = [UIColor secondaryLabelColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:14.0];
        _subtitleLabel.textColor = [UIColor tertiaryLabelColor];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.numberOfLines = 0;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_iconView];
        [self addSubview:_titleLabel];
        [self addSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-40.0],
            [_iconView.widthAnchor constraintEqualToConstant:60.0],
            [_iconView.heightAnchor constraintEqualToConstant:60.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:16.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32.0],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32.0],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32.0],
        ]];

        [self setSearchActive:NO];
    }
    return self;
}

- (void)setSearchActive:(BOOL)searching {
    if (searching) {
        _titleLabel.text = @"No Results";
        _subtitleLabel.text = @"Try a different vendor name.";
    } else {
        _titleLabel.text = @"No Vendors";
        _subtitleLabel.text = @"Add a vendor to get started.";
    }
}

@end

// ---------------------------------------------------------------------------
#pragma mark - View controller
// ---------------------------------------------------------------------------

@interface CPVendorListViewController () <UITableViewDelegate, UITableViewDataSource,
                                          NSFetchedResultsControllerDelegate,
                                          UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) CPVendorEmptyView *emptyView;
@property (nonatomic, copy) NSString *activeSearchText;
@end

@implementation CPVendorListViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Vendors";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self _buildTableView];
    [self _buildSearchController];
    [self _buildEmptyView];
    [self _buildNavigationItems];
    [self _setupFetchedResultsController];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.tableView.indexPathForSelectedRow) {
        [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:animated];
    }
    // Re-fetch in case a detail edit changed active status
    [self _performFetch];
}

// ---------------------------------------------------------------------------
#pragma mark - UI Construction
// ---------------------------------------------------------------------------

- (void)_buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60.0;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [_tableView registerClass:[CPVendorCell class] forCellReuseIdentifier:kVendorCellIdentifier];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(_handleRefresh:) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;
}

- (void)_buildSearchController {
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.delegate = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Search vendors";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
}

- (void)_buildEmptyView {
    _emptyView = [[CPVendorEmptyView alloc] init];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    [self.view addSubview:_emptyView];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_emptyView.heightAnchor constraintEqualToConstant:300.0],
    ]];
}

- (void)_buildNavigationItems {
    BOOL isAdmin = [[CPRBACService sharedService] currentUserCanPerform:CPActionCreate onResource:CPResourceUser];
    if (isAdmin) {
        UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                   target:self
                                                                                   action:@selector(_handleAddVendor)];
        self.navigationItem.rightBarButtonItem = addButton;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Core Data
// ---------------------------------------------------------------------------

- (void)_setupFetchedResultsController {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [CPVendor fetchRequest];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                                               selector:@selector(localizedCaseInsensitiveCompare:)]];
    _fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                                    managedObjectContext:context
                                                                      sectionNameKeyPath:nil
                                                                               cacheName:nil];
    _fetchedResultsController.delegate = self;
    [self _performFetch];
}

- (void)_performFetch {
    NSFetchRequest *request = _fetchedResultsController.fetchRequest;

    if (_activeSearchText.length > 0) {
        request.predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", _activeSearchText];
    } else {
        request.predicate = nil;
    }

    NSError *error = nil;
    if (![_fetchedResultsController performFetch:&error]) {
        NSLog(@"[CPVendorList] Fetch error: %@", error.localizedDescription);
    }
    [self _updateEmptyState];
    [_tableView reloadData];
    [_refreshControl endRefreshing];
}

- (void)_updateEmptyState {
    NSInteger count = [_fetchedResultsController.sections.firstObject numberOfObjects];
    BOOL isEmpty = count == 0;
    _emptyView.hidden = !isEmpty;
    _tableView.separatorStyle = isEmpty ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
    [_emptyView setSearchActive:(_activeSearchText.length > 0)];
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)_handleAddVendor {
    CPVendorDetailViewController *vc = [[CPVendorDetailViewController alloc] init];
    vc.vendorUUID = nil; // new vendor
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)_handleRefresh:(UIRefreshControl *)sender {
    [self _performFetch];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_fetchedResultsController.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id<NSFetchedResultsSectionInfo> sectionInfo = _fetchedResultsController.sections[section];
    return (NSInteger)sectionInfo.numberOfObjects;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPVendorCell *cell = [tableView dequeueReusableCellWithIdentifier:kVendorCellIdentifier
                                                         forIndexPath:indexPath];
    CPVendor *vendor = [_fetchedResultsController objectAtIndexPath:indexPath];
    [cell configureWithVendor:vendor];
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CPVendor *vendor = [_fetchedResultsController objectAtIndexPath:indexPath];
    CPVendorDetailViewController *vc = [[CPVendorDetailViewController alloc] init];
    vc.vendorUUID = vendor.uuid;
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
       atIndexPath:(nullable NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(nullable NSIndexPath *)newIndexPath {
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
            CPVendorCell *cell = (CPVendorCell *)[_tableView cellForRowAtIndexPath:indexPath];
            if (cell) {
                CPVendor *vendor = [controller objectAtIndexPath:indexPath];
                [cell configureWithVendor:vendor];
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
    [self _updateEmptyState];
}

// ---------------------------------------------------------------------------
#pragma mark - UISearchResultsUpdating
// ---------------------------------------------------------------------------

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    _activeSearchText = text.length > 0 ? text : nil;
    [self _performFetch];
}

// ---------------------------------------------------------------------------
#pragma mark - UISearchControllerDelegate
// ---------------------------------------------------------------------------

- (void)didDismissSearchController:(UISearchController *)searchController {
    _activeSearchText = nil;
    [self _performFetch];
}

@end
