#import "CPAnalyticsDashboardViewController.h"
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
@class CPAnalyticsService;
@class CPExportService;

@interface CPAnalyticsService : NSObject
+ (instancetype)sharedService;
- (void)fetchStreakData:(void(^)(NSInteger currentStreak, NSInteger longestStreak, NSError *_Nullable))completion;
- (void)fetchProcurementStages:(void(^)(NSArray<NSDictionary *> *stages, NSError *_Nullable))completion;
- (void)fetchChargerHeatmapData:(void(^)(NSArray<NSArray<NSNumber *> *> *grid, NSError *_Nullable))completion;
- (NSDictionary *)trendAnalysisForDays:(NSInteger)days resource:(NSString *)resource;
- (void)fetchAnomalies:(void(^)(NSArray<NSDictionary *> *anomalies, NSError *_Nullable))completion;
@end

@interface CPExportService : NSObject
+ (instancetype)sharedService;
- (void)generateAnalyticsExportForSegment:(NSInteger)segment
                               completion:(void(^)(NSURL *_Nullable fileURL, NSError *_Nullable error))completion;
@end

// ---------------------------------------------------------------------------
// Trend Line Chart View
// ---------------------------------------------------------------------------
@interface CPTrendChartView : UIView
@property (nonatomic, strong) NSArray<NSNumber *> *values; // normalized 0..1
@property (nonatomic, strong) UIColor *lineColor;
@end

@implementation CPTrendChartView

- (instancetype)init {
    self = [super init];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.lineColor = [UIColor systemBlueColor];
    }
    return self;
}

- (void)setValues:(NSArray<NSNumber *> *)values {
    _values = values;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (self.values.count < 2) return;

    CGFloat minVal = CGFLOAT_MAX, maxVal = -CGFLOAT_MAX;
    for (NSNumber *v in self.values) {
        CGFloat f = v.floatValue;
        if (f < minVal) minVal = f;
        if (f > maxVal) maxVal = f;
    }
    CGFloat range = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;

    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat stepX = rect.size.width / (CGFloat)(self.values.count - 1);
    BOOL first = YES;

    NSInteger idx = 0;
    for (NSNumber *v in self.values) {
        CGFloat normalised = (v.floatValue - minVal) / range;
        CGFloat x = idx * stepX;
        CGFloat y = rect.size.height - (normalised * (rect.size.height - 20)) - 10;
        if (first) {
            [path moveToPoint:CGPointMake(x, y)];
            first = NO;
        } else {
            [path addLineToPoint:CGPointMake(x, y)];
        }
        idx++;
    }

    [self.lineColor setStroke];
    path.lineWidth = 2.0;
    path.lineJoinStyle = kCGLineJoinRound;
    path.lineCapStyle = kCGLineCapRound;
    [path stroke];

    // Fill under curve
    UIBezierPath *fillPath = [path copy];
    [fillPath addLineToPoint:CGPointMake(rect.size.width, rect.size.height)];
    [fillPath addLineToPoint:CGPointMake(0, rect.size.height)];
    [fillPath closePath];
    [[self.lineColor colorWithAlphaComponent:0.1] setFill];
    [fillPath fill];

    // Dot at last value
    NSNumber *lastVal = self.values.lastObject;
    CGFloat lastNorm = (lastVal.floatValue - minVal) / range;
    CGFloat dotX = rect.size.width;
    CGFloat dotY = rect.size.height - (lastNorm * (rect.size.height - 20)) - 10;
    UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(dotX - 4, dotY - 4, 8, 8)];
    [self.lineColor setFill];
    [dot fill];
}

@end

// ---------------------------------------------------------------------------
// Heatmap View
// ---------------------------------------------------------------------------
@interface CPHeatmapView : UIView
// 7 rows (days) x 24 cols (hours), values 0..1
- (void)setHeatmapData:(NSArray<NSArray<NSNumber *> *> *)data;
@end

@implementation CPHeatmapView {
    NSArray<NSArray<NSNumber *> *> *_data;
    NSMutableArray<UIView *> *_cells;
}

- (instancetype)init {
    self = [super init];
    _cells = [NSMutableArray array];
    return self;
}

- (void)setHeatmapData:(NSArray<NSArray<NSNumber *> *> *)data {
    _data = data;
    [_cells makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [_cells removeAllObjects];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_data || _data.count == 0) return;

    [_cells makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [_cells removeAllObjects];

    NSInteger rows = MIN((NSInteger)_data.count, 7);
    NSInteger cols = rows > 0 ? MIN((NSInteger)_data[0].count, 24) : 24;
    if (cols == 0) return;

    CGFloat cellW = (self.bounds.size.width - (cols + 1) * 1.0) / cols;
    CGFloat cellH = (self.bounds.size.height - (rows + 1) * 1.0) / rows;

    for (NSInteger row = 0; row < rows; row++) {
        for (NSInteger col = 0; col < cols; col++) {
            CGFloat x = 1.0 + col * (cellW + 1.0);
            CGFloat y = 1.0 + row * (cellH + 1.0);
            UIView *cell = [[UIView alloc] initWithFrame:CGRectMake(x, y, cellW, cellH)];
            cell.layer.cornerRadius = 2;
            cell.layer.masksToBounds = YES;

            CGFloat intensity = 0;
            if (row < (NSInteger)_data.count && col < (NSInteger)_data[row].count) {
                intensity = [_data[row][col] floatValue];
                intensity = MAX(0, MIN(1, intensity));
            }

            // Blend blue (low) → red (high)
            UIColor *color = [UIColor colorWithRed:intensity green:0 blue:1.0 - intensity alpha:0.7 + intensity * 0.3];
            cell.backgroundColor = color;
            [self addSubview:cell];
            [_cells addObject:cell];
        }
    }
}

@end

// ---------------------------------------------------------------------------
// Main Dashboard
// ---------------------------------------------------------------------------
@interface CPAnalyticsDashboardViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

// Streak
@property (nonatomic, strong) UILabel *currentStreakLabel;
@property (nonatomic, strong) UILabel *longestStreakLabel;

// Procurement
@property (nonatomic, strong) NSArray<NSDictionary *> *procurementStages;
@property (nonatomic, strong) UIStackView *procurementStackView;

// Heatmap
@property (nonatomic, strong) CPHeatmapView *heatmapView;

// Trend
@property (nonatomic, strong) CPTrendChartView *trendChartView;
@property (nonatomic, strong) UISegmentedControl *trendRangeSegment;

// Anomalies
@property (nonatomic, strong) UITableView *anomalyTable;
@property (nonatomic, strong) NSArray<NSDictionary *> *anomalies;

// Rendering pause flag
@property (nonatomic, assign) BOOL renderingPaused;
@end

@implementation CPAnalyticsDashboardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Analytics";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.renderingPaused = NO;
    [self setupNavigationBar];
    [self setupSegmentControl];
    [self setupScrollView];
    [self buildDashboardUI];
    [self setupLoadingIndicator];
    [self registerForMemoryWarnings];
    [self loadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupNavigationBar {
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                style:UIBarButtonItemStylePlain
               target:self action:@selector(exportData)];
    self.navigationItem.rightBarButtonItem = exportBtn;
}

- (void)setupSegmentControl {
    self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"Activity", @"Procurement", @"Chargers"]];
    self.segmentControl.selectedSegmentIndex = 0;
    self.segmentControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.segmentControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.segmentControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.segmentControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.segmentControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    ]];
}

- (void)setupScrollView {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [UIView new];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.segmentControl.bottomAnchor constant:8],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];
}

- (void)buildDashboardUI {
    const CGFloat pad = 16;
    UIView *lastView = self.contentView;
    NSLayoutYAxisAnchor *topAnchor = self.contentView.topAnchor;

    // Helper to add a card
    UIView *(^card)(NSString *) = ^UIView *(NSString *title) {
        UIView *c = [UIView new];
        c.translatesAutoresizingMaskIntoConstraints = NO;
        c.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        c.layer.cornerRadius = 12;
        c.layer.masksToBounds = YES;
        [self.contentView addSubview:c];
        if (title.length > 0) {
            UILabel *titleLbl = [UILabel new];
            titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
            titleLbl.text = title;
            titleLbl.font = [UIFont boldSystemFontOfSize:15];
            [c addSubview:titleLbl];
            [NSLayoutConstraint activateConstraints:@[
                [titleLbl.topAnchor constraintEqualToAnchor:c.topAnchor constant:12],
                [titleLbl.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:12],
            ]];
            objc_setAssociatedObject(c, "titleLabel", titleLbl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return c;
    };

    // Streak card
    UIView *streakCard = card(@"Streak");
    [NSLayoutConstraint activateConstraints:@[
        [streakCard.topAnchor constraintEqualToAnchor:topAnchor constant:pad],
        [streakCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [streakCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];
    UILabel *titleLblRef = objc_getAssociatedObject(streakCard, "titleLabel");

    self.currentStreakLabel = [UILabel new];
    self.currentStreakLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.currentStreakLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.currentStreakLabel.text = @"—";
    [streakCard addSubview:self.currentStreakLabel];

    UILabel *currentStreakSubLabel = [UILabel new];
    currentStreakSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    currentStreakSubLabel.text = @"current days";
    currentStreakSubLabel.font = [UIFont systemFontOfSize:12];
    currentStreakSubLabel.textColor = [UIColor secondaryLabelColor];
    [streakCard addSubview:currentStreakSubLabel];

    self.longestStreakLabel = [UILabel new];
    self.longestStreakLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.longestStreakLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
    self.longestStreakLabel.textColor = [UIColor systemOrangeColor];
    self.longestStreakLabel.text = @"—";
    [streakCard addSubview:self.longestStreakLabel];

    UILabel *longestSubLabel = [UILabel new];
    longestSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    longestSubLabel.text = @"longest streak";
    longestSubLabel.font = [UIFont systemFontOfSize:12];
    longestSubLabel.textColor = [UIColor secondaryLabelColor];
    [streakCard addSubview:longestSubLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.currentStreakLabel.topAnchor constraintEqualToAnchor:titleLblRef.bottomAnchor constant:12],
        [self.currentStreakLabel.leadingAnchor constraintEqualToAnchor:streakCard.leadingAnchor constant:12],
        [currentStreakSubLabel.topAnchor constraintEqualToAnchor:self.currentStreakLabel.bottomAnchor constant:2],
        [currentStreakSubLabel.leadingAnchor constraintEqualToAnchor:streakCard.leadingAnchor constant:12],
        [currentStreakSubLabel.bottomAnchor constraintEqualToAnchor:streakCard.bottomAnchor constant:-12],

        [self.longestStreakLabel.topAnchor constraintEqualToAnchor:titleLblRef.bottomAnchor constant:12],
        [self.longestStreakLabel.leadingAnchor constraintEqualToAnchor:streakCard.centerXAnchor constant:8],
        [longestSubLabel.topAnchor constraintEqualToAnchor:self.longestStreakLabel.bottomAnchor constant:2],
        [longestSubLabel.leadingAnchor constraintEqualToAnchor:streakCard.centerXAnchor constant:8],
    ]];
    topAnchor = streakCard.bottomAnchor;

    // Procurement completion rate card
    UIView *procCard = card(@"Procurement Completion");
    [NSLayoutConstraint activateConstraints:@[
        [procCard.topAnchor constraintEqualToAnchor:topAnchor constant:pad],
        [procCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [procCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];

    UILabel *procTitleRef = objc_getAssociatedObject(procCard, "titleLabel");
    self.procurementStackView = [UIStackView new];
    self.procurementStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.procurementStackView.axis = UILayoutConstraintAxisVertical;
    self.procurementStackView.spacing = 8;
    [procCard addSubview:self.procurementStackView];
    [NSLayoutConstraint activateConstraints:@[
        [self.procurementStackView.topAnchor constraintEqualToAnchor:procTitleRef.bottomAnchor constant:12],
        [self.procurementStackView.leadingAnchor constraintEqualToAnchor:procCard.leadingAnchor constant:12],
        [self.procurementStackView.trailingAnchor constraintEqualToAnchor:procCard.trailingAnchor constant:-12],
        [self.procurementStackView.bottomAnchor constraintEqualToAnchor:procCard.bottomAnchor constant:-12],
    ]];
    topAnchor = procCard.bottomAnchor;

    // Heatmap card
    UIView *heatCard = card(@"Charger Activity (7 days × 24 hours)");
    [NSLayoutConstraint activateConstraints:@[
        [heatCard.topAnchor constraintEqualToAnchor:topAnchor constant:pad],
        [heatCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [heatCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];

    UILabel *heatTitleRef = objc_getAssociatedObject(heatCard, "titleLabel");
    self.heatmapView = [CPHeatmapView new];
    self.heatmapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.heatmapView.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
    self.heatmapView.layer.cornerRadius = 6;
    [heatCard addSubview:self.heatmapView];
    [NSLayoutConstraint activateConstraints:@[
        [self.heatmapView.topAnchor constraintEqualToAnchor:heatTitleRef.bottomAnchor constant:12],
        [self.heatmapView.leadingAnchor constraintEqualToAnchor:heatCard.leadingAnchor constant:12],
        [self.heatmapView.trailingAnchor constraintEqualToAnchor:heatCard.trailingAnchor constant:-12],
        [self.heatmapView.heightAnchor constraintEqualToConstant:120],
        [self.heatmapView.bottomAnchor constraintEqualToAnchor:heatCard.bottomAnchor constant:-12],
    ]];
    topAnchor = heatCard.bottomAnchor;

    // Trend chart card
    UIView *trendCard = card(@"Trend");
    [NSLayoutConstraint activateConstraints:@[
        [trendCard.topAnchor constraintEqualToAnchor:topAnchor constant:pad],
        [trendCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [trendCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];

    UILabel *trendTitleRef = objc_getAssociatedObject(trendCard, "titleLabel");
    self.trendRangeSegment = [[UISegmentedControl alloc] initWithItems:@[@"7d", @"30d", @"90d"]];
    self.trendRangeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.trendRangeSegment.selectedSegmentIndex = 0;
    [self.trendRangeSegment addTarget:self action:@selector(trendRangeChanged:) forControlEvents:UIControlEventValueChanged];
    [trendCard addSubview:self.trendRangeSegment];

    self.trendChartView = [CPTrendChartView new];
    self.trendChartView.translatesAutoresizingMaskIntoConstraints = NO;
    self.trendChartView.backgroundColor = [UIColor clearColor];
    [trendCard addSubview:self.trendChartView];

    [NSLayoutConstraint activateConstraints:@[
        [self.trendRangeSegment.topAnchor constraintEqualToAnchor:trendTitleRef.bottomAnchor constant:8],
        [self.trendRangeSegment.leadingAnchor constraintEqualToAnchor:trendCard.leadingAnchor constant:12],
        [self.trendRangeSegment.trailingAnchor constraintEqualToAnchor:trendCard.trailingAnchor constant:-12],

        [self.trendChartView.topAnchor constraintEqualToAnchor:self.trendRangeSegment.bottomAnchor constant:8],
        [self.trendChartView.leadingAnchor constraintEqualToAnchor:trendCard.leadingAnchor constant:12],
        [self.trendChartView.trailingAnchor constraintEqualToAnchor:trendCard.trailingAnchor constant:-12],
        [self.trendChartView.heightAnchor constraintEqualToConstant:140],
        [self.trendChartView.bottomAnchor constraintEqualToAnchor:trendCard.bottomAnchor constant:-12],
    ]];
    topAnchor = trendCard.bottomAnchor;

    // Anomaly alerts card
    UIView *anomalyCard = card(@"Anomaly Alerts");
    [NSLayoutConstraint activateConstraints:@[
        [anomalyCard.topAnchor constraintEqualToAnchor:topAnchor constant:pad],
        [anomalyCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [anomalyCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [anomalyCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32],
    ]];

    UILabel *anomalyTitleRef = objc_getAssociatedObject(anomalyCard, "titleLabel");

    self.anomalyTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.anomalyTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.anomalyTable.scrollEnabled = NO;
    self.anomalyTable.delegate = self;
    self.anomalyTable.dataSource = self;
    self.anomalyTable.rowHeight = UITableViewAutomaticDimension;
    self.anomalyTable.estimatedRowHeight = 60;
    self.anomalyTable.backgroundColor = [UIColor clearColor];
    self.anomalyTable.separatorInset = UIEdgeInsetsMake(0, 12, 0, 12);
    [anomalyCard addSubview:self.anomalyTable];

    [NSLayoutConstraint activateConstraints:@[
        [self.anomalyTable.topAnchor constraintEqualToAnchor:anomalyTitleRef.bottomAnchor constant:8],
        [self.anomalyTable.leadingAnchor constraintEqualToAnchor:anomalyCard.leadingAnchor],
        [self.anomalyTable.trailingAnchor constraintEqualToAnchor:anomalyCard.trailingAnchor],
        [self.anomalyTable.heightAnchor constraintGreaterThanOrEqualToConstant:80],
        [self.anomalyTable.bottomAnchor constraintEqualToAnchor:anomalyCard.bottomAnchor],
    ]];
}

- (void)setupLoadingIndicator {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)registerForMemoryWarnings {
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(handleMemoryWarning)
        name:UIApplicationDidReceiveMemoryWarningNotification
        object:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Data loading
// ---------------------------------------------------------------------------

- (void)loadData {
    [self.loadingIndicator startAnimating];
    self.scrollView.hidden = YES;
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    [[CPAnalyticsService sharedService] fetchStreakData:^(NSInteger current, NSInteger longest, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err) {
                self.currentStreakLabel.text = [NSString stringWithFormat:@"%ld 🔥", (long)current];
                self.longestStreakLabel.text = [NSString stringWithFormat:@"%ld days", (long)longest];
            }
            dispatch_group_leave(group);
        });
    }];

    dispatch_group_enter(group);
    [[CPAnalyticsService sharedService] fetchProcurementStages:^(NSArray *stages, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err) {
                self.procurementStages = stages;
                [self rebuildProcurementBars];
            }
            dispatch_group_leave(group);
        });
    }];

    dispatch_group_enter(group);
    [[CPAnalyticsService sharedService] fetchChargerHeatmapData:^(NSArray *grid, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err && !self.renderingPaused) {
                [self.heatmapView setHeatmapData:grid];
            }
            dispatch_group_leave(group);
        });
    }];

    dispatch_group_enter(group);
    [self loadTrendDataForDays:7 completion:^{
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [[CPAnalyticsService sharedService] fetchAnomalies:^(NSArray *anomalies, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err) {
                self.anomalies = anomalies;
                [self.anomalyTable reloadData];
                [self updateAnomalyTableHeight];
            }
            dispatch_group_leave(group);
        });
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self.loadingIndicator stopAnimating];
        self.scrollView.hidden = NO;
    });
}

- (void)loadTrendDataForDays:(NSInteger)days completion:(dispatch_block_t)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *result = [[CPAnalyticsService sharedService] trendAnalysisForDays:days resource:@"charger"];
        NSArray *values = result[@"dailyCounts"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (values && !self.renderingPaused) {
                self.trendChartView.values = values;
            }
            if (completion) completion();
        });
    });
}

- (void)rebuildProcurementBars {
    for (UIView *v in self.procurementStackView.arrangedSubviews) {
        [self.procurementStackView removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    for (NSDictionary *stage in self.procurementStages) {
        NSString *name = stage[@"name"] ?: @"Stage";
        CGFloat rate = [stage[@"completionRate"] floatValue];

        UIView *row = [UIView new];
        row.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *nameLabel = [UILabel new];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        nameLabel.text = name;
        nameLabel.font = [UIFont systemFontOfSize:13];
        nameLabel.textColor = [UIColor secondaryLabelColor];
        [[nameLabel.widthAnchor constraintEqualToConstant:120] setActive:YES];
        [row addSubview:nameLabel];

        UIProgressView *progress = [UIProgressView new];
        progress.translatesAutoresizingMaskIntoConstraints = NO;
        progress.progressViewStyle = UIProgressViewStyleDefault;
        progress.progress = rate;
        progress.progressTintColor = rate >= 0.8 ? [UIColor systemGreenColor] :
                                     rate >= 0.5 ? [UIColor systemOrangeColor] :
                                     [UIColor systemRedColor];
        [row addSubview:progress];

        UILabel *rateLabel = [UILabel new];
        rateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        rateLabel.text = [NSString stringWithFormat:@"%.0f%%", rate * 100];
        rateLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        rateLabel.textAlignment = NSTextAlignmentRight;
        [rateLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [row addSubview:rateLabel];

        [NSLayoutConstraint activateConstraints:@[
            [nameLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [nameLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

            [progress.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor constant:8],
            [progress.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [progress.trailingAnchor constraintEqualToAnchor:rateLabel.leadingAnchor constant:-8],

            [rateLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [rateLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

            [row.heightAnchor constraintEqualToConstant:28],
        ]];

        [self.procurementStackView addArrangedSubview:row];
    }
}

- (void)updateAnomalyTableHeight {
    CGFloat rowHeight = 60;
    CGFloat height = MAX(80, self.anomalies.count * rowHeight);
    // Update height constraint
    for (NSLayoutConstraint *c in self.anomalyTable.constraints) {
        if (c.firstAttribute == NSLayoutAttributeHeight) {
            c.constant = height;
            break;
        }
    }
    [self.view layoutIfNeeded];
}

// ---------------------------------------------------------------------------
#pragma mark - Segment / range changes
// ---------------------------------------------------------------------------

- (void)segmentChanged:(UISegmentedControl *)sender {
    // Could filter which cards are visible per segment
    // For now reload data in context of the segment
    [self loadData];
}

- (void)trendRangeChanged:(UISegmentedControl *)sender {
    NSArray *days = @[@7, @30, @90];
    NSInteger d = [days[sender.selectedSegmentIndex] integerValue];
    [self loadTrendDataForDays:d completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Memory warning
// ---------------------------------------------------------------------------

- (void)handleMemoryWarning {
    NSLog(@"[CPAnalyticsDashboard] Memory warning — pausing rendering");
    self.renderingPaused = YES;
    // Release heavy chart data
    self.trendChartView.values = nil;
    [self.heatmapView setHeatmapData:@[]];
}

// ---------------------------------------------------------------------------
#pragma mark - Export
// ---------------------------------------------------------------------------

- (void)exportData {
    NSInteger segment = self.segmentControl.selectedSegmentIndex;
    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:@"Generating Report"
        message:@"Please wait…"
        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    [[CPExportService sharedService] generateAnalyticsExportForSegment:segment completion:^(NSURL *fileURL, NSError *error) {
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
                avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
                [self presentViewController:avc animated:YES completion:nil];
            }];
        });
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource (anomalies)
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.anomalies.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *anomalyCellID = @"AnomalyCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:anomalyCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:anomalyCellID];
    }
    NSDictionary *anomaly = self.anomalies[indexPath.row];
    NSString *type = anomaly[@"type"] ?: @"Unknown";
    NSString *desc = anomaly[@"description"] ?: @"";
    NSString *severity = anomaly[@"severity"] ?: @"medium";

    cell.textLabel.text = [NSString stringWithFormat:@"[%@] %@", type, desc];
    cell.textLabel.numberOfLines = 0;

    UIColor *severityColor = [UIColor systemOrangeColor];
    if ([severity isEqualToString:@"high"] || [severity isEqualToString:@"critical"]) {
        severityColor = [UIColor systemRedColor];
    } else if ([severity isEqualToString:@"low"]) {
        severityColor = [UIColor systemYellowColor];
    }
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Severity: %@", severity];
    cell.detailTextLabel.textColor = severityColor;
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
