#import "CPAuditLogViewController.h"
#import "CPAuditService.h"
#import "CPExportService.h"
#import "CPAuthService.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Audit log cell
// ---------------------------------------------------------------------------
@interface CPAuditLogCell : UITableViewCell
@property (nonatomic, strong) UILabel *actorLabel;
@property (nonatomic, strong) UILabel *actionLabel;
@property (nonatomic, strong) UILabel *resourceLabel;
@property (nonatomic, strong) UILabel *timestampLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@end

@implementation CPAuditLogCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    self.actorLabel = [UILabel new];
    self.actorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.actorLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.contentView addSubview:self.actorLabel];

    self.actionLabel = [UILabel new];
    self.actionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.actionLabel.textColor = [UIColor systemBlueColor];
    self.actionLabel.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.1];
    self.actionLabel.layer.cornerRadius = 4;
    self.actionLabel.layer.masksToBounds = YES;
    [self.contentView addSubview:self.actionLabel];

    self.resourceLabel = [UILabel new];
    self.resourceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.resourceLabel.font = [UIFont systemFontOfSize:13];
    self.resourceLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.resourceLabel];

    self.timestampLabel = [UILabel new];
    self.timestampLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.timestampLabel.font = [UIFont systemFontOfSize:11];
    self.timestampLabel.textColor = [UIColor tertiaryLabelColor];
    self.timestampLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.timestampLabel];

    self.detailLabel = [UILabel new];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.font = [UIFont systemFontOfSize:12];
    self.detailLabel.textColor = [UIColor secondaryLabelColor];
    self.detailLabel.numberOfLines = 2;
    [self.contentView addSubview:self.detailLabel];

    const CGFloat p = 12;
    [NSLayoutConstraint activateConstraints:@[
        [self.actorLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:p],
        [self.actorLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.actorLabel.trailingAnchor constraintEqualToAnchor:self.actionLabel.leadingAnchor constant:-8],

        [self.actionLabel.centerYAnchor constraintEqualToAnchor:self.actorLabel.centerYAnchor],
        [self.actionLabel.trailingAnchor constraintEqualToAnchor:self.timestampLabel.leadingAnchor constant:-8],

        [self.timestampLabel.centerYAnchor constraintEqualToAnchor:self.actorLabel.centerYAnchor],
        [self.timestampLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [self.timestampLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70],

        [self.resourceLabel.topAnchor constraintEqualToAnchor:self.actorLabel.bottomAnchor constant:4],
        [self.resourceLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.resourceLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],

        [self.detailLabel.topAnchor constraintEqualToAnchor:self.resourceLabel.bottomAnchor constant:4],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [self.detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-p],
    ]];
    return self;
}

- (void)configureWithLog:(NSManagedObject *)log relativeDateFormatter:(NSRelativeDateTimeFormatter *)rdf {
    self.actorLabel.text = [log valueForKey:@"actorUsername"] ?: @"(system)";
    NSString *action = [log valueForKey:@"action"] ?: @"?";
    self.actionLabel.text = [NSString stringWithFormat:@" %@ ", action.uppercaseString];
    self.resourceLabel.text = [log valueForKey:@"resource"] ?: @"—";

    NSDate *ts = [log valueForKey:@"occurredAt"];
    if (ts) {
        self.timestampLabel.text = [rdf localizedStringForDate:ts relativeToDate:[NSDate date]];
    } else {
        self.timestampLabel.text = @"—";
    }

    self.detailLabel.text = [log valueForKey:@"detail"] ?: @"";

    // Color-code action
    NSDictionary *actionColors = @{
        @"CREATE": [UIColor systemGreenColor],
        @"UPDATE": [UIColor systemBlueColor],
        @"DELETE": [UIColor systemRedColor],
        @"LOGIN":  [UIColor systemPurpleColor],
        @"LOGOUT": [UIColor systemGrayColor],
        @"PUBLISH": [UIColor systemOrangeColor],
    };
    UIColor *color = actionColors[action.uppercaseString] ?: [UIColor systemBlueColor];
    self.actionLabel.textColor = color;
    self.actionLabel.backgroundColor = [color colorWithAlphaComponent:0.1];
}

@end

// ---------------------------------------------------------------------------
// Main View Controller
// ---------------------------------------------------------------------------
@interface CPAuditLogViewController () <UITableViewDelegate, UITableViewDataSource,
    UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSMutableArray<NSManagedObject *> *logs;
@property (nonatomic, assign) NSInteger currentPage;
@property (nonatomic, assign) BOOL isLoadingMore;
@property (nonatomic, assign) BOOL hasMore;
@property (nonatomic, strong) NSString *activeResourceFilter;
@property (nonatomic, strong) NSRelativeDateTimeFormatter *relativeDateFormatter;
@property (nonatomic, strong) UIActivityIndicatorView *footerSpinner;
@end

static const NSInteger kPageSize = 50;

@implementation CPAuditLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Audit Log";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // Read-side authorization check — only admins may view audit logs.
    if (![[CPAuthService sharedService] currentUserHasPermission:@"admin"]) {
        UIAlertController *denied = [UIAlertController
            alertControllerWithTitle:@"Access Denied"
            message:@"You do not have permission to view the audit log."
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

    self.logs = [NSMutableArray array];
    self.currentPage = 0;
    self.hasMore = YES;

    self.relativeDateFormatter = [NSRelativeDateTimeFormatter new];
    self.relativeDateFormatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleAbbreviated;

    [self setupSearchController];
    [self setupTableView];
    [self setupNavigationBar];
    [self loadNextPage];
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search by actor username…";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
    [self.tableView registerClass:[CPAuditLogCell class] forCellReuseIdentifier:@"AuditCell"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Footer spinner for pagination
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 50)];
    self.footerSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.footerSpinner.center = CGPointMake(UIScreen.mainScreen.bounds.size.width / 2, 25);
    self.footerSpinner.hidesWhenStopped = YES;
    [footer addSubview:self.footerSpinner];
    self.tableView.tableFooterView = footer;
}

- (void)setupNavigationBar {
    // Export button
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                style:UIBarButtonItemStylePlain
               target:self action:@selector(exportAuditLog)];

    // Filter button using UIMenu
    UIBarButtonItem *filterBtn = [self makeFilterButton];

    self.navigationItem.rightBarButtonItems = @[exportBtn, filterBtn];
}

- (UIBarButtonItem *)makeFilterButton {
    NSArray<NSString *> *types = [[CPAuditService sharedService] availableResourceTypes];
    NSMutableArray *actions = [NSMutableArray array];

    UIAction *allAction = [UIAction actionWithTitle:@"All Resources"
        image:[UIImage systemImageNamed:@"list.bullet"]
        identifier:nil
        handler:^(__kindof UIAction *a) {
            self.activeResourceFilter = nil;
            [self resetAndReload];
        }];
    [actions addObject:allAction];

    for (NSString *type in types) {
        UIAction *action = [UIAction actionWithTitle:type image:nil identifier:nil handler:^(__kindof UIAction *a) {
            self.activeResourceFilter = type;
            [self resetAndReload];
        }];
        [actions addObject:action];
    }

    UIMenu *menu = [UIMenu menuWithTitle:@"Filter by Resource" children:actions];
    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                 menu:menu];
    return btn;
}

// ---------------------------------------------------------------------------
#pragma mark - Data loading
// ---------------------------------------------------------------------------

- (void)loadNextPage {
    if (self.isLoadingMore || !self.hasMore) return;
    self.isLoadingMore = YES;
    [self.footerSpinner startAnimating];

    NSString *search = self.searchController.searchBar.text.length > 0 ? self.searchController.searchBar.text : nil;

    [[CPAuditService sharedService]
        fetchAuditLogsPage:self.currentPage
        resourceType:self.activeResourceFilter
        search:search
        completion:^(NSArray *logs, BOOL hasMore, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isLoadingMore = NO;
                [self.footerSpinner stopAnimating];
                if (err) {
                    NSLog(@"[CPAuditLog] Error loading page %ld: %@", (long)self.currentPage, err);
                    return;
                }
                self.hasMore = hasMore;
                NSInteger insertStart = self.logs.count;
                [self.logs addObjectsFromArray:logs];
                self.currentPage++;

                NSMutableArray *indexPaths = [NSMutableArray array];
                for (NSInteger i = insertStart; i < (NSInteger)self.logs.count; i++) {
                    [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
                if (insertStart == 0) {
                    [self.tableView reloadData];
                } else if (indexPaths.count > 0) {
                    [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
                }
            });
        }];
}

- (void)resetAndReload {
    self.logs = [NSMutableArray array];
    self.currentPage = 0;
    self.hasMore = YES;
    [self.tableView reloadData];
    [self loadNextPage];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.logs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPAuditLogCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AuditCell" forIndexPath:indexPath];
    NSManagedObject *log = self.logs[indexPath.row];
    [cell configureWithLog:log relativeDateFormatter:self.relativeDateFormatter];
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate (infinite scroll)
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == (NSInteger)self.logs.count - 5 && self.hasMore && !self.isLoadingMore) {
        [self loadNextPage];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    // Audit logs are immutable — no editing
}

// Disable swipe-to-delete entirely
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

// ---------------------------------------------------------------------------
#pragma mark - UISearchResultsUpdating
// ---------------------------------------------------------------------------

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetAndReload) object:nil];
    [self performSelector:@selector(resetAndReload) withObject:nil afterDelay:0.3];
}

// ---------------------------------------------------------------------------
#pragma mark - Export
// ---------------------------------------------------------------------------

- (void)exportAuditLog {
    NSString *search = self.searchController.searchBar.text.length > 0 ? self.searchController.searchBar.text : nil;
    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:@"Exporting…"
        message:nil
        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    [[CPExportService sharedService]
        exportAuditLogsWithResourceType:self.activeResourceFilter
        search:search
        completion:^(NSURL *fileURL, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loading dismissViewControllerAnimated:YES completion:^{
                    if (error || !fileURL) {
                        UIAlertController *err = [UIAlertController
                            alertControllerWithTitle:@"Export Failed"
                            message:error.localizedDescription ?: @"Unknown error"
                            preferredStyle:UIAlertControllerStyleAlert];
                        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:err animated:YES completion:nil];
                        return;
                    }
                    UIActivityViewController *avc = [[UIActivityViewController alloc]
                        initWithActivityItems:@[fileURL]
                        applicationActivities:nil];
                    avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
                    [self presentViewController:avc animated:YES completion:nil];
                }];
            });
        }];
}

@end
