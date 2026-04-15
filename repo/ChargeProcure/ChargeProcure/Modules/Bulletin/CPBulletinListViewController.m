#import "CPBulletinListViewController.h"
#import <CoreData/CoreData.h>
#import "CPBulletinDetailViewController.h"
#import "CPBulletinEditorViewController.h"
#import "CPBulletinService.h"
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPBulletin+CoreDataClass.h"

// ---------------------------------------------------------------------------
// Cell
// ---------------------------------------------------------------------------

@interface CPBulletinCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *statusBadgeLabel;
@property (nonatomic, strong) UILabel *weightLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *pinImageView;
@end

@implementation CPBulletinCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.pinImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pin.fill"]];
    self.pinImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.pinImageView.tintColor = [UIColor systemOrangeColor];
    self.pinImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.pinImageView];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.numberOfLines = 1;
    [self.contentView addSubview:self.titleLabel];

    self.statusBadgeLabel = [UILabel new];
    self.statusBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBadgeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.statusBadgeLabel.layer.cornerRadius = 6;
    self.statusBadgeLabel.layer.masksToBounds = YES;
    self.statusBadgeLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.statusBadgeLabel];

    self.summaryLabel = [UILabel new];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.font = [UIFont systemFontOfSize:13];
    self.summaryLabel.textColor = [UIColor secondaryLabelColor];
    self.summaryLabel.numberOfLines = 2;
    [self.contentView addSubview:self.summaryLabel];

    self.weightLabel = [UILabel new];
    self.weightLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.weightLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.weightLabel.textColor = [UIColor tertiaryLabelColor];
    [self.contentView addSubview:self.weightLabel];

    self.dateLabel = [UILabel new];
    self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dateLabel.font = [UIFont systemFontOfSize:11];
    self.dateLabel.textColor = [UIColor tertiaryLabelColor];
    self.dateLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.dateLabel];

    const CGFloat pad = 12;
    const CGFloat pinW = 14;
    [NSLayoutConstraint activateConstraints:@[
        [self.pinImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.pinImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad],
        [self.pinImageView.widthAnchor constraintEqualToConstant:pinW],
        [self.pinImageView.heightAnchor constraintEqualToConstant:pinW],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.pinImageView.trailingAnchor constant:6],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.statusBadgeLabel.leadingAnchor constant:-8],

        [self.statusBadgeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.statusBadgeLabel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.statusBadgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:60],

        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],

        [self.weightLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.weightLabel.topAnchor constraintEqualToAnchor:self.summaryLabel.bottomAnchor constant:4],
        [self.weightLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-pad],

        [self.dateLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.dateLabel.centerYAnchor constraintEqualToAnchor:self.weightLabel.centerYAnchor],
    ]];

    return self;
}

- (void)configureBadgeWithStatus:(NSString *)status {
    NSDictionary *map = @{
        @"published": @[@"Published", [UIColor systemGreenColor]],
        @"draft":     @[@"Draft",     [UIColor systemGrayColor]],
        @"archived":  @[@"Archived",  [UIColor systemOrangeColor]],
    };
    NSArray *info = map[status.lowercaseString] ?: @[status, [UIColor systemBlueColor]];
    self.statusBadgeLabel.text = [NSString stringWithFormat:@" %@ ", info[0]];
    self.statusBadgeLabel.backgroundColor = [info[1] colorWithAlphaComponent:0.15];
    self.statusBadgeLabel.textColor = info[1];
}

@end

// ---------------------------------------------------------------------------
// Main View Controller
// ---------------------------------------------------------------------------

@interface CPBulletinListViewController () <UITableViewDelegate, UITableViewDataSource, NSFetchedResultsControllerDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSFetchedResultsController *frc;
@property (nonatomic, strong) NSString *currentFilter; // "all", "published", "draft", "archived"
@property (nonatomic, assign) BOOL canCreate;
@end

@implementation CPBulletinListViewController

static NSString * const kCellID = @"CPBulletinCell";

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Bulletins";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.currentFilter = @"all";
    self.canCreate = [[CPAuthService sharedService] currentUserHasPermission:@"bulletin.create"];

    [self setupSegmentedControl];
    [self setupTableView];
    [self setupEmptyLabel];
    [self setupNavigationBar];
    [self setupFRC];
}

- (void)setupSegmentedControl {
    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Published", @"Drafts", @"Archived"]];
    self.filterSegment.selectedSegmentIndex = 0;
    [self.filterSegment addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.filterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.filterSegment];

    [NSLayoutConstraint activateConstraints:@[
        [self.filterSegment.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.filterSegment.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.filterSegment.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
    [self.tableView registerClass:[CPBulletinCell class] forCellReuseIdentifier:kCellID];
    [self.view addSubview:self.tableView];

    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(handleRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.filterSegment.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupEmptyLabel {
    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"No bulletins found";
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:16];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)setupNavigationBar {
    if (self.canCreate) {
        UIBarButtonItem *addBtn = [[UIBarButtonItem alloc]
            initWithImage:[UIImage systemImageNamed:@"square.and.pencil"]
                    style:UIBarButtonItemStylePlain
                   target:self
                   action:@selector(addBulletin)];
        self.navigationItem.rightBarButtonItem = addBtn;
    }
}

- (void)setupFRC {
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
    req.predicate = [self predicateForCurrentFilter];
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"isPinned" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"recommendationWeight" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO],
    ];
    self.frc = [[NSFetchedResultsController alloc]
        initWithFetchRequest:req
        managedObjectContext:ctx
        sectionNameKeyPath:nil
        cacheName:nil];
    self.frc.delegate = self;
    NSError *err;
    [self.frc performFetch:&err];
    if (err) NSLog(@"[CPBulletinList] FRC fetch error: %@", err);
    [self updateEmptyState];
}

- (NSPredicate *)predicateForCurrentFilter {
    if ([self.currentFilter isEqualToString:@"all"]) return nil;
    NSDictionary *map = @{
        @"published": @(CPBulletinStatusPublished),
        @"draft":     @(CPBulletinStatusDraft),
        @"archived":  @(CPBulletinStatusArchived),
    };
    NSNumber *val = map[self.currentFilter];
    if (!val) return nil;
    return [NSPredicate predicateWithFormat:@"statusValue == %@", val];
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)segmentChanged:(UISegmentedControl *)sender {
    NSArray *keys = @[@"all", @"published", @"draft", @"archived"];
    self.currentFilter = keys[sender.selectedSegmentIndex];
    self.frc.fetchRequest.predicate = [self predicateForCurrentFilter];
    NSError *err;
    [self.frc performFetch:&err];
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)addBulletin {
    CPBulletinEditorViewController *editor = [CPBulletinEditorViewController new];
    editor.bulletinUUID = nil; // new draft
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)handleRefresh {
    [[CPBulletinService sharedService] processScheduledBulletins];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.refreshControl endRefreshing];
    });
}

- (void)updateEmptyState {
    NSInteger count = self.frc.fetchedObjects.count;
    self.emptyLabel.hidden = (count > 0);
    self.tableView.hidden = (count == 0);
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPBulletinCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    NSManagedObject *bulletin = [self.frc objectAtIndexPath:indexPath];

    cell.titleLabel.text = [bulletin valueForKey:@"title"] ?: @"(Untitled)";
    cell.summaryLabel.text = [bulletin valueForKey:@"summary"];

    CPBulletinStatus statusEnum = (CPBulletinStatus)[[bulletin valueForKey:@"statusValue"] integerValue];
    NSString *statusStr;
    switch (statusEnum) {
        case CPBulletinStatusPublished:  statusStr = @"published";  break;
        case CPBulletinStatusScheduled:  statusStr = @"scheduled";  break;
        case CPBulletinStatusArchived:   statusStr = @"archived";   break;
        default:                         statusStr = @"draft";      break;
    }
    [cell configureBadgeWithStatus:statusStr];

    NSNumber *weight = [bulletin valueForKey:@"recommendationWeight"];
    cell.weightLabel.text = [NSString stringWithFormat:@"Weight: %@", weight ?: @"0"];

    NSDate *date = [bulletin valueForKey:@"createdAt"];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateStyle = NSDateFormatterShortStyle;
    df.timeStyle = NSDateFormatterNoStyle;
    cell.dateLabel.text = date ? [df stringFromDate:date] : @"";

    BOOL pinned = [[bulletin valueForKey:@"isPinned"] boolValue];
    cell.pinImageView.hidden = !pinned;

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSManagedObject *bulletin = [self.frc objectAtIndexPath:indexPath];
    NSString *uuid = [bulletin valueForKey:@"uuid"];
    CPBulletinStatus status = (CPBulletinStatus)[[bulletin valueForKey:@"statusValue"] integerValue];

    if (status == CPBulletinStatusPublished) {
        CPBulletinDetailViewController *detail = [CPBulletinDetailViewController new];
        detail.bulletinUUID = uuid;
        [self.navigationController pushViewController:detail animated:YES];
    } else {
        CPBulletinEditorViewController *editor = [CPBulletinEditorViewController new];
        editor.bulletinUUID = uuid;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {

    NSManagedObject *bulletin = [self.frc objectAtIndexPath:indexPath];

    UIContextualAction *editAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
        title:@"Edit"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            CPBulletinEditorViewController *editor = [CPBulletinEditorViewController new];
            editor.bulletinUUID = [bulletin valueForKey:@"uuid"];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
            [self presentViewController:nav animated:YES completion:nil];
            completionHandler(YES);
        }];
    editAction.backgroundColor = [UIColor systemBlueColor];

    return [UISwipeActionsConfiguration configurationWithActions:@[editAction]];
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

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
    [self updateEmptyState];
}

// ---------------------------------------------------------------------------
#pragma mark - UISearchResultsUpdating (optional hook)
// ---------------------------------------------------------------------------

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    NSPredicate *basePredicate = [self predicateForCurrentFilter];
    if (text.length > 0) {
        NSPredicate *search = [NSPredicate predicateWithFormat:@"title CONTAINS[cd] %@ OR summary CONTAINS[cd] %@", text, text];
        self.frc.fetchRequest.predicate = basePredicate
            ? [NSCompoundPredicate andPredicateWithSubpredicates:@[basePredicate, search]]
            : search;
    } else {
        self.frc.fetchRequest.predicate = basePredicate;
    }
    NSError *err;
    [self.frc performFetch:&err];
    [self.tableView reloadData];
    [self updateEmptyState];
}

@end
