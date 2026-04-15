#import "CPReportsViewController.h"
#import "CPExportService.h"
#import "CPRBACService.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Report cell
// ---------------------------------------------------------------------------
@interface CPReportCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@end

@implementation CPReportCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [UIFont systemFontOfSize:13];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.subtitleLabel];

    self.dateLabel = [UILabel new];
    self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dateLabel.font = [UIFont systemFontOfSize:11];
    self.dateLabel.textColor = [UIColor tertiaryLabelColor];
    self.dateLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.dateLabel];

    const CGFloat p = 12;
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:p],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.dateLabel.leadingAnchor constant:-8],

        [self.dateLabel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.dateLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [self.dateLabel.widthAnchor constraintGreaterThanOrEqualToConstant:80],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-p],
    ]];
    return self;
}

static NSString *CPReportTypeName(CPReportType rt) {
    switch (rt) {
        case CPReportTypeProcurementSummary: return @"Procurement Summary";
        case CPReportTypeVendorStatement:    return @"Vendor Statement";
        case CPReportTypeChargerActivity:    return @"Charger Activity";
        case CPReportTypeAuditLog:           return @"Audit Log";
        case CPReportTypeAnalyticsSummary:   return @"Analytics Summary";
    }
    return @"Report";
}

- (void)configureWithExport:(NSManagedObject *)export {
    NSNumber *reportTypeNum = [export valueForKey:@"reportType"];
    CPReportType rt = (CPReportType)reportTypeNum.integerValue;
    self.titleLabel.text = CPReportTypeName(rt);

    NSNumber *format = [export valueForKey:@"format"];
    self.subtitleLabel.text = (format.integerValue == CPExportFormatCSV) ? @"CSV" : @"PDF";

    NSDate *generatedAt = [export valueForKey:@"generatedAt"];
    if (generatedAt) {
        NSRelativeDateTimeFormatter *rdf = [NSRelativeDateTimeFormatter new];
        rdf.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleAbbreviated;
        self.dateLabel.text = [rdf localizedStringForDate:generatedAt relativeToDate:[NSDate date]];
    } else {
        self.dateLabel.text = @"—";
    }
}

@end

// ---------------------------------------------------------------------------
// Report type picker model
// ---------------------------------------------------------------------------
static CPReportType kAllReportTypes[] = {
    CPReportTypeProcurementSummary,
    CPReportTypeVendorStatement,
    CPReportTypeChargerActivity,
    CPReportTypeAuditLog,
    CPReportTypeAnalyticsSummary,
};
static const NSUInteger kReportTypeCount = 5;

// ---------------------------------------------------------------------------
// Main View Controller
// ---------------------------------------------------------------------------
@interface CPReportsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSManagedObject *> *exports;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation CPReportsViewController

static NSString * const kCellID = @"CPReportCell";

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Reports";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self setupTableView];
    [self setupNavigationBar];
    [self applyRBACVisibility];
    [self reload];
}

/// Hides the "Generate Report" button for users without report.export permission.
- (void)applyRBACVisibility {
    BOOL canExport = [[CPRBACService sharedService]
                      currentUserCanPerform:CPActionExport onResource:CPResourceReport];
    self.navigationItem.rightBarButtonItem.enabled = canExport;
    self.navigationItem.rightBarButtonItem.tintColor = canExport ? nil : [UIColor clearColor];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 66;
    [self.tableView registerClass:[CPReportCell class] forCellReuseIdentifier:kCellID];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupNavigationBar {
    // Generate report button — opens report-type picker
    UIBarButtonItem *genBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus.circle"]
                style:UIBarButtonItemStylePlain
               target:self action:@selector(showGenerateSheet)];
    self.navigationItem.rightBarButtonItem = genBtn;
}

- (void)reload {
    // UI-level read authorization — belt-and-suspenders with service layer.
    if (![[CPRBACService sharedService] currentUserCanPerform:CPActionRead   onResource:CPResourceReport]
     && ![[CPRBACService sharedService] currentUserCanPerform:CPActionExport onResource:CPResourceReport]) {
        self.exports = @[];
        [self.tableView reloadData];
        return;
    }
    NSArray *results = [[CPExportService sharedService] fetchReportExports];
    self.exports = results ?: @[];
    [self.tableView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - Generate report sheet
// ---------------------------------------------------------------------------

- (void)showGenerateSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Generate Report"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger i = 0; i < kReportTypeCount; i++) {
        CPReportType rt = kAllReportTypes[i];
        NSString *title = CPReportTypeName(rt);
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *a) {
            [self generateReportOfType:rt];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)generateReportOfType:(CPReportType)reportType {
    // Enforce export permission in the UI layer (belt-and-suspenders with service layer).
    if (![[CPRBACService sharedService] currentUserCanPerform:CPActionExport onResource:CPResourceReport]) {
        UIAlertController *denied = [UIAlertController
            alertControllerWithTitle:@"Access Denied"
            message:@"Your role does not have permission to generate reports."
            preferredStyle:UIAlertControllerStyleAlert];
        [denied addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:denied animated:YES completion:nil];
        return;
    }
    self.navigationItem.rightBarButtonItem.enabled = NO;

    [[CPExportService sharedService]
        generateReport:reportType
                format:CPExportFormatCSV
            parameters:nil
            completion:^(NSURL *fileURL, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.navigationItem.rightBarButtonItem.enabled = YES;
                    if (error || !fileURL) {
                        UIAlertController *err = [UIAlertController
                            alertControllerWithTitle:@"Generation Failed"
                            message:error.localizedDescription ?: @"Unknown error."
                            preferredStyle:UIAlertControllerStyleAlert];
                        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:err animated:YES completion:nil];
                    } else {
                        [self reload];
                    }
                });
            }];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.exports.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPReportCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    [cell configureWithExport:self.exports[indexPath.row]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%ld Report%@", (long)self.exports.count,
            self.exports.count == 1 ? @"" : @"s"];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // UI-level read authorization check before opening a report file.
    if (![[CPRBACService sharedService] currentUserCanPerform:CPActionRead   onResource:CPResourceReport]
     && ![[CPRBACService sharedService] currentUserCanPerform:CPActionExport onResource:CPResourceReport]) {
        UIAlertController *denied = [UIAlertController
            alertControllerWithTitle:@"Access Denied"
            message:@"You do not have permission to open reports."
            preferredStyle:UIAlertControllerStyleAlert];
        [denied addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:denied animated:YES completion:nil];
        return;
    }

    NSManagedObject *export = self.exports[indexPath.row];
    NSString *reportUUID = [export valueForKey:@"uuid"];
    if (!reportUUID) return;

    NSURL *fileURL = [[CPExportService sharedService] exportURLForReportUUID:reportUUID];
    if (!fileURL) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"File Not Found"
            message:@"The report file could not be located."
            preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[fileURL] applicationActivities:nil];
    avc.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    [self presentViewController:avc animated:YES completion:nil];
}

@end
