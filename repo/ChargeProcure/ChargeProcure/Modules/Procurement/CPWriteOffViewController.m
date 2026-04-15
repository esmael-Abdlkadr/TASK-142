#import "CPWriteOffViewController.h"
#import "CPProcurementService.h"
#import "CPAuthService.h"
#import "CPNumberFormatter.h"
#import "CPCoreDataStack.h"
#import "CPInvoice+CoreDataClass.h"
#import "CPInvoice+CoreDataProperties.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
#pragma mark - Write-off entry view (custom form)
// ---------------------------------------------------------------------------

@interface CPWriteOffViewController () <UITextViewDelegate, UITextFieldDelegate>

// Model
@property (nonatomic, strong, nullable) CPInvoice *invoice;
@property (nonatomic, strong) NSDecimalNumber *usedWriteOffAmount;
@property (nonatomic, strong) NSDecimalNumber *remainingCapacity;

// Header views
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;

// Header info labels
@property (nonatomic, strong) UILabel *invoiceNumberLabel;
@property (nonatomic, strong) UILabel *totalAmountLabel;
@property (nonatomic, strong) UILabel *varianceLabel;
@property (nonatomic, strong) UILabel *variancePercentLabel;
@property (nonatomic, strong) UILabel *existingWriteOffsLabel;
@property (nonatomic, strong) UILabel *availableCapacityLabel;

// Input controls
@property (nonatomic, strong) UITextField *amountField;
@property (nonatomic, strong) UITextView *reasonTextView;
@property (nonatomic, strong) UILabel *approverLabel;
@property (nonatomic, strong) UILabel *reasonCharCountLabel;

// Submit
@property (nonatomic, strong) UIButton *submitButton;

@end

@implementation CPWriteOffViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Write-Off Approval";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self _loadInvoice];
    [self _buildUI];
    [self _populateData];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_keyboardChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
#pragma mark - Data loading
// ---------------------------------------------------------------------------

- (void)_loadInvoice {
    if (!self.invoiceUUID) return;

    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [CPInvoice fetchRequest];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", self.invoiceUUID];
    req.fetchLimit = 1;
    NSArray *results = [ctx executeFetchRequest:req error:nil];
    _invoice = results.firstObject;

    // Calculate remaining write-off capacity
    _usedWriteOffAmount = _invoice.writeOffAmount ?: [NSDecimalNumber zero];
    _remainingCapacity = [CPWriteOffMaxAmount decimalNumberBySubtracting:_usedWriteOffAmount];
    if ([_remainingCapacity compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
        _remainingCapacity = [NSDecimalNumber zero];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - UI Construction
// ---------------------------------------------------------------------------

- (void)_buildUI {
    // Scroll view
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Stack
    _stackView = [[UIStackView alloc] init];
    _stackView.axis = UILayoutConstraintAxisVertical;
    _stackView.spacing = 0;
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_stackView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:16.0],
        [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
        [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-32.0],
        [_stackView.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor],
    ]];

    // --- Header card ---
    [_stackView addArrangedSubview:[self _buildSectionLabel:@"INVOICE DETAILS"]];
    UIView *headerCard = [self _buildCard];
    _invoiceNumberLabel   = [self _addRowToCard:headerCard title:@"Invoice #" valueLabel:[[UILabel alloc] init]];
    _totalAmountLabel     = [self _addRowToCard:headerCard title:@"Total Amount" valueLabel:[[UILabel alloc] init]];
    _varianceLabel        = [self _addRowToCard:headerCard title:@"Variance" valueLabel:[[UILabel alloc] init]];
    _variancePercentLabel = [self _addRowToCard:headerCard title:@"Variance %" valueLabel:[[UILabel alloc] init]];
    [_stackView addArrangedSubview:headerCard];

    // --- Write-off summary ---
    [_stackView addArrangedSubview:[self _buildSectionLabel:@"WRITE-OFF SUMMARY"]];
    UIView *summaryCard = [self _buildCard];
    _existingWriteOffsLabel = [self _addRowToCard:summaryCard title:@"Applied Write-Offs" valueLabel:[[UILabel alloc] init]];
    _availableCapacityLabel = [self _addRowToCard:summaryCard title:@"Available Capacity" valueLabel:[[UILabel alloc] init]];
    _availableCapacityLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [_stackView addArrangedSubview:summaryCard];

    // --- New write-off form ---
    [_stackView addArrangedSubview:[self _buildSectionLabel:@"NEW WRITE-OFF"]];
    UIView *formCard = [self _buildCard];
    [self _addFormFieldsToCard:formCard];
    [_stackView addArrangedSubview:formCard];

    // --- Submit button ---
    [_stackView addArrangedSubview:[self _buildSubmitButtonContainer]];
}

- (UIView *)_buildSectionLabel:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    label.textColor = [UIColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *container = [[UIView alloc] init];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4.0],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20.0],
    ]];
    return container;
}

- (UIView *)_buildCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12.0;
    card.layer.masksToBounds = YES;
    UIView *wrapper = [[UIView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:card];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
        [card.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-16.0],
    ]];
    // Attach a vertical stack inside the card
    UIStackView *innerStack = [[UIStackView alloc] init];
    innerStack.axis = UILayoutConstraintAxisVertical;
    innerStack.spacing = 0;
    innerStack.translatesAutoresizingMaskIntoConstraints = NO;
    innerStack.tag = 9001; // marker for row insertion
    [card addSubview:innerStack];
    [NSLayoutConstraint activateConstraints:@[
        [innerStack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [innerStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [innerStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [innerStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    ]];
    return wrapper;
}

- (UILabel *)_addRowToCard:(UIView *)cardWrapper title:(NSString *)title valueLabel:(UILabel *)valueLabel {
    UIView *card = cardWrapper.subviews.firstObject;
    UIStackView *innerStack = (UIStackView *)[card viewWithTag:9001];

    UIView *rowView = [[UIView alloc] init];
    rowView.translatesAutoresizingMaskIntoConstraints = NO;
    [rowView.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:15.0];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    valueLabel.font = [UIFont systemFontOfSize:15.0];
    valueLabel.textColor = [UIColor secondaryLabelColor];
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [rowView addSubview:titleLabel];
    [rowView addSubview:valueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:16.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:valueLabel.leadingAnchor constant:-8.0],
        [valueLabel.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-16.0],
    ]];

    if (innerStack.arrangedSubviews.count > 0) {
        // separator
        UIView *sep = [[UIView alloc] init];
        sep.backgroundColor = [UIColor separatorColor];
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        [rowView addSubview:sep];
        [NSLayoutConstraint activateConstraints:@[
            [sep.topAnchor constraintEqualToAnchor:rowView.topAnchor],
            [sep.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:16.0],
            [sep.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor],
            [sep.heightAnchor constraintEqualToConstant:0.5],
        ]];
    }

    [innerStack addArrangedSubview:rowView];
    return valueLabel;
}

- (void)_addFormFieldsToCard:(UIView *)cardWrapper {
    UIView *card = cardWrapper.subviews.firstObject;
    UIStackView *innerStack = (UIStackView *)[card viewWithTag:9001];

    // Amount field row
    UIView *amountRow = [self _buildFieldRow:@"Amount ($)" field:[self _buildAmountField]];
    [innerStack addArrangedSubview:amountRow];

    // Separator
    UIView *sep1 = [self _buildSeparator];
    [innerStack addArrangedSubview:sep1];

    // Reason text view row
    UIView *reasonRow = [self _buildReasonRow];
    [innerStack addArrangedSubview:reasonRow];

    // Separator
    [innerStack addArrangedSubview:[self _buildSeparator]];

    // Approver row
    UIView *approverRow = [self _buildApproverRow];
    [innerStack addArrangedSubview:approverRow];
}

- (UIView *)_buildFieldRow:(NSString *)title field:(UIView *)field {
    UIView *row = [[UIView alloc] init];
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:52.0].active = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:15.0];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    field.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:titleLabel];
    [row addSubview:field];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
        [titleLabel.widthAnchor constraintEqualToConstant:100.0],

        [field.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:8.0],
        [field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
        [field.topAnchor constraintEqualToAnchor:row.topAnchor constant:4.0],
        [field.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-4.0],
    ]];
    return row;
}

- (UITextField *)_buildAmountField {
    _amountField = [[UITextField alloc] init];
    _amountField.placeholder = @"0.00";
    _amountField.keyboardType = UIKeyboardTypeDecimalPad;
    _amountField.font = [UIFont systemFontOfSize:15.0];
    _amountField.textAlignment = NSTextAlignmentRight;
    _amountField.delegate = self;
    _amountField.clearButtonMode = UITextFieldViewModeWhileEditing;
    return _amountField;
}

- (UIView *)_buildReasonRow {
    UIView *row = [[UIView alloc] init];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Reason *";
    titleLabel.font = [UIFont systemFontOfSize:15.0];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _reasonTextView = [[UITextView alloc] init];
    _reasonTextView.font = [UIFont systemFontOfSize:15.0];
    _reasonTextView.delegate = self;
    _reasonTextView.backgroundColor = [UIColor clearColor];
    _reasonTextView.translatesAutoresizingMaskIntoConstraints = NO;
    _reasonTextView.text = @"";

    UILabel *placeholder = [[UILabel alloc] init];
    placeholder.text = @"Enter reason (minimum 20 characters)…";
    placeholder.font = [UIFont systemFontOfSize:15.0];
    placeholder.textColor = [UIColor placeholderTextColor];
    placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    placeholder.tag = 8800;
    [_reasonTextView addSubview:placeholder];
    [NSLayoutConstraint activateConstraints:@[
        [placeholder.topAnchor constraintEqualToAnchor:_reasonTextView.topAnchor constant:8.0],
        [placeholder.leadingAnchor constraintEqualToAnchor:_reasonTextView.leadingAnchor constant:5.0],
        [placeholder.trailingAnchor constraintEqualToAnchor:_reasonTextView.trailingAnchor],
    ]];

    _reasonCharCountLabel = [[UILabel alloc] init];
    _reasonCharCountLabel.font = [UIFont systemFontOfSize:12.0];
    _reasonCharCountLabel.textColor = [UIColor tertiaryLabelColor];
    _reasonCharCountLabel.text = @"0 / 20 min";
    _reasonCharCountLabel.textAlignment = NSTextAlignmentRight;
    _reasonCharCountLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:titleLabel];
    [row addSubview:_reasonTextView];
    [row addSubview:_reasonCharCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:12.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],

        [_reasonTextView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],
        [_reasonTextView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:11.0],
        [_reasonTextView.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
        [_reasonTextView.heightAnchor constraintGreaterThanOrEqualToConstant:80.0],

        [_reasonCharCountLabel.topAnchor constraintEqualToAnchor:_reasonTextView.bottomAnchor constant:2.0],
        [_reasonCharCountLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
        [_reasonCharCountLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8.0],
    ]];
    return row;
}

- (UIView *)_buildApproverRow {
    UIView *row = [[UIView alloc] init];
    [row.heightAnchor constraintEqualToConstant:44.0].active = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Approver";
    titleLabel.font = [UIFont systemFontOfSize:15.0];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _approverLabel = [[UILabel alloc] init];
    _approverLabel.font = [UIFont systemFontOfSize:15.0];
    _approverLabel.textColor = [UIColor secondaryLabelColor];
    _approverLabel.textAlignment = NSTextAlignmentRight;
    _approverLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _approverLabel.text = [CPAuthService sharedService].currentUsername ?: @"—";

    [row addSubview:titleLabel];
    [row addSubview:_approverLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
        [_approverLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [_approverLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
        [_approverLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:8.0],
    ]];
    return row;
}

- (UIView *)_buildSeparator {
    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [UIColor separatorColor];
    [sep.heightAnchor constraintEqualToConstant:0.5].active = YES;
    UIView *wrapper = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
        [sep.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:16.0],
        [sep.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
    ]];
    return wrapper;
}

- (UIView *)_buildSubmitButtonContainer {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    _submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_submitButton setTitle:@"Submit Write-Off" forState:UIControlStateNormal];
    _submitButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _submitButton.backgroundColor = [UIColor systemBlueColor];
    [_submitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _submitButton.layer.cornerRadius = 12.0;
    _submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_submitButton addTarget:self action:@selector(_handleSubmit) forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:_submitButton];
    [NSLayoutConstraint activateConstraints:@[
        [_submitButton.topAnchor constraintEqualToAnchor:container.topAnchor constant:24.0],
        [_submitButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_submitButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
        [_submitButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
        [_submitButton.heightAnchor constraintEqualToConstant:50.0],
    ]];
    return container;
}

// ---------------------------------------------------------------------------
#pragma mark - Populate data
// ---------------------------------------------------------------------------

- (void)_populateData {
    if (!_invoice) {
        _invoiceNumberLabel.text = @"—";
        _totalAmountLabel.text = @"—";
        _varianceLabel.text = @"—";
        _variancePercentLabel.text = @"—";
        _existingWriteOffsLabel.text = @"—";
        _availableCapacityLabel.text = @"—";
        return;
    }

    CPNumberFormatter *fmt = [CPNumberFormatter sharedFormatter];

    _invoiceNumberLabel.text = _invoice.invoiceNumber ?: _invoice.vendorInvoiceNumber ?: @"—";
    _totalAmountLabel.text = _invoice.totalAmount ? [fmt currencyStringFromDecimal:_invoice.totalAmount] : @"—";

    // Variance
    BOOL flagged = [_invoice.varianceFlag boolValue];
    NSString *varianceStr = _invoice.varianceAmount ? [fmt currencyStringFromDecimal:_invoice.varianceAmount] : @"$0.00";
    _varianceLabel.text = varianceStr;
    _varianceLabel.textColor = flagged ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];

    double varPct = _invoice.variancePercentage ? [_invoice.variancePercentage doubleValue] : 0.0;
    _variancePercentLabel.text = [fmt percentageStringFromDouble:varPct];
    _variancePercentLabel.textColor = flagged ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];

    // Write-off summary
    _existingWriteOffsLabel.text = [fmt currencyStringFromDecimal:_usedWriteOffAmount];
    NSString *availableStr = [NSString stringWithFormat:@"Available: %@ / %@",
                              [fmt currencyStringFromDecimal:_remainingCapacity],
                              [fmt currencyStringFromDecimal:CPWriteOffMaxAmount]];
    _availableCapacityLabel.text = availableStr;
    _availableCapacityLabel.textColor = ([_remainingCapacity compare:[NSDecimalNumber zero]] == NSOrderedDescending)
                                        ? [UIColor labelColor]
                                        : [UIColor systemRedColor];

    // Disable submit if no capacity
    if ([_remainingCapacity compare:[NSDecimalNumber zero]] == NSOrderedSame) {
        _submitButton.enabled = NO;
        _submitButton.backgroundColor = [UIColor systemGrayColor];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)_handleSubmit {
    NSString *amountStr = [_amountField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *reason = [_reasonTextView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Validate amount
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:amountStr];
    if (!amountStr.length || [amount isEqualToNumber:[NSDecimalNumber notANumber]] || [amount compare:[NSDecimalNumber zero]] != NSOrderedDescending) {
        [self _showAlert:@"Invalid Amount" message:@"Please enter a valid positive amount."];
        return;
    }
    if ([amount compare:_remainingCapacity] == NSOrderedDescending) {
        CPNumberFormatter *fmt = [CPNumberFormatter sharedFormatter];
        [self _showAlert:@"Exceeds Capacity"
                 message:[NSString stringWithFormat:@"Amount exceeds remaining capacity of %@.",
                          [fmt currencyStringFromDecimal:_remainingCapacity]]];
        return;
    }

    // Validate reason
    if (reason.length < 20) {
        [self _showAlert:@"Reason Required" message:@"Please provide a reason of at least 20 characters."];
        [_reasonTextView becomeFirstResponder];
        return;
    }

    NSString *approverUUID = [CPAuthService sharedService].currentUserID;
    if (!approverUUID) {
        [self _showAlert:@"Not Logged In" message:@"No current user found."];
        return;
    }

    // Haptic feedback
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic prepare];
    [haptic impactOccurred];

    // Disable button during submission
    _submitButton.enabled = NO;

    NSError *error = nil;
    BOOL success = [[CPProcurementService sharedService] createWriteOffForInvoice:self.invoiceUUID
                                                                            amount:amount
                                                                            reason:reason
                                                                      approverUUID:approverUUID
                                                                             error:&error];
    _submitButton.enabled = YES;

    if (success) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Write-Off Submitted"
                                                                       message:[NSString stringWithFormat:@"A write-off of %@ has been recorded.",
                                                                                [[CPNumberFormatter sharedFormatter] currencyStringFromDecimal:amount]]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self _showAlert:@"Submission Failed" message:error.localizedDescription ?: @"Could not create write-off."];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - UITextViewDelegate
// ---------------------------------------------------------------------------

- (void)textViewDidChange:(UITextView *)textView {
    NSInteger count = textView.text.length;
    _reasonCharCountLabel.text = [NSString stringWithFormat:@"%ld / 20 min", (long)count];
    _reasonCharCountLabel.textColor = count >= 20 ? [UIColor systemGreenColor] : [UIColor tertiaryLabelColor];
    // Show/hide placeholder
    UILabel *placeholder = (UILabel *)[textView viewWithTag:8800];
    placeholder.hidden = count > 0;
}

// ---------------------------------------------------------------------------
#pragma mark - UITextFieldDelegate
// ---------------------------------------------------------------------------

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Allow decimal input only
    NSString *resultString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    if (string.length == 0) return YES;
    NSCharacterSet *invalidChars = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    if ([string rangeOfCharacterFromSet:invalidChars].location != NSNotFound) return NO;
    NSInteger dotCount = [resultString componentsSeparatedByString:@"."].count - 1;
    return dotCount <= 1;
}

// ---------------------------------------------------------------------------
#pragma mark - Keyboard handling
// ---------------------------------------------------------------------------

- (void)_keyboardChanged:(NSNotification *)note {
    CGRect keyboardFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = CGRectGetHeight([[UIScreen mainScreen] bounds]) - CGRectGetMinY(keyboardFrame);
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, keyboardHeight, 0);
    _scrollView.contentInset = insets;
    _scrollView.scrollIndicatorInsets = insets;
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
