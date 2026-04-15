//
//  CPDashboardViewController.m
//  ChargeProcure
//
//  Main dashboard screen. Shows summary cards, recent audit events, and
//  role-based content blocks. Uses UICollectionView with
//  UICollectionViewCompositionalLayout for the card strip and a plain
//  UITableView for recent audit events.
//

#import "CPDashboardViewController.h"

// Services
#import "CPAuthService.h"
#import "CPAuditService.h"
#import "CPChargerService.h"
#import "CPRBACService.h"
#import "CPCoreDataStack.h"

// Core Data entities
#import "CPCharger+CoreDataProperties.h"
#import "CPProcurementCase+CoreDataProperties.h"
#import "CPBulletin+CoreDataProperties.h"

// AppDelegate (for root VC replacement after logout)
#import "AppDelegate.h"

#import <CoreData/CoreData.h>

// MARK: - Summary card data model

@interface CPSummaryCard : NSObject
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, copy)   NSString *systemImageName;
@property (nonatomic, strong) UIColor  *accentColor;
@property (nonatomic, assign) NSInteger destinationTabIndex;
+ (instancetype)cardWithTitle:(NSString *)title
                        count:(NSInteger)count
                  systemImage:(NSString *)image
                  accentColor:(UIColor *)color
           destinationTabIndex:(NSInteger)tabIndex;
@end

@implementation CPSummaryCard
+ (instancetype)cardWithTitle:(NSString *)title
                        count:(NSInteger)count
                  systemImage:(NSString *)image
                  accentColor:(UIColor *)color
           destinationTabIndex:(NSInteger)tabIndex {
    CPSummaryCard *card = [[CPSummaryCard alloc] init];
    card.title                = title;
    card.count                = count;
    card.systemImageName      = image;
    card.accentColor          = color;
    card.destinationTabIndex  = tabIndex;
    return card;
}
@end

// MARK: - Summary card collection cell

static NSString * const kSummaryCardCellID = @"CPSummaryCardCell";

@interface CPSummaryCardCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *iconView;
- (void)configureWithCard:(CPSummaryCard *)card;
@end

@implementation CPSummaryCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.contentView.layer.cornerRadius = 14.0;
        self.contentView.layer.masksToBounds = YES;
        self.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.08f;
        self.layer.shadowOffset  = CGSizeMake(0, 2);
        self.layer.shadowRadius  = 6.0;

        self.iconView = [[UIImageView alloc] init];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:self.iconView];

        self.countLabel = [[UILabel alloc] init];
        self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.countLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
        self.countLabel.adjustsFontForContentSizeCategory = YES;
        self.countLabel.textColor = [UIColor labelColor];
        [self.contentView addSubview:self.countLabel];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        self.titleLabel.adjustsFontForContentSizeCategory = YES;
        self.titleLabel.textColor = [UIColor secondaryLabelColor];
        self.titleLabel.numberOfLines = 2;
        [self.contentView addSubview:self.titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.iconView.topAnchor    constraintEqualToAnchor:self.contentView.topAnchor constant:14.0],
            [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [self.iconView.widthAnchor  constraintEqualToConstant:28.0],
            [self.iconView.heightAnchor constraintEqualToConstant:28.0],

            [self.countLabel.topAnchor     constraintEqualToAnchor:self.iconView.bottomAnchor constant:8.0],
            [self.countLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [self.countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],

            [self.titleLabel.topAnchor     constraintEqualToAnchor:self.countLabel.bottomAnchor constant:2.0],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
            [self.titleLabel.bottomAnchor  constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],
        ]];
    }
    return self;
}

- (void)configureWithCard:(CPSummaryCard *)card {
    self.countLabel.text = @(card.count).stringValue;
    self.titleLabel.text = card.title;

    UIImageSymbolConfiguration *symConfig =
        [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightMedium];
    self.iconView.image = [[UIImage systemImageNamed:card.systemImageName
                              withConfiguration:symConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.iconView.tintColor = card.accentColor;

    self.isAccessibilityElement = YES;
    self.accessibilityLabel =
        [NSString stringWithFormat:@"%@: %@", card.title, @(card.count)];
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityHint   = NSLocalizedString(@"Double-tap to navigate", nil);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.countLabel.text = nil;
    self.titleLabel.text = nil;
    self.iconView.image  = nil;
}

@end

// MARK: - Audit event table cell

static NSString * const kAuditCellID = @"CPAuditEventCell";

// MARK: - Section identifiers

typedef NS_ENUM(NSUInteger, CPDashboardSection) {
    CPDashboardSectionCards       = 0,
    CPDashboardSectionStreak      = 1,
    CPDashboardSectionAuditEvents = 2,
    CPDashboardSectionRoleBased   = 3,
    CPDashboardSectionCount,
};

// MARK: - Private interface

@interface CPDashboardViewController () <
    UICollectionViewDelegate,
    UICollectionViewDataSource,
    NSFetchedResultsControllerDelegate,
    UITableViewDelegate,
    UITableViewDataSource
>

// MARK: Views
@property (nonatomic, strong) UIScrollView               *scrollView;
@property (nonatomic, strong) UIView                     *contentView;
@property (nonatomic, strong) UICollectionView           *cardsCollectionView;
@property (nonatomic, strong) UILabel                    *streakLabel;
@property (nonatomic, strong) UILabel                    *sectionAuditTitle;
@property (nonatomic, strong) UITableView                *auditTableView;
@property (nonatomic, strong) UIView                     *roleBasedContainerView;
@property (nonatomic, strong) UILabel                    *roleBasedLabel;
@property (nonatomic, strong) UILabel                    *pendingCommandsBadgeLabel;

// MARK: Data
@property (nonatomic, strong) NSMutableArray<CPSummaryCard *> *summaryCards;
@property (nonatomic, strong) NSMutableArray                  *recentAuditEvents;
@property (nonatomic, strong) NSFetchedResultsController      *auditFRC;

// MARK: Layout constraint for cards collection view height
@property (nonatomic, strong) NSLayoutConstraint *cardsHeightConstraint;

@end

// MARK: - Implementation

@implementation CPDashboardViewController

// MARK: - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    [self configureNavigationBar];
    [self buildUI];
    [self applyConstraints];
    [self setupFetchedResultsController];
    [self registerNotifications];
    [self refreshAllData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Keep the cards collection view height in sync with the compositional layout.
    [self updateCardsHeight];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Reload only currently visible cells rather than a full reload.
    NSArray<NSIndexPath *> *visiblePaths = [self.auditTableView indexPathsForVisibleRows];
    if (visiblePaths.count > 0) {
        [self.auditTableView reloadRowsAtIndexPaths:visiblePaths
                                  withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: - Navigation bar

- (void)configureNavigationBar {
    NSString *username = [[CPAuthService sharedService] currentUsername] ?: @"User";
    self.navigationItem.title =
        [NSString stringWithFormat:NSLocalizedString(@"Welcome, %@", nil), username];

    // Logout bar button (useful for demo / testing).
    UIBarButtonItem *logoutButton =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Sign Out", nil)
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(logoutButtonTapped:)];
    logoutButton.tintColor = [UIColor systemRedColor];
    logoutButton.accessibilityLabel = NSLocalizedString(@"Sign out button", nil);
    self.navigationItem.rightBarButtonItem = logoutButton;
}

// MARK: - UI construction

- (void)buildUI {
    // ---- Outer scroll view -------------------------------------------------
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    // ---- Summary cards collection view --------------------------------------
    UICollectionViewLayout *layout = [self makeSummaryCardsLayout];
    self.cardsCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                                  collectionViewLayout:layout];
    self.cardsCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardsCollectionView.backgroundColor = [UIColor clearColor];
    self.cardsCollectionView.showsHorizontalScrollIndicator = NO;
    self.cardsCollectionView.delegate   = self;
    self.cardsCollectionView.dataSource = self;
    [self.cardsCollectionView registerClass:[CPSummaryCardCell class]
                 forCellWithReuseIdentifier:kSummaryCardCellID];
    self.cardsCollectionView.accessibilityLabel = NSLocalizedString(@"Summary cards", nil);
    [self.contentView addSubview:self.cardsCollectionView];

    // ---- Pending commands badge label (red) ---------------------------------
    self.pendingCommandsBadgeLabel = [[UILabel alloc] init];
    self.pendingCommandsBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pendingCommandsBadgeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.pendingCommandsBadgeLabel.adjustsFontForContentSizeCategory = YES;
    self.pendingCommandsBadgeLabel.textColor = [UIColor whiteColor];
    self.pendingCommandsBadgeLabel.backgroundColor = [UIColor systemRedColor];
    self.pendingCommandsBadgeLabel.textAlignment = NSTextAlignmentCenter;
    self.pendingCommandsBadgeLabel.layer.cornerRadius = 10.0;
    self.pendingCommandsBadgeLabel.layer.masksToBounds = YES;
    self.pendingCommandsBadgeLabel.hidden = YES;
    self.pendingCommandsBadgeLabel.accessibilityTraits = UIAccessibilityTraitStaticText;
    [self.contentView addSubview:self.pendingCommandsBadgeLabel];

    // ---- Activity streak label ----------------------------------------------
    self.streakLabel = [[UILabel alloc] init];
    self.streakLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.streakLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.streakLabel.adjustsFontForContentSizeCategory = YES;
    self.streakLabel.textColor = [UIColor secondaryLabelColor];
    self.streakLabel.numberOfLines = 1;
    [self.contentView addSubview:self.streakLabel];

    // ---- Recent audit events section header ---------------------------------
    self.sectionAuditTitle = [[UILabel alloc] init];
    self.sectionAuditTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectionAuditTitle.text = NSLocalizedString(@"Recent Activity", nil);
    self.sectionAuditTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.sectionAuditTitle.adjustsFontForContentSizeCategory = YES;
    self.sectionAuditTitle.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.sectionAuditTitle];

    // ---- Audit events table view -------------------------------------------
    self.auditTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.auditTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditTableView.scrollEnabled = NO; // Outer scroll view handles scrolling
    self.auditTableView.delegate   = self;
    self.auditTableView.dataSource = self;
    self.auditTableView.backgroundColor = [UIColor clearColor];
    self.auditTableView.rowHeight = UITableViewAutomaticDimension;
    self.auditTableView.estimatedRowHeight = 60.0;
    [self.auditTableView registerClass:[UITableViewCell class]
                forCellReuseIdentifier:kAuditCellID];
    [self.contentView addSubview:self.auditTableView];

    // ---- Role-based content container --------------------------------------
    self.roleBasedContainerView = [[UIView alloc] init];
    self.roleBasedContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.roleBasedContainerView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.roleBasedContainerView.layer.cornerRadius = 14.0;
    self.roleBasedContainerView.layer.masksToBounds = YES;
    [self.contentView addSubview:self.roleBasedContainerView];

    self.roleBasedLabel = [[UILabel alloc] init];
    self.roleBasedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.roleBasedLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.roleBasedLabel.adjustsFontForContentSizeCategory = YES;
    self.roleBasedLabel.textColor = [UIColor secondaryLabelColor];
    self.roleBasedLabel.numberOfLines = 0;
    [self.roleBasedContainerView addSubview:self.roleBasedLabel];
}

// MARK: - Compositional layout for summary cards

- (UICollectionViewLayout *)makeSummaryCardsLayout {
    // Each card is a fixed-width item in a horizontally scrolling group.
    NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:150.0]
                                       heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
    item.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 12.0);

    NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension estimatedDimension:150.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:140.0]];
    NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;
    section.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 16.0, 8.0, 16.0);

    return [[UICollectionViewCompositionalLayout alloc] initWithSection:section];
}

// MARK: - Auto Layout

- (void)applyConstraints {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    CGFloat sideMargin = 16.0;

    // Scroll view
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor      constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor   constraintEqualToAnchor:safe.bottomAnchor],
    ]];

    // Content view
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor      constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor  constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor   constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor    constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];

    // Cards collection view height placeholder (updated in viewDidLayoutSubviews).
    self.cardsHeightConstraint = [self.cardsCollectionView.heightAnchor constraintEqualToConstant:156.0];

    [NSLayoutConstraint activateConstraints:@[
        // Cards
        [self.cardsCollectionView.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
        [self.cardsCollectionView.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.cardsCollectionView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        self.cardsHeightConstraint,

        // Pending commands badge (top-right of cards strip).
        [self.pendingCommandsBadgeLabel.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
        [self.pendingCommandsBadgeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [self.pendingCommandsBadgeLabel.widthAnchor    constraintGreaterThanOrEqualToConstant:20.0],
        [self.pendingCommandsBadgeLabel.heightAnchor   constraintEqualToConstant:20.0],

        // Streak label
        [self.streakLabel.topAnchor      constraintEqualToAnchor:self.cardsCollectionView.bottomAnchor constant:4.0],
        [self.streakLabel.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:sideMargin],
        [self.streakLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-sideMargin],

        // Audit section header
        [self.sectionAuditTitle.topAnchor      constraintEqualToAnchor:self.streakLabel.bottomAnchor constant:20.0],
        [self.sectionAuditTitle.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:sideMargin],
        [self.sectionAuditTitle.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-sideMargin],

        // Audit table view (non-scrollable; grows to fit content).
        [self.auditTableView.topAnchor      constraintEqualToAnchor:self.sectionAuditTitle.bottomAnchor constant:8.0],
        [self.auditTableView.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.auditTableView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.auditTableView.heightAnchor   constraintEqualToConstant:300.0],

        // Role-based container
        [self.roleBasedContainerView.topAnchor      constraintEqualToAnchor:self.auditTableView.bottomAnchor constant:20.0],
        [self.roleBasedContainerView.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:sideMargin],
        [self.roleBasedContainerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-sideMargin],

        // Role-based label inside container
        [self.roleBasedLabel.topAnchor      constraintEqualToAnchor:self.roleBasedContainerView.topAnchor constant:14.0],
        [self.roleBasedLabel.leadingAnchor  constraintEqualToAnchor:self.roleBasedContainerView.leadingAnchor constant:14.0],
        [self.roleBasedLabel.trailingAnchor constraintEqualToAnchor:self.roleBasedContainerView.trailingAnchor constant:-14.0],
        [self.roleBasedLabel.bottomAnchor   constraintEqualToAnchor:self.roleBasedContainerView.bottomAnchor constant:-14.0],

        // Bottom padding
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.roleBasedContainerView.bottomAnchor constant:32.0],
    ]];
}

// MARK: - Data loading

- (void)refreshAllData {
    [self loadSummaryCards];
    [self loadStreakData];
    [self loadRecentAuditEvents];
    [self loadPendingCommandsBadge];
    [self loadRoleBasedContent];
    [self.cardsCollectionView reloadData];
    [self.auditTableView reloadData];
}

- (void)loadSummaryCards {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;

    // Active chargers count
    NSFetchRequest *chargerFetch = [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
    chargerFetch.predicate = [NSPredicate predicateWithFormat:@"status == %@", @"Active"];
    NSInteger activeChargers = [ctx countForFetchRequest:chargerFetch error:nil];

    // Open procurement cases count
    NSFetchRequest *procFetch = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
    NSInteger openProcurement = [ctx countForFetchRequest:procFetch error:nil];

    // Pending (draft/unpublished) bulletins count
    NSFetchRequest *bulletinFetch = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
    // statusValue 0 = draft (pending)
    bulletinFetch.predicate = [NSPredicate predicateWithFormat:@"statusValue == 0"];
    NSInteger pendingBulletins = [ctx countForFetchRequest:bulletinFetch error:nil];

    self.summaryCards = [@[
        [CPSummaryCard cardWithTitle:NSLocalizedString(@"Active Chargers",   nil)
                               count:activeChargers
                          systemImage:@"bolt.fill"
                          accentColor:[UIColor systemGreenColor]
               destinationTabIndex:1],

        [CPSummaryCard cardWithTitle:NSLocalizedString(@"Open Procurement",  nil)
                               count:openProcurement
                          systemImage:@"doc.text.fill"
                          accentColor:[UIColor systemBlueColor]
               destinationTabIndex:2],

        [CPSummaryCard cardWithTitle:NSLocalizedString(@"Pending Bulletins", nil)
                               count:pendingBulletins
                          systemImage:@"newspaper.fill"
                          accentColor:[UIColor systemOrangeColor]
               destinationTabIndex:3],
    ] mutableCopy];
}

- (void)loadStreakData {
    // CPAnalyticsService may not be compiled yet; guard with runtime lookup.
    Class analyticsClass = NSClassFromString(@"CPAnalyticsService");
    if (analyticsClass && [analyticsClass respondsToSelector:@selector(sharedService)]) {
        id analyticsService = [analyticsClass performSelector:@selector(sharedService)];
        SEL streakSel = NSSelectorFromString(@"activityStreakDays");
        if ([analyticsService respondsToSelector:streakSel]) {
            NSInteger streakDays = ((NSInteger (*)(id, SEL))
                                    [analyticsService methodForSelector:streakSel])
                                   (analyticsService, streakSel);
            if (streakDays > 0) {
                self.streakLabel.text =
                    [NSString stringWithFormat:
                     NSLocalizedString(@"Activity streak: %ld day(s)", nil),
                     (long)streakDays];
                return;
            }
        }
    }
    self.streakLabel.text = NSLocalizedString(@"No active streak yet.", nil);
}

- (void)loadRecentAuditEvents {
    self.recentAuditEvents =
        [[[CPAuditService sharedService] fetchEventsWithOffset:0
                                                         limit:5
                                                     predicate:nil] mutableCopy];
}

- (void)loadPendingCommandsBadge {
    NSArray *pendingCommands = [[CPChargerService sharedService] fetchPendingReviewCommands];
    NSInteger count = (NSInteger)pendingCommands.count;

    if (count > 0) {
        self.pendingCommandsBadgeLabel.text =
            [NSString stringWithFormat:@"%ld", (long)count];
        self.pendingCommandsBadgeLabel.hidden = NO;
        self.pendingCommandsBadgeLabel.accessibilityLabel =
            [NSString stringWithFormat:
             NSLocalizedString(@"%ld pending command(s) require review", nil), (long)count];
    } else {
        self.pendingCommandsBadgeLabel.hidden = YES;
    }
}

- (void)loadRoleBasedContent {
    NSString *role = [[CPAuthService sharedService] currentUserRole] ?: @"";
    NSString *roleContent = nil;

    if ([role isEqualToString:@"Finance Approver"]) {
        // Finance Approver: show invoice summary.
        NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
        NSFetchRequest *invoiceFetch = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        invoiceFetch.predicate = [NSPredicate predicateWithFormat:@"status != %@", @"Paid"];
        NSInteger invoiceCount = [ctx countForFetchRequest:invoiceFetch error:nil];
        roleContent =
            [NSString stringWithFormat:
             NSLocalizedString(@"Invoice Summary\n%ld invoice(s) awaiting approval.", nil),
             (long)invoiceCount];

    } else if ([role isEqualToString:@"Administrator"]) {
        // Admin: show user summary.
        NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
        NSFetchRequest *userFetch = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        NSInteger userCount = [ctx countForFetchRequest:userFetch error:nil];
        roleContent =
            [NSString stringWithFormat:
             NSLocalizedString(@"User Management\n%ld registered user(s).", nil),
             (long)userCount];

    } else if ([role isEqualToString:@"Site Technician"]) {
        // Technician: show charger summary.
        NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
        NSFetchRequest *faultFetch = [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
        faultFetch.predicate = [NSPredicate predicateWithFormat:@"status == %@", @"Faulted"];
        NSInteger faultedCount = [ctx countForFetchRequest:faultFetch error:nil];
        roleContent =
            [NSString stringWithFormat:
             NSLocalizedString(@"Charger Summary\n%ld charger(s) currently faulted.", nil),
             (long)faultedCount];

    } else {
        roleContent = NSLocalizedString(@"Welcome to ChargeProcure. Select a section to get started.", nil);
    }

    self.roleBasedLabel.text = roleContent;
    self.roleBasedContainerView.hidden = (roleContent.length == 0);
}

// MARK: - NSFetchedResultsController (audit events)

- (void)setupFetchedResultsController {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;

    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"AuditEvent"];
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"occurredAt"
                                                           ascending:NO];
    request.sortDescriptors = @[sort];
    request.fetchLimit = 5;

    self.auditFRC = [[NSFetchedResultsController alloc]
                     initWithFetchRequest:request
                     managedObjectContext:ctx
                       sectionNameKeyPath:nil
                                cacheName:nil];
    self.auditFRC.delegate = self;

    NSError *error = nil;
    if (![self.auditFRC performFetch:&error]) {
        NSLog(@"[CPDashboardViewController] Audit FRC fetch failed: %@",
              error.localizedDescription);
    }
}

// MARK: - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.auditTableView reloadData];
}

// MARK: - Notifications

- (void)registerNotifications {
    // Charger status changes.
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(handleDataChanged:)
     name:CPChargerStatusChangedNotification
     object:nil];

    // Auth session changes (e.g. another VC posted a session-ended note).
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(handleAuthSessionChanged:)
     name:CPAuthSessionChangedNotification
     object:nil];
}

- (void)handleDataChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self loadSummaryCards];
        [self loadPendingCommandsBadge];
        [self.cardsCollectionView reloadData];
    });
}

- (void)handleAuthSessionChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self configureNavigationBar];
        [self loadRoleBasedContent];
    });
}

// MARK: - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.summaryCards.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CPSummaryCardCell *cell =
        [collectionView dequeueReusableCellWithReuseIdentifier:kSummaryCardCellID
                                                  forIndexPath:indexPath];
    CPSummaryCard *card = self.summaryCards[(NSUInteger)indexPath.item];
    [cell configureWithCard:card];
    return cell;
}

// MARK: - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView
    didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    CPSummaryCard *card = self.summaryCards[(NSUInteger)indexPath.item];
    [self navigateToTabIndex:card.destinationTabIndex];
}

// MARK: - UITableViewDataSource (audit events)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = (NSInteger)self.recentAuditEvents.count;
    return (count > 0) ? count : 1; // Show a "no activity" placeholder row
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAuditCellID
                                                            forIndexPath:indexPath];

    if (self.recentAuditEvents.count == 0) {
        if (@available(iOS 14.0, *)) {
            UIListContentConfiguration *config = [cell defaultContentConfiguration];
            config.text = NSLocalizedString(@"No recent activity.", nil);
            config.textProperties.color = [UIColor secondaryLabelColor];
            cell.contentConfiguration = config;
        } else {
            cell.textLabel.text = NSLocalizedString(@"No recent activity.", nil);
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    id event = self.recentAuditEvents[(NSUInteger)indexPath.row];

    // Use KVC to read audit event properties (avoids a hard import of the
    // entity class which may live in Core Data generated files).
    NSString *action     = [event valueForKey:@"action"]     ?: @"—";
    NSString *resource   = [event valueForKey:@"resource"]   ?: @"—";
    NSDate   *timestamp  = [event valueForKey:@"occurredAt"];

    NSString *timeString = @"";
    if (timestamp) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterNoStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        timeString = [fmt stringFromDate:timestamp];
    }

    if (@available(iOS 14.0, *)) {
        UIListContentConfiguration *config = [cell defaultContentConfiguration];
        config.text = [NSString stringWithFormat:@"%@ — %@", action, resource];
        config.secondaryText = timeString;
        config.secondaryTextProperties.color = [UIColor secondaryLabelColor];
        config.image = [UIImage systemImageNamed:@"clock"];
        cell.contentConfiguration = config;
    } else {
        cell.textLabel.text = [NSString stringWithFormat:@"%@ — %@", action, resource];
        cell.detailTextLabel.text = timeString;
        cell.imageView.image = [UIImage systemImageNamed:@"clock"];
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@ %@ at %@",
                                action, resource, timeString];
    return cell;
}

// MARK: - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// MARK: - Tab navigation (card shortcut)

- (void)navigateToTabIndex:(NSInteger)tabIndex {
    UITabBarController *tabBarController = nil;

    // Walk up the VC hierarchy to find the tab bar controller.
    UIViewController *vc = self;
    while (vc != nil) {
        if ([vc isKindOfClass:[UITabBarController class]]) {
            tabBarController = (UITabBarController *)vc;
            break;
        }
        vc = vc.parentViewController;
    }

    if (tabBarController) {
        tabBarController.selectedIndex = (NSUInteger)tabIndex;
    }
}

// MARK: - Cards collection view height update

- (void)updateCardsHeight {
    // Cards are 140pt tall + 8+8 section insets = 156pt.
    self.cardsHeightConstraint.constant = 156.0;
}

// MARK: - Actions

- (IBAction)logoutButtonTapped:(id)sender {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Sign Out", nil)
                                            message:NSLocalizedString(@"Are you sure you want to sign out?", nil)
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:
     [UIAlertAction actionWithTitle:NSLocalizedString(@"Sign Out", nil)
                              style:UIAlertActionStyleDestructive
                            handler:^(UIAlertAction *action) {
        [[CPAuthService sharedService] logout];
        [self resetToLoginScreen];
    }]];

    [alert addAction:
     [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                              style:UIAlertActionStyleCancel
                            handler:nil]];

    // iPad: anchor the popover to the bar button item.
    alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetToLoginScreen {
    AppDelegate *appDelegate =
        (AppDelegate *)[[UIApplication sharedApplication] delegate];
    if ([appDelegate respondsToSelector:@selector(configureRootViewControllerForAuthState)]) {
        [appDelegate performSelector:@selector(configureRootViewControllerForAuthState)];
    }
}

@end
