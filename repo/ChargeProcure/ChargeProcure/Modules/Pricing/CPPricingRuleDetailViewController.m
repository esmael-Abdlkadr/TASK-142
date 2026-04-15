#import "CPPricingRuleDetailViewController.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
@class CPPricingService;
@class CPAuthService;

@interface CPPricingService : NSObject
+ (instancetype)sharedService;
- (NSManagedObjectContext *)mainContext;
- (void)createPricingRuleWithServiceType:(NSString *)serviceType
                            vehicleClass:(NSString *_Nullable)vehicleClass
                                 storeID:(NSString *_Nullable)storeID
                               basePrice:(NSDecimalNumber *)basePrice
                          effectiveStart:(NSDate *)effectiveStart
                            effectiveEnd:(NSDate *_Nullable)effectiveEnd
                                  tierJSON:(NSString *_Nullable)tierJSON
                                    notes:(NSString *_Nullable)notes
                               completion:(void(^)(NSString *_Nullable uuid, NSError *_Nullable error))completion;
- (void)deprecateRuleWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion;
@end

@interface CPAuthService : NSObject
+ (instancetype)sharedService;
- (BOOL)currentUserHasPermission:(NSString *)permission;
@end

// ---------------------------------------------------------------------------
// Main View Controller
// ---------------------------------------------------------------------------
@interface CPPricingRuleDetailViewController () <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Form fields
@property (nonatomic, strong) UITextField *serviceTypeField;
@property (nonatomic, strong) UITextField *vehicleClassField;
@property (nonatomic, strong) UITextField *storeIDField;
@property (nonatomic, strong) UITextField *basePriceField;
@property (nonatomic, strong) UIDatePicker *effectiveStartPicker;
@property (nonatomic, strong) UIDatePicker *effectiveEndPicker;
@property (nonatomic, strong) UISwitch *hasEndDateSwitch;
@property (nonatomic, strong) UITextView *tierJSONTextView;
@property (nonatomic, strong) UITextView *notesTextView;
@property (nonatomic, strong) UILabel *versionLabel;

// Price calculator
@property (nonatomic, strong) UITextField *durationInputField;
@property (nonatomic, strong) UILabel *calculatedPriceLabel;

// Buttons
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *deprecateButton;

// Existing rule
@property (nonatomic, strong) NSManagedObject *existingRule;
@property (nonatomic, assign) BOOL isViewMode; // viewing existing (not editable)
@end

@implementation CPPricingRuleDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // Page-level read authorization — pricing rules are admin-only, mirroring list screen policy.
    if (![[CPAuthService sharedService] currentUserHasPermission:@"admin"]) {
        self.title = @"Pricing Rule";
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

    [self setupScrollView];
    [self buildForm];
    [self loadExistingRule];
}

// ---------------------------------------------------------------------------
#pragma mark - Scroll view setup
// ---------------------------------------------------------------------------

- (void)setupScrollView {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.contentView = [UIView new];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
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

// ---------------------------------------------------------------------------
#pragma mark - Form building
// ---------------------------------------------------------------------------

typedef UIView *(^RowBuilder)(void);

- (UILabel *)sectionLabelWithText:(NSString *)text {
    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = text;
    lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    lbl.textColor = [UIColor secondaryLabelColor];
    return lbl;
}

- (UITextField *)styledTextField {
    UITextField *tf = [UITextField new];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.font = [UIFont systemFontOfSize:15];
    tf.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    tf.layer.cornerRadius = 8;
    tf.layer.masksToBounds = YES;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.delegate = self;
    return tf;
}

- (void)buildForm {
    const CGFloat pad = 16;
    UIView *anchor = self.contentView;
    __block NSLayoutYAxisAnchor *topAnchor = self.contentView.topAnchor;
    CGFloat topConst = pad;

    // Helper to add a labeled row
    void (^addRow)(NSString *, UIView *, UIView **, NSLayoutYAxisAnchor **, CGFloat *) =
        ^(NSString *sectionText, UIView *field, UIView **outField, NSLayoutYAxisAnchor **outBottom, CGFloat *topC) {
            UILabel *lbl = [self sectionLabelWithText:sectionText];
            [anchor addSubview:lbl];
            [anchor addSubview:field];
            [NSLayoutConstraint activateConstraints:@[
                [lbl.topAnchor constraintEqualToAnchor:topAnchor constant:topC ? *topC : 16],
                [lbl.leadingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:pad],
                [field.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:4],
                [field.leadingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:pad],
                [field.trailingAnchor constraintEqualToAnchor:anchor.trailingAnchor constant:-pad],
                [field.heightAnchor constraintEqualToConstant:44],
            ]];
            if (outField) *outField = field;
            if (outBottom) *outBottom = field.bottomAnchor;
            topAnchor = field.bottomAnchor;
            *topC = 16;
        };

    // Service type
    self.serviceTypeField = [self styledTextField];
    self.serviceTypeField.placeholder = @"e.g. EV_CHARGING, PARKING";
    addRow(@"SERVICE TYPE", self.serviceTypeField, nil, nil, &topConst);

    // Vehicle class
    self.vehicleClassField = [self styledTextField];
    self.vehicleClassField.placeholder = @"Optional: COMPACT, SUV, TRUCK…";
    addRow(@"VEHICLE CLASS (OPTIONAL)", self.vehicleClassField, nil, nil, &topConst);

    // Store ID
    self.storeIDField = [self styledTextField];
    self.storeIDField.placeholder = @"Optional: store identifier";
    addRow(@"STORE ID (OPTIONAL)", self.storeIDField, nil, nil, &topConst);

    // Base price
    self.basePriceField = [self styledTextField];
    self.basePriceField.placeholder = @"0.00";
    self.basePriceField.keyboardType = UIKeyboardTypeDecimalPad;
    addRow(@"BASE PRICE ($)", self.basePriceField, nil, nil, &topConst);

    // Effective start
    UILabel *startLbl = [self sectionLabelWithText:@"EFFECTIVE START"];
    [self.contentView addSubview:startLbl];
    self.effectiveStartPicker = [UIDatePicker new];
    self.effectiveStartPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.effectiveStartPicker.datePickerMode = UIDatePickerModeDateAndTime;
    self.effectiveStartPicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    [self.contentView addSubview:self.effectiveStartPicker];

    [NSLayoutConstraint activateConstraints:@[
        [startLbl.topAnchor constraintEqualToAnchor:topAnchor constant:topConst],
        [startLbl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.effectiveStartPicker.topAnchor constraintEqualToAnchor:startLbl.bottomAnchor constant:4],
        [self.effectiveStartPicker.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
    ]];
    topAnchor = self.effectiveStartPicker.bottomAnchor;
    topConst = 16;

    // Effective end (optional, toggle)
    UILabel *endLbl = [self sectionLabelWithText:@"EFFECTIVE END (OPTIONAL)"];
    [self.contentView addSubview:endLbl];

    UIView *endRow = [UIView new];
    endRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:endRow];

    self.hasEndDateSwitch = [UISwitch new];
    self.hasEndDateSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hasEndDateSwitch addTarget:self action:@selector(endDateToggled:) forControlEvents:UIControlEventValueChanged];
    [endRow addSubview:self.hasEndDateSwitch];

    UILabel *endToggleLabel = [UILabel new];
    endToggleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    endToggleLabel.text = @"Set end date";
    endToggleLabel.font = [UIFont systemFontOfSize:15];
    [endRow addSubview:endToggleLabel];

    self.effectiveEndPicker = [UIDatePicker new];
    self.effectiveEndPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.effectiveEndPicker.datePickerMode = UIDatePickerModeDateAndTime;
    self.effectiveEndPicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    self.effectiveEndPicker.hidden = YES;
    [endRow addSubview:self.effectiveEndPicker];

    [NSLayoutConstraint activateConstraints:@[
        [endLbl.topAnchor constraintEqualToAnchor:topAnchor constant:topConst],
        [endLbl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],

        [endRow.topAnchor constraintEqualToAnchor:endLbl.bottomAnchor constant:4],
        [endRow.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [endRow.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],

        [endToggleLabel.topAnchor constraintEqualToAnchor:endRow.topAnchor constant:8],
        [endToggleLabel.leadingAnchor constraintEqualToAnchor:endRow.leadingAnchor],

        [self.hasEndDateSwitch.centerYAnchor constraintEqualToAnchor:endToggleLabel.centerYAnchor],
        [self.hasEndDateSwitch.trailingAnchor constraintEqualToAnchor:endRow.trailingAnchor],

        [self.effectiveEndPicker.topAnchor constraintEqualToAnchor:endToggleLabel.bottomAnchor constant:8],
        [self.effectiveEndPicker.leadingAnchor constraintEqualToAnchor:endRow.leadingAnchor],
        [self.effectiveEndPicker.bottomAnchor constraintEqualToAnchor:endRow.bottomAnchor constant:-8],
    ]];
    topAnchor = endRow.bottomAnchor;
    topConst = 16;

    // Tier JSON
    UILabel *tierLbl = [self sectionLabelWithText:@"TIER PRICING (JSON)"];
    [self.contentView addSubview:tierLbl];

    UILabel *tierHelpText = [UILabel new];
    tierHelpText.translatesAutoresizingMaskIntoConstraints = NO;
    tierHelpText.text = @"Format: [{\"maxDuration\": 3600, \"price\": 10.00}, ...]";
    tierHelpText.font = [UIFont systemFontOfSize:11];
    tierHelpText.textColor = [UIColor secondaryLabelColor];
    tierHelpText.numberOfLines = 0;
    [self.contentView addSubview:tierHelpText];

    self.tierJSONTextView = [UITextView new];
    self.tierJSONTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tierJSONTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.tierJSONTextView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.tierJSONTextView.layer.cornerRadius = 8;
    self.tierJSONTextView.layer.masksToBounds = YES;
    self.tierJSONTextView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    self.tierJSONTextView.delegate = self;
    [self.contentView addSubview:self.tierJSONTextView];

    [NSLayoutConstraint activateConstraints:@[
        [tierLbl.topAnchor constraintEqualToAnchor:topAnchor constant:topConst],
        [tierLbl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],

        [tierHelpText.topAnchor constraintEqualToAnchor:tierLbl.bottomAnchor constant:2],
        [tierHelpText.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [tierHelpText.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],

        [self.tierJSONTextView.topAnchor constraintEqualToAnchor:tierHelpText.bottomAnchor constant:4],
        [self.tierJSONTextView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.tierJSONTextView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.tierJSONTextView.heightAnchor constraintEqualToConstant:100],
    ]];
    topAnchor = self.tierJSONTextView.bottomAnchor;
    topConst = 16;

    // Notes
    UILabel *notesLbl = [self sectionLabelWithText:@"NOTES"];
    [self.contentView addSubview:notesLbl];

    self.notesTextView = [UITextView new];
    self.notesTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.notesTextView.font = [UIFont systemFontOfSize:14];
    self.notesTextView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.notesTextView.layer.cornerRadius = 8;
    self.notesTextView.layer.masksToBounds = YES;
    self.notesTextView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    [self.contentView addSubview:self.notesTextView];

    [NSLayoutConstraint activateConstraints:@[
        [notesLbl.topAnchor constraintEqualToAnchor:topAnchor constant:topConst],
        [notesLbl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.notesTextView.topAnchor constraintEqualToAnchor:notesLbl.bottomAnchor constant:4],
        [self.notesTextView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.notesTextView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.notesTextView.heightAnchor constraintEqualToConstant:80],
    ]];
    topAnchor = self.notesTextView.bottomAnchor;
    topConst = 16;

    // Version (read-only)
    self.versionLabel = [UILabel new];
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.versionLabel.font = [UIFont systemFontOfSize:13];
    self.versionLabel.textColor = [UIColor secondaryLabelColor];
    self.versionLabel.text = @"Version: (new)";
    [self.contentView addSubview:self.versionLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.versionLabel.topAnchor constraintEqualToAnchor:topAnchor constant:topConst],
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
    ]];
    topAnchor = self.versionLabel.bottomAnchor;
    topConst = 24;

    // Save button
    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.saveButton setTitle:@"Save New Version" forState:UIControlStateNormal];
    self.saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.saveButton.backgroundColor = [UIColor systemBlueColor];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveButton.layer.cornerRadius = 10;
    self.saveButton.layer.masksToBounds = YES;
    [self.saveButton addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.saveButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.saveButton.topAnchor constraintEqualToAnchor:topAnchor constant:topConst],
        [self.saveButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.saveButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.saveButton.heightAnchor constraintEqualToConstant:50],
    ]];
    topAnchor = self.saveButton.bottomAnchor;
    topConst = 12;

    // Deprecate button (admin only)
    BOOL isAdmin = [[CPAuthService sharedService] currentUserHasPermission:@"admin"];
    if (isAdmin && self.ruleUUID) {
        self.deprecateButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.deprecateButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.deprecateButton setTitle:@"Deprecate Rule" forState:UIControlStateNormal];
        self.deprecateButton.titleLabel.font = [UIFont systemFontOfSize:15];
        [self.deprecateButton setTitleColor:[UIColor systemOrangeColor] forState:UIControlStateNormal];
        self.deprecateButton.backgroundColor = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.1];
        self.deprecateButton.layer.cornerRadius = 10;
        self.deprecateButton.layer.masksToBounds = YES;
        [self.deprecateButton addTarget:self action:@selector(deprecateTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.deprecateButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.deprecateButton.topAnchor constraintEqualToAnchor:topAnchor constant:topConst],
            [self.deprecateButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
            [self.deprecateButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
            [self.deprecateButton.heightAnchor constraintEqualToConstant:50],
        ]];
        topAnchor = self.deprecateButton.bottomAnchor;
        topConst = 16;
    }

    // Price calculator
    [self buildPriceCalculatorWithTopAnchor:topAnchor topConst:topConst pad:pad];
}

- (void)buildPriceCalculatorWithTopAnchor:(NSLayoutYAxisAnchor *)top topConst:(CGFloat)topConst pad:(CGFloat)pad {
    UIView *calcCard = [UIView new];
    calcCard.translatesAutoresizingMaskIntoConstraints = NO;
    calcCard.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    calcCard.layer.cornerRadius = 12;
    calcCard.layer.masksToBounds = YES;
    [self.contentView addSubview:calcCard];

    UILabel *calcTitle = [UILabel new];
    calcTitle.translatesAutoresizingMaskIntoConstraints = NO;
    calcTitle.text = @"Price Calculator";
    calcTitle.font = [UIFont boldSystemFontOfSize:15];
    [calcCard addSubview:calcTitle];

    UILabel *durationLabel = [UILabel new];
    durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    durationLabel.text = @"Duration (seconds):";
    durationLabel.font = [UIFont systemFontOfSize:14];
    [calcCard addSubview:durationLabel];

    self.durationInputField = [UITextField new];
    self.durationInputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.durationInputField.placeholder = @"e.g. 3600";
    self.durationInputField.keyboardType = UIKeyboardTypeNumberPad;
    self.durationInputField.font = [UIFont systemFontOfSize:15];
    self.durationInputField.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
    self.durationInputField.layer.cornerRadius = 6;
    self.durationInputField.layer.masksToBounds = YES;
    self.durationInputField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 0)];
    self.durationInputField.leftViewMode = UITextFieldViewModeAlways;
    [self.durationInputField addTarget:self action:@selector(calculatePrice) forControlEvents:UIControlEventEditingChanged];
    [calcCard addSubview:self.durationInputField];

    self.calculatedPriceLabel = [UILabel new];
    self.calculatedPriceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.calculatedPriceLabel.text = @"Calculated price: —";
    self.calculatedPriceLabel.font = [UIFont boldSystemFontOfSize:20];
    self.calculatedPriceLabel.textColor = [UIColor systemGreenColor];
    [calcCard addSubview:self.calculatedPriceLabel];

    [NSLayoutConstraint activateConstraints:@[
        [calcCard.topAnchor constraintEqualToAnchor:top constant:topConst],
        [calcCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [calcCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [calcCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32],

        [calcTitle.topAnchor constraintEqualToAnchor:calcCard.topAnchor constant:12],
        [calcTitle.leadingAnchor constraintEqualToAnchor:calcCard.leadingAnchor constant:12],

        [durationLabel.topAnchor constraintEqualToAnchor:calcTitle.bottomAnchor constant:12],
        [durationLabel.leadingAnchor constraintEqualToAnchor:calcCard.leadingAnchor constant:12],

        [self.durationInputField.topAnchor constraintEqualToAnchor:durationLabel.bottomAnchor constant:6],
        [self.durationInputField.leadingAnchor constraintEqualToAnchor:calcCard.leadingAnchor constant:12],
        [self.durationInputField.trailingAnchor constraintEqualToAnchor:calcCard.trailingAnchor constant:-12],
        [self.durationInputField.heightAnchor constraintEqualToConstant:38],

        [self.calculatedPriceLabel.topAnchor constraintEqualToAnchor:self.durationInputField.bottomAnchor constant:12],
        [self.calculatedPriceLabel.leadingAnchor constraintEqualToAnchor:calcCard.leadingAnchor constant:12],
        [self.calculatedPriceLabel.bottomAnchor constraintEqualToAnchor:calcCard.bottomAnchor constant:-12],
    ]];
}

// ---------------------------------------------------------------------------
#pragma mark - Load existing rule
// ---------------------------------------------------------------------------

- (void)loadExistingRule {
    if (!self.ruleUUID) {
        self.title = @"New Pricing Rule";
        return;
    }
    self.title = @"Pricing Rule";
    NSManagedObjectContext *ctx = [[CPPricingService sharedService] mainContext];
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", self.ruleUUID];
    req.fetchLimit = 1;
    NSError *err;
    self.existingRule = [[ctx executeFetchRequest:req error:&err] firstObject];
    if (!self.existingRule) return;

    self.serviceTypeField.text = [self.existingRule valueForKey:@"serviceType"];
    self.vehicleClassField.text = [self.existingRule valueForKey:@"vehicleClass"];
    self.storeIDField.text = [self.existingRule valueForKey:@"storeID"];

    NSDecimalNumber *price = [self.existingRule valueForKey:@"basePrice"];
    self.basePriceField.text = price ? [NSString stringWithFormat:@"%.2f", price.doubleValue] : @"";

    NSDate *start = [self.existingRule valueForKey:@"effectiveStart"];
    if (start) self.effectiveStartPicker.date = start;

    NSDate *end = [self.existingRule valueForKey:@"effectiveEnd"];
    if (end) {
        self.hasEndDateSwitch.on = YES;
        self.effectiveEndPicker.date = end;
        self.effectiveEndPicker.hidden = NO;
    }

    self.tierJSONTextView.text = [self.existingRule valueForKey:@"tierJSON"];
    self.notesTextView.text = [self.existingRule valueForKey:@"notes"];

    NSNumber *version = [self.existingRule valueForKey:@"version"];
    NSInteger nextVersion = version ? version.integerValue + 1 : 1;
    self.versionLabel.text = [NSString stringWithFormat:@"Current version: %@  →  New version: %ld",
        version ?: @"?", (long)nextVersion];
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)endDateToggled:(UISwitch *)sender {
    [UIView animateWithDuration:0.2 animations:^{
        self.effectiveEndPicker.hidden = !sender.isOn;
    }];
}

- (void)saveTapped {
    NSString *serviceType = [self.serviceTypeField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (serviceType.length == 0) {
        [self showAlert:@"Validation Error" message:@"Service type is required."];
        return;
    }

    NSString *priceStr = self.basePriceField.text;
    if (priceStr.length == 0) {
        [self showAlert:@"Validation Error" message:@"Base price is required."];
        return;
    }
    NSDecimalNumber *price = [NSDecimalNumber decimalNumberWithString:priceStr];
    if ([price isEqualToNumber:[NSDecimalNumber notANumber]]) {
        [self showAlert:@"Validation Error" message:@"Invalid price format."];
        return;
    }

    // Validate tier JSON if provided
    NSString *tierJSON = [self.tierJSONTextView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (tierJSON.length > 0) {
        NSData *data = [tierJSON dataUsingEncoding:NSUTF8StringEncoding];
        NSError *jsonErr;
        [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr) {
            [self showAlert:@"Invalid JSON" message:[NSString stringWithFormat:@"Tier JSON is invalid: %@", jsonErr.localizedDescription]];
            return;
        }
    }

    self.saveButton.enabled = NO;
    [self.saveButton setTitle:@"Saving…" forState:UIControlStateNormal];

    [[CPPricingService sharedService]
        createPricingRuleWithServiceType:serviceType
        vehicleClass:self.vehicleClassField.text.length > 0 ? self.vehicleClassField.text : nil
        storeID:self.storeIDField.text.length > 0 ? self.storeIDField.text : nil
        basePrice:price
        effectiveStart:self.effectiveStartPicker.date
        effectiveEnd:self.hasEndDateSwitch.isOn ? self.effectiveEndPicker.date : nil
        tierJSON:tierJSON.length > 0 ? tierJSON : nil
        notes:self.notesTextView.text
        completion:^(NSString *uuid, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.saveButton.enabled = YES;
                [self.saveButton setTitle:@"Save New Version" forState:UIControlStateNormal];
                if (error) {
                    [self showAlert:@"Error" message:error.localizedDescription];
                } else {
                    [self.navigationController popViewControllerAnimated:YES];
                }
            });
        }];
}

- (void)deprecateTapped {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Deprecate Rule"
        message:@"This will set the effective end date to now, making this rule immediately inactive."
        preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Deprecate" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[CPPricingService sharedService] deprecateRuleWithUUID:self.ruleUUID completion:^(NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (err) {
                    [self showAlert:@"Error" message:err.localizedDescription];
                } else {
                    [self.navigationController popViewControllerAnimated:YES];
                }
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.deprecateButton;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)calculatePrice {
    NSString *durationStr = self.durationInputField.text;
    NSInteger duration = durationStr.integerValue;
    NSString *priceStr = self.basePriceField.text;
    NSDecimalNumber *basePrice = [NSDecimalNumber decimalNumberWithString:priceStr ?: @"0"];

    // Try to parse tier JSON for tiered pricing
    NSString *tierJSON = self.tierJSONTextView.text;
    if (tierJSON.length > 0) {
        NSData *data = [tierJSON dataUsingEncoding:NSUTF8StringEncoding];
        NSError *err;
        NSArray *tiers = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (!err && [tiers isKindOfClass:[NSArray class]]) {
            for (NSDictionary *tier in tiers) {
                NSNumber *maxDuration = tier[@"maxDuration"];
                NSNumber *tierPrice = tier[@"price"];
                if (maxDuration && tierPrice && duration <= maxDuration.integerValue) {
                    self.calculatedPriceLabel.text = [NSString stringWithFormat:@"Calculated price: $%.2f", tierPrice.doubleValue];
                    return;
                }
            }
        }
    }

    // Fallback to base price
    self.calculatedPriceLabel.text = [NSString stringWithFormat:@"Calculated price: $%.2f", basePrice.doubleValue];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
