#import "CPVendorStatementViewController.h"
#import "CPProcurementService.h"
#import "CPExportService.h"
#import "CPNumberFormatter.h"
#import "CPDateFormatter.h"
#import "CPCoreDataStack.h"
#import "CPVendor+CoreDataClass.h"
#import "CPVendor+CoreDataProperties.h"
#import "CPInvoice+CoreDataClass.h"
#import "CPInvoice+CoreDataProperties.h"
#import "CPPayment+CoreDataClass.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
#pragma mark - Invoice row model
// ---------------------------------------------------------------------------

@interface CPStatementInvoiceRow : NSObject
@property (nonatomic, copy) NSString *invoiceNumber;
@property (nonatomic, copy) NSString *vendorInvoiceNumber;
@property (nonatomic, strong) NSDecimalNumber *totalAmount;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, strong, nullable) NSDate *paidDate;
@property (nonatomic, strong, nullable) NSDecimalNumber *paidAmount;
@end

@implementation CPStatementInvoiceRow
@end

// ---------------------------------------------------------------------------
#pragma mark - Summary header view
// ---------------------------------------------------------------------------

@interface CPStatementSummaryHeaderView : UIView
- (void)setTotalInvoiced:(NSDecimalNumber *)invoiced
              totalPaid:(NSDecimalNumber *)paid
            outstanding:(NSDecimalNumber *)outstanding;
@end

@implementation CPStatementSummaryHeaderView {
    UILabel *_monthLabel;
    UIStackView *_summaryStack;
    UILabel *_invoicedValueLabel;
    UILabel *_paidValueLabel;
    UILabel *_outstandingValueLabel;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _build];
    }
    return self;
}

- (void)_build {
    self.backgroundColor = [UIColor systemBlueColor];

    // Month label
    _monthLabel = [[UILabel alloc] init];
    _monthLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    _monthLabel.textColor = [UIColor whiteColor];
    _monthLabel.textAlignment = NSTextAlignmentCenter;
    _monthLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // Summary row
    _summaryStack = [[UIStackView alloc] init];
    _summaryStack.axis = UILayoutConstraintAxisHorizontal;
    _summaryStack.distribution = UIStackViewDistributionFillEqually;
    _summaryStack.spacing = 8.0;
    _summaryStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSDictionary *columns = @{
        @"Invoiced": [self _makeSummaryColumn:@"Invoiced" valueLabel:&_invoicedValueLabel],
        @"Paid": [self _makeSummaryColumn:@"Paid" valueLabel:&_paidValueLabel],
        @"Outstanding": [self _makeSummaryColumn:@"Outstanding" valueLabel:&_outstandingValueLabel],
    };

    // Insert in fixed order
    for (NSString *key in @[@"Invoiced", @"Paid", @"Outstanding"]) {
        [_summaryStack addArrangedSubview:columns[key]];
    }

    [self addSubview:_monthLabel];
    [self addSubview:_summaryStack];

    [NSLayoutConstraint activateConstraints:@[
        [_monthLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:20.0],
        [_monthLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [_monthLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],

        [_summaryStack.topAnchor constraintEqualToAnchor:_monthLabel.bottomAnchor constant:16.0],
        [_summaryStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [_summaryStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [_summaryStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-20.0],
    ]];
}

- (UIView *)_makeSummaryColumn:(NSString *)title valueLabel:(UILabel * __strong *)outLabel {
    UIStackView *col = [[UIStackView alloc] init];
    col.axis = UILayoutConstraintAxisVertical;
    col.alignment = UIStackViewAlignmentCenter;
    col.spacing = 4.0;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    titleLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *valLabel = [[UILabel alloc] init];
    valLabel.text = @"—";
    valLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    valLabel.textColor = [UIColor whiteColor];
    valLabel.textAlignment = NSTextAlignmentCenter;
    valLabel.adjustsFontSizeToFitWidth = YES;
    valLabel.minimumScaleFactor = 0.7;
    if (outLabel) *outLabel = valLabel;

    [col addArrangedSubview:titleLabel];
    [col addArrangedSubview:valLabel];
    return col;
}

- (void)setMonthTitle:(NSString *)title {
    _monthLabel.text = title;
}

- (void)setTotalInvoiced:(NSDecimalNumber *)invoiced
              totalPaid:(NSDecimalNumber *)paid
            outstanding:(NSDecimalNumber *)outstanding {
    CPNumberFormatter *fmt = [CPNumberFormatter sharedFormatter];
    _invoicedValueLabel.text = [fmt currencyStringFromDecimal:invoiced];
    _paidValueLabel.text = [fmt currencyStringFromDecimal:paid];

    NSString *outStr = [fmt currencyStringFromDecimal:outstanding];
    _outstandingValueLabel.text = outStr;
    // Red tint if outstanding > 0
    _outstandingValueLabel.textColor = ([outstanding compare:[NSDecimalNumber zero]] == NSOrderedDescending)
                                       ? [UIColor systemYellowColor]
                                       : [UIColor whiteColor];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Invoice table cell
// ---------------------------------------------------------------------------

static NSString * const kStatementCellID = @"CPStatementInvoiceCell";

@interface CPStatementInvoiceCell : UITableViewCell
- (void)configureWithRow:(CPStatementInvoiceRow *)row;
@end

@implementation CPStatementInvoiceCell {
    UILabel *_invoiceNumberLabel;
    UILabel *_vendorInvoiceLabel;
    UILabel *_amountLabel;
    UILabel *_statusBadge;
    UILabel *_paidDateLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self _buildLayout];
    }
    return self;
}

- (void)_buildLayout {
    _invoiceNumberLabel = [[UILabel alloc] init];
    _invoiceNumberLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    _invoiceNumberLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _vendorInvoiceLabel = [[UILabel alloc] init];
    _vendorInvoiceLabel.font = [UIFont systemFontOfSize:12.0];
    _vendorInvoiceLabel.textColor = [UIColor secondaryLabelColor];
    _vendorInvoiceLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _amountLabel = [[UILabel alloc] init];
    _amountLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    _amountLabel.textAlignment = NSTextAlignmentRight;
    _amountLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _statusBadge = [[UILabel alloc] init];
    _statusBadge.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    _statusBadge.textColor = [UIColor whiteColor];
    _statusBadge.layer.cornerRadius = 7.0;
    _statusBadge.layer.masksToBounds = YES;
    _statusBadge.textAlignment = NSTextAlignmentCenter;
    _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;

    _paidDateLabel = [[UILabel alloc] init];
    _paidDateLabel.font = [UIFont systemFontOfSize:12.0];
    _paidDateLabel.textColor = [UIColor secondaryLabelColor];
    _paidDateLabel.textAlignment = NSTextAlignmentRight;
    _paidDateLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self.contentView addSubview:_invoiceNumberLabel];
    [self.contentView addSubview:_vendorInvoiceLabel];
    [self.contentView addSubview:_amountLabel];
    [self.contentView addSubview:_statusBadge];
    [self.contentView addSubview:_paidDateLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_invoiceNumberLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],
        [_invoiceNumberLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [_invoiceNumberLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_amountLabel.leadingAnchor constant:-8.0],

        [_vendorInvoiceLabel.topAnchor constraintEqualToAnchor:_invoiceNumberLabel.bottomAnchor constant:2.0],
        [_vendorInvoiceLabel.leadingAnchor constraintEqualToAnchor:_invoiceNumberLabel.leadingAnchor],
        [_vendorInvoiceLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],

        [_amountLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],
        [_amountLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [_amountLabel.widthAnchor constraintGreaterThanOrEqualToConstant:90.0],

        [_statusBadge.topAnchor constraintEqualToAnchor:_amountLabel.bottomAnchor constant:4.0],
        [_statusBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [_statusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:60.0],
        [_statusBadge.heightAnchor constraintEqualToConstant:18.0],
        [_statusBadge.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],

        [_paidDateLabel.centerYAnchor constraintEqualToAnchor:_vendorInvoiceLabel.centerYAnchor],
        [_paidDateLabel.trailingAnchor constraintEqualToAnchor:_statusBadge.leadingAnchor constant:-8.0],
    ]];
}

- (void)configureWithRow:(CPStatementInvoiceRow *)row {
    _invoiceNumberLabel.text = row.invoiceNumber ?: @"—";
    _vendorInvoiceLabel.text = row.vendorInvoiceNumber.length ? [NSString stringWithFormat:@"Vendor: %@", row.vendorInvoiceNumber] : @"";
    _amountLabel.text = row.totalAmount ? [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:row.totalAmount] : @"—";

    _statusBadge.text = row.status ?: @"Unknown";
    NSString *statusLower = [row.status lowercaseString];
    if ([statusLower isEqualToString:@"paid"]) {
        _statusBadge.backgroundColor = [UIColor systemGreenColor];
    } else if ([statusLower isEqualToString:@"pending"] || [statusLower isEqualToString:@"approved"]) {
        _statusBadge.backgroundColor = [UIColor systemOrangeColor];
    } else {
        _statusBadge.backgroundColor = [UIColor systemGrayColor];
    }

    if (row.paidDate) {
        _paidDateLabel.text = [[CPDateFormatter sharedFormatter] displayDateStringFromDate:row.paidDate];
    } else {
        _paidDateLabel.text = @"";
    }
}

@end

// ---------------------------------------------------------------------------
#pragma mark - View controller
// ---------------------------------------------------------------------------

@interface CPVendorStatementViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) CPStatementSummaryHeaderView *headerView;
@property (nonatomic, strong) NSArray<CPStatementInvoiceRow *> *invoiceRows;
@property (nonatomic, strong) NSDecimalNumber *totalInvoiced;
@property (nonatomic, strong) NSDecimalNumber *totalPaid;
@property (nonatomic, strong) NSDecimalNumber *outstandingBalance;
@end

@implementation CPVendorStatementViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self _configureTitle];
    [self _buildExportButton];
    [self _buildHeaderView];
    [self _buildTableView];
    [self _loadStatementData];
}

- (void)_configureTitle {
    if (self.statementMonth) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"MMMM yyyy";
        self.title = [df stringFromDate:self.statementMonth];
    } else {
        self.title = @"Vendor Statement";
    }
}

- (void)_buildExportButton {
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc] initWithTitle:@"Export"
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(_handleExport)];
    self.navigationItem.rightBarButtonItem = exportBtn;
}

// ---------------------------------------------------------------------------
#pragma mark - UI Construction
// ---------------------------------------------------------------------------

- (void)_buildHeaderView {
    _headerView = [[CPStatementSummaryHeaderView alloc] init];

    if (self.statementMonth) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"MMMM yyyy";
        [_headerView setMonthTitle:[df stringFromDate:self.statementMonth]];
    }
}

- (void)_buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60.0;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [_tableView registerClass:[CPStatementInvoiceCell class] forCellReuseIdentifier:kStatementCellID];

    // Size the header view
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat targetWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGSize fittingSize = [_headerView systemLayoutSizeFittingSize:CGSizeMake(targetWidth, UILayoutFittingCompressedSize.height)
                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    _headerView.frame = CGRectMake(0, 0, targetWidth, fittingSize.height);
    _tableView.tableHeaderView = _headerView;

    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

// ---------------------------------------------------------------------------
#pragma mark - Data loading
// ---------------------------------------------------------------------------

- (void)_loadStatementData {
    if (!self.vendorUUID || !self.statementMonth) return;

    NSArray *statementData = [[CPProcurementService sharedService]
                              generateVendorStatementForVendor:self.vendorUUID
                              month:self.statementMonth];

    // Build invoice rows from returned data; the service returns an array of invoice objects/dicts
    NSMutableArray<CPStatementInvoiceRow *> *rows = [NSMutableArray array];
    NSDecimalNumber *invoicedSum = [NSDecimalNumber zero];
    NSDecimalNumber *paidSum = [NSDecimalNumber zero];

    for (id item in statementData) {
        CPStatementInvoiceRow *row = [[CPStatementInvoiceRow alloc] init];

        if ([item isKindOfClass:[CPInvoice class]]) {
            CPInvoice *inv = (CPInvoice *)item;
            row.invoiceNumber = inv.invoiceNumber;
            row.vendorInvoiceNumber = inv.vendorInvoiceNumber;
            row.totalAmount = inv.totalAmount ?: [NSDecimalNumber zero];
            row.status = inv.status ?: @"Unknown";
            if (inv.payment) {
                // CPPayment has paidAt and amount – accessed via KVC if not typed
                row.paidDate = [inv.payment valueForKey:@"paidAt"];
                row.paidAmount = [inv.payment valueForKey:@"amount"];
            }
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)item;
            row.invoiceNumber = d[@"invoiceNumber"];
            row.vendorInvoiceNumber = d[@"vendorInvoiceNumber"];
            row.totalAmount = d[@"totalAmount"] ?: [NSDecimalNumber zero];
            row.status = d[@"status"] ?: @"Unknown";
            row.paidDate = d[@"paidAt"];
            row.paidAmount = d[@"paidAmount"];
        } else {
            continue;
        }

        invoicedSum = [invoicedSum decimalNumberByAdding:row.totalAmount ?: [NSDecimalNumber zero]];
        if (row.paidAmount) {
            paidSum = [paidSum decimalNumberByAdding:row.paidAmount];
        }
        [rows addObject:row];
    }

    _invoiceRows = [rows copy];
    _totalInvoiced = invoicedSum;
    _totalPaid = paidSum;
    _outstandingBalance = [invoicedSum decimalNumberBySubtracting:paidSum];
    if ([_outstandingBalance compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
        _outstandingBalance = [NSDecimalNumber zero];
    }

    // Update header
    [_headerView setTotalInvoiced:_totalInvoiced totalPaid:_totalPaid outstanding:_outstandingBalance];

    // Re-layout header view
    [_headerView setNeedsLayout];
    [_headerView layoutIfNeeded];
    CGFloat targetWidth = CGRectGetWidth(self.view.bounds);
    if (targetWidth == 0) targetWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGSize fittingSize = [_headerView systemLayoutSizeFittingSize:CGSizeMake(targetWidth, UILayoutFittingCompressedSize.height)
                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    _headerView.frame = CGRectMake(0, 0, targetWidth, fittingSize.height);
    _tableView.tableHeaderView = _headerView;

    [_tableView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)_invoiceRows.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Invoices";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_invoiceRows.count == 0) {
        UITableViewCell *empty = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        empty.textLabel.text = @"No invoices for this period.";
        empty.textLabel.textColor = [UIColor secondaryLabelColor];
        empty.selectionStyle = UITableViewCellSelectionStyleNone;
        return empty;
    }

    CPStatementInvoiceCell *cell = [tableView dequeueReusableCellWithIdentifier:kStatementCellID
                                                                   forIndexPath:indexPath];
    [cell configureWithRow:_invoiceRows[indexPath.row]];
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// ---------------------------------------------------------------------------
#pragma mark - Export
// ---------------------------------------------------------------------------

- (void)_handleExport {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Export Statement"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:@"Export as CSV" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf _exportWithFormat:CPExportFormatCSV];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Export as PDF" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf _exportWithFormat:CPExportFormatPDF];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)_exportWithFormat:(CPExportFormat)format {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *month = self.statementMonth ?: [NSDate date];
    NSDateComponents *comps = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:month];

    NSDictionary *params = @{
        @"vendorUUID": self.vendorUUID ?: @"",
        @"year": @(comps.year),
        @"month": @(comps.month),
    };

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

    __weak typeof(self) weakSelf = self;
    [[CPExportService sharedService] generateReport:CPReportTypeVendorStatement
                                             format:format
                                         parameters:params
                                         completion:^(NSURL *fileURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf _buildExportButton];
            if (error || !fileURL) {
                [weakSelf _showAlert:@"Export Failed"
                             message:error.localizedDescription ?: @"Could not generate export."];
                return;
            }
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                              applicationActivities:nil];
            avc.popoverPresentationController.barButtonItem = weakSelf.navigationItem.rightBarButtonItem;
            [weakSelf presentViewController:avc animated:YES completion:nil];
        });
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

- (void)_showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
