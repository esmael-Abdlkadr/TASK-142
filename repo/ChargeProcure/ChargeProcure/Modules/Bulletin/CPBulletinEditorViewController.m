#import "CPBulletinEditorViewController.h"
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#import <PhotosUI/PhotosUI.h>

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
@class CPBulletinService;
@class CPImageCache;

@interface CPBulletinService : NSObject
+ (instancetype)sharedService;
- (NSManagedObjectContext *)mainContext;
- (nullable NSString *)createDraftWithTitle:(NSString *)title
                                 editorMode:(NSString *)editorMode
                                      error:(NSError **)error;
- (void)autosaveDraft:(NSString *)uuid
                title:(NSString *)title
              summary:(NSString *)summary
                 body:(NSString *)body
             bodyHTML:(NSString *_Nullable)bodyHTML
 recommendationWeight:(NSNumber *)weight
             isPinned:(BOOL)isPinned
          publishDate:(NSDate *_Nullable)publishDate
        unpublishDate:(NSDate *_Nullable)unpublishDate
           completion:(void(^)(NSString *savedUUID, NSError *_Nullable error))completion;
- (void)publishBulletinWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion;
- (void)setCoverImagePath:(NSString *)path forBulletinUUID:(NSString *)bulletinUUID;
- (void)setEditorMode:(NSInteger)mode forBulletinUUID:(NSString *)bulletinUUID;
@end

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

@interface CPBulletinEditorViewController () <UITextViewDelegate, UITextFieldDelegate,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    PHPickerViewControllerDelegate>

// Top segment
@property (nonatomic, strong) UISegmentedControl *editorModeSegment;

// Fields
@property (nonatomic, strong) UITextField *titleField;
@property (nonatomic, strong) UITextField *summaryField;
@property (nonatomic, strong) UILabel *summaryCounterLabel;
@property (nonatomic, strong) UITextView *bodyTextView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Weight
@property (nonatomic, strong) UISlider *weightSlider;
@property (nonatomic, strong) UILabel *weightValueLabel;

// Pin
@property (nonatomic, strong) UISwitch *pinSwitch;

// Schedule
@property (nonatomic, strong) UIDatePicker *publishDatePicker;
@property (nonatomic, strong) UIDatePicker *unpublishDatePicker;
@property (nonatomic, strong) UISwitch *schedulePublishSwitch;
@property (nonatomic, strong) UISwitch *scheduleUnpublishSwitch;

// Cover image
@property (nonatomic, strong) UIButton *coverImageButton;
@property (nonatomic, strong) UIImageView *coverImagePreview;
@property (nonatomic, strong) UIImage *pendingCoverImage;

// Autosave
@property (nonatomic, strong) NSTimer *autosaveTimer;
@property (nonatomic, strong) UILabel *savedIndicatorLabel;
@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Nav
@property (nonatomic, strong) UIBarButtonItem *publishBarButton;

// Formatting toolbar (WYSIWYG mode)
@property (nonatomic, strong) UIToolbar *formattingToolbar;

@end

@implementation CPBulletinEditorViewController

static const NSInteger kSummaryMaxLength = 280;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self setupNavigationBar];
    [self setupScrollView];
    [self setupEditorModeSegment];
    [self setupFields];
    [self setupWeightSlider];
    [self setupPinSwitch];
    [self setupScheduleSection];
    [self setupCoverImageSection];
    [self setupSavedIndicator];
    [self loadExistingBulletin];
    [self startAutosaveTimer];
    [self registerForResignActive];
}

- (void)dealloc {
    [self.autosaveTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
#pragma mark - Setup
// ---------------------------------------------------------------------------

- (void)setupNavigationBar {
    self.title = self.bulletinUUID ? @"Edit Bulletin" : @"New Bulletin";
    UIBarButtonItem *cancelBtn = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.publishBarButton = [[UIBarButtonItem alloc]
        initWithTitle:@"Publish"
                style:UIBarButtonItemStyleDone
               target:self
               action:@selector(publishTapped)];
    self.navigationItem.leftBarButtonItem = cancelBtn;
    self.navigationItem.rightBarButtonItem = self.publishBarButton;
}

- (void)setupScrollView {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.contentView = [UIView new];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
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

- (void)setupEditorModeSegment {
    self.editorModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Markdown", @"WYSIWYG"]];
    self.editorModeSegment.selectedSegmentIndex = 0;
    self.editorModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorModeSegment addTarget:self action:@selector(editorModeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.editorModeSegment];
    [NSLayoutConstraint activateConstraints:@[
        [self.editorModeSegment.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [self.editorModeSegment.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.editorModeSegment.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
    ]];
}

- (void)setupFields {
    const CGFloat pad = 16;

    // Section label helper
    UILabel *(^sectionLabel)(NSString *) = ^UILabel *(NSString *text) {
        UILabel *lbl = [UILabel new];
        lbl.translatesAutoresizingMaskIntoConstraints = NO;
        lbl.text = text;
        lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        lbl.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:lbl];
        return lbl;
    };

    UILabel *titleSectionLabel = sectionLabel(@"TITLE");
    [NSLayoutConstraint activateConstraints:@[
        [titleSectionLabel.topAnchor constraintEqualToAnchor:self.editorModeSegment.bottomAnchor constant:16],
        [titleSectionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
    ]];

    self.titleField = [UITextField new];
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleField.placeholder = @"Bulletin title…";
    self.titleField.font = [UIFont systemFontOfSize:17];
    self.titleField.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.titleField.layer.cornerRadius = 8;
    self.titleField.layer.masksToBounds = YES;
    self.titleField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    self.titleField.leftViewMode = UITextFieldViewModeAlways;
    self.titleField.delegate = self;
    [self.titleField addTarget:self action:@selector(fieldDidChange) forControlEvents:UIControlEventEditingChanged];
    [self.contentView addSubview:self.titleField];
    [NSLayoutConstraint activateConstraints:@[
        [self.titleField.topAnchor constraintEqualToAnchor:titleSectionLabel.bottomAnchor constant:4],
        [self.titleField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.titleField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.titleField.heightAnchor constraintEqualToConstant:44],
    ]];

    UILabel *sumSectionLabel = sectionLabel(@"SUMMARY");
    [NSLayoutConstraint activateConstraints:@[
        [sumSectionLabel.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:16],
        [sumSectionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
    ]];

    self.summaryField = [UITextField new];
    self.summaryField.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryField.placeholder = @"Brief summary (max 280 characters)…";
    self.summaryField.font = [UIFont systemFontOfSize:15];
    self.summaryField.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.summaryField.layer.cornerRadius = 8;
    self.summaryField.layer.masksToBounds = YES;
    self.summaryField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    self.summaryField.leftViewMode = UITextFieldViewModeAlways;
    self.summaryField.delegate = self;
    [self.summaryField addTarget:self action:@selector(summaryFieldChanged) forControlEvents:UIControlEventEditingChanged];
    [self.contentView addSubview:self.summaryField];

    self.summaryCounterLabel = [UILabel new];
    self.summaryCounterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryCounterLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.summaryCounterLabel.textColor = [UIColor secondaryLabelColor];
    self.summaryCounterLabel.text = @"0/280";
    self.summaryCounterLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.summaryCounterLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.summaryField.topAnchor constraintEqualToAnchor:sumSectionLabel.bottomAnchor constant:4],
        [self.summaryField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.summaryField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.summaryField.heightAnchor constraintEqualToConstant:44],

        [self.summaryCounterLabel.topAnchor constraintEqualToAnchor:self.summaryField.bottomAnchor constant:4],
        [self.summaryCounterLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];

    // Body
    UILabel *bodySectionLabel = sectionLabel(@"BODY");
    [NSLayoutConstraint activateConstraints:@[
        [bodySectionLabel.topAnchor constraintEqualToAnchor:self.summaryCounterLabel.bottomAnchor constant:12],
        [bodySectionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
    ]];

    // Formatting toolbar for WYSIWYG
    self.formattingToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
    UIBarButtonItem *boldItem = [[UIBarButtonItem alloc]
        initWithTitle:@"B" style:UIBarButtonItemStylePlain
        target:self action:@selector(insertBoldMarker)];
    UIBarButtonItem *italicItem = [[UIBarButtonItem alloc]
        initWithTitle:@"I" style:UIBarButtonItemStylePlain
        target:self action:@selector(insertItalicMarker)];
    UIBarButtonItem *h1Item = [[UIBarButtonItem alloc]
        initWithTitle:@"H1" style:UIBarButtonItemStylePlain
        target:self action:@selector(insertH1Marker)];
    UIBarButtonItem *h2Item = [[UIBarButtonItem alloc]
        initWithTitle:@"H2" style:UIBarButtonItemStylePlain
        target:self action:@selector(insertH2Marker)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
        target:nil action:nil];
    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(dismissKeyboard)];
    self.formattingToolbar.items = @[boldItem, italicItem, h1Item, h2Item, flex, doneItem];
    self.formattingToolbar.hidden = YES; // shown in WYSIWYG mode

    self.bodyTextView = [UITextView new];
    self.bodyTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bodyTextView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.bodyTextView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.bodyTextView.layer.cornerRadius = 8;
    self.bodyTextView.layer.masksToBounds = YES;
    self.bodyTextView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.bodyTextView.scrollEnabled = NO;
    self.bodyTextView.delegate = self;
    self.bodyTextView.inputAccessoryView = self.formattingToolbar;
    [self.contentView addSubview:self.bodyTextView];

    [NSLayoutConstraint activateConstraints:@[
        [self.bodyTextView.topAnchor constraintEqualToAnchor:bodySectionLabel.bottomAnchor constant:4],
        [self.bodyTextView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.bodyTextView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.bodyTextView.heightAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];

    // Keep reference to body bottom for chaining next section
    UIView *lastBodyView = self.bodyTextView;
    objc_setAssociatedObject(self, "lastBodyView", lastBodyView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setupWeightSlider {
    const CGFloat pad = 16;
    UILabel *sectionLabel = [UILabel new];
    sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sectionLabel.text = @"RECOMMENDATION WEIGHT";
    sectionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    sectionLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:sectionLabel];

    self.weightValueLabel = [UILabel new];
    self.weightValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.weightValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    self.weightValueLabel.text = @"50";
    [self.contentView addSubview:self.weightValueLabel];

    self.weightSlider = [UISlider new];
    self.weightSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.weightSlider.minimumValue = 0;
    self.weightSlider.maximumValue = 100;
    self.weightSlider.value = 50;
    [self.weightSlider addTarget:self action:@selector(weightSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.weightSlider];

    UIView *lastBodyView = objc_getAssociatedObject(self, "lastBodyView");

    [NSLayoutConstraint activateConstraints:@[
        [sectionLabel.topAnchor constraintEqualToAnchor:lastBodyView.bottomAnchor constant:16],
        [sectionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],

        [self.weightValueLabel.centerYAnchor constraintEqualToAnchor:sectionLabel.centerYAnchor],
        [self.weightValueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],

        [self.weightSlider.topAnchor constraintEqualToAnchor:sectionLabel.bottomAnchor constant:8],
        [self.weightSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.weightSlider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];
    objc_setAssociatedObject(self, "lastBodyView", self.weightSlider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setupPinSwitch {
    const CGFloat pad = 16;
    UIView *pinRow = [UIView new];
    pinRow.translatesAutoresizingMaskIntoConstraints = NO;
    pinRow.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    pinRow.layer.cornerRadius = 8;
    pinRow.layer.masksToBounds = YES;
    [self.contentView addSubview:pinRow];

    UILabel *pinLabel = [UILabel new];
    pinLabel.translatesAutoresizingMaskIntoConstraints = NO;
    pinLabel.text = @"Pin Bulletin";
    pinLabel.font = [UIFont systemFontOfSize:15];
    [pinRow addSubview:pinLabel];

    self.pinSwitch = [UISwitch new];
    self.pinSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pinSwitch addTarget:self action:@selector(fieldDidChange) forControlEvents:UIControlEventValueChanged];
    [pinRow addSubview:self.pinSwitch];

    UIView *prevSlider = objc_getAssociatedObject(self, "lastBodyView");
    [NSLayoutConstraint activateConstraints:@[
        [pinRow.topAnchor constraintEqualToAnchor:prevSlider.bottomAnchor constant:16],
        [pinRow.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [pinRow.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [pinRow.heightAnchor constraintEqualToConstant:48],

        [pinLabel.centerYAnchor constraintEqualToAnchor:pinRow.centerYAnchor],
        [pinLabel.leadingAnchor constraintEqualToAnchor:pinRow.leadingAnchor constant:12],

        [self.pinSwitch.centerYAnchor constraintEqualToAnchor:pinRow.centerYAnchor],
        [self.pinSwitch.trailingAnchor constraintEqualToAnchor:pinRow.trailingAnchor constant:-12],
    ]];
    objc_setAssociatedObject(self, "lastBodyView", pinRow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setupScheduleSection {
    const CGFloat pad = 16;
    UILabel *sectionLabel = [UILabel new];
    sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sectionLabel.text = @"SCHEDULE";
    sectionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    sectionLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:sectionLabel];

    UIView *prevView = objc_getAssociatedObject(self, "lastBodyView");

    // Publish date row (use local vars; ARC requires non-ivar targets for out-params)
    UISwitch *pubSw = nil; UIDatePicker *pubPk = nil;
    UIView *publishRow = [self makeScheduleRowWithLabel:@"Publish Date" switchRef:&pubSw picker:&pubPk];
    _schedulePublishSwitch = pubSw; _publishDatePicker = pubPk;

    UISwitch *unpubSw = nil; UIDatePicker *unpubPk = nil;
    UIView *unpublishRow = [self makeScheduleRowWithLabel:@"Unpublish Date (optional)" switchRef:&unpubSw picker:&unpubPk];
    _scheduleUnpublishSwitch = unpubSw; _unpublishDatePicker = unpubPk;

    [NSLayoutConstraint activateConstraints:@[
        [sectionLabel.topAnchor constraintEqualToAnchor:prevView.bottomAnchor constant:16],
        [sectionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],

        [publishRow.topAnchor constraintEqualToAnchor:sectionLabel.bottomAnchor constant:8],
        [publishRow.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [publishRow.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],

        [unpublishRow.topAnchor constraintEqualToAnchor:publishRow.bottomAnchor constant:8],
        [unpublishRow.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [unpublishRow.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];
    objc_setAssociatedObject(self, "lastBodyView", unpublishRow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIView *)makeScheduleRowWithLabel:(NSString *)labelText
                           switchRef:(UISwitch **)switchRef
                              picker:(UIDatePicker **)pickerRef {
    UIView *container = [UIView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    container.layer.cornerRadius = 8;
    container.layer.masksToBounds = YES;
    [self.contentView addSubview:container];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = labelText;
    label.font = [UIFont systemFontOfSize:15];
    [container addSubview:label];

    UISwitch *sw = [UISwitch new];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [sw addTarget:self action:@selector(scheduleToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:sw];
    *switchRef = sw;

    UIDatePicker *picker = [UIDatePicker new];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    picker.datePickerMode = UIDatePickerModeDateAndTime;
    picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    picker.hidden = YES;
    [container addSubview:picker];
    *pickerRef = picker;

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:picker.topAnchor constant:-8],

        [sw.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [sw.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],

        [picker.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [picker.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [picker.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
    ]];

    return container;
}

- (void)setupCoverImageSection {
    const CGFloat pad = 16;
    UIView *prevView = objc_getAssociatedObject(self, "lastBodyView");

    UILabel *sectionLabel = [UILabel new];
    sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sectionLabel.text = @"COVER IMAGE";
    sectionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    sectionLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:sectionLabel];

    self.coverImagePreview = [UIImageView new];
    self.coverImagePreview.translatesAutoresizingMaskIntoConstraints = NO;
    self.coverImagePreview.contentMode = UIViewContentModeScaleAspectFill;
    self.coverImagePreview.clipsToBounds = YES;
    self.coverImagePreview.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
    self.coverImagePreview.layer.cornerRadius = 8;
    self.coverImagePreview.hidden = YES;
    [self.contentView addSubview:self.coverImagePreview];

    self.coverImageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.coverImageButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *cameraImg = [UIImage systemImageNamed:@"photo.badge.plus"];
    [self.coverImageButton setImage:cameraImg forState:UIControlStateNormal];
    [self.coverImageButton setTitle:@"  Attach Cover Image" forState:UIControlStateNormal];
    self.coverImageButton.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.coverImageButton.layer.cornerRadius = 8;
    self.coverImageButton.layer.masksToBounds = YES;
    [self.coverImageButton addTarget:self action:@selector(attachCoverImage) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.coverImageButton];

    [NSLayoutConstraint activateConstraints:@[
        [sectionLabel.topAnchor constraintEqualToAnchor:prevView.bottomAnchor constant:16],
        [sectionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],

        [self.coverImagePreview.topAnchor constraintEqualToAnchor:sectionLabel.bottomAnchor constant:8],
        [self.coverImagePreview.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.coverImagePreview.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.coverImagePreview.heightAnchor constraintEqualToConstant:160],

        [self.coverImageButton.topAnchor constraintEqualToAnchor:self.coverImagePreview.bottomAnchor constant:8],
        [self.coverImageButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.coverImageButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.coverImageButton.heightAnchor constraintEqualToConstant:44],
        [self.coverImageButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32],
    ]];
}

- (void)setupSavedIndicator {
    self.savedIndicatorLabel = [UILabel new];
    self.savedIndicatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.savedIndicatorLabel.text = @"Saved";
    self.savedIndicatorLabel.font = [UIFont systemFontOfSize:12];
    self.savedIndicatorLabel.textColor = [UIColor systemGreenColor];
    self.savedIndicatorLabel.alpha = 0;
    [self.view addSubview:self.savedIndicatorLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.savedIndicatorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.savedIndicatorLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
    ]];
}

// ---------------------------------------------------------------------------
#pragma mark - Load existing data
// ---------------------------------------------------------------------------

- (void)loadExistingBulletin {
    if (!self.bulletinUUID) return;
    NSManagedObjectContext *ctx = [[CPBulletinService sharedService] mainContext];
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", self.bulletinUUID];
    req.fetchLimit = 1;
    NSError *err;
    NSManagedObject *b = [[ctx executeFetchRequest:req error:&err] firstObject];
    if (!b) return;

    self.titleField.text = [b valueForKey:@"title"];
    self.summaryField.text = [b valueForKey:@"summary"];
    NSString *body = [b valueForKey:@"body"] ?: @"";
    NSString *bodyHTML = [b valueForKey:@"bodyHTML"];
    NSNumber *weight = [b valueForKey:@"recommendationWeight"];
    self.weightSlider.value = weight ? weight.floatValue : 50.f;
    self.weightValueLabel.text = [NSString stringWithFormat:@"%.0f", self.weightSlider.value];
    self.pinSwitch.on = [[b valueForKey:@"isPinned"] boolValue];

    // Restore saved editor mode before rendering the body.
    NSNumber *modeVal = [b valueForKey:@"editorModeValue"];
    NSInteger savedMode = modeVal ? modeVal.integerValue : 0;
    self.editorModeSegment.selectedSegmentIndex = savedMode;

    if (savedMode == 1) {
        // WYSIWYG: load persisted HTML if available; fall back to markdown rendering.
        NSAttributedString *richContent = bodyHTML.length > 0
            ? [self attributedStringFromHTML:bodyHTML]
            : nil;
        self.bodyTextView.attributedText = richContent ?: [self attributedStringFromMarkdown:body];
        self.formattingToolbar.hidden = NO;
    } else {
        self.bodyTextView.text = body;
        self.bodyTextView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.formattingToolbar.hidden = YES;
    }

    [self summaryFieldChanged];
}

// ---------------------------------------------------------------------------
#pragma mark - Autosave
// ---------------------------------------------------------------------------

- (void)startAutosaveTimer {
    self.autosaveTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                          target:self
                                                        selector:@selector(autosave)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)registerForResignActive {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(autosave)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
}

- (void)autosave {
    if (!self.hasUnsavedChanges) return;
    NSString *title = self.titleField.text ?: @"";
    NSString *summary = self.summaryField.text ?: @"";
    NSInteger currentEditorMode = self.editorModeSegment.selectedSegmentIndex;
    BOOL isWYSIWYG = (currentEditorMode == 1);

    // In WYSIWYG mode persist the attributed body as HTML; keep the plain-text
    // string as the fallback body (body field).  In Markdown mode body is raw
    // markdown and bodyHTML is cleared so the detail view renders plain text.
    NSString *body = isWYSIWYG
        ? (self.bodyTextView.attributedText.string ?: @"")
        : (self.bodyTextView.text ?: @"");
    NSString *bodyHTML = isWYSIWYG
        ? [self htmlFromAttributedString:self.bodyTextView.attributedText]
        : nil;

    NSNumber *weight = @((NSInteger)self.weightSlider.value);
    BOOL isPinned = self.pinSwitch.isOn;
    NSDate *publishDate = self.schedulePublishSwitch.isOn ? self.publishDatePicker.date : nil;
    NSDate *unpublishDate = self.scheduleUnpublishSwitch.isOn ? self.unpublishDatePicker.date : nil;

    [[CPBulletinService sharedService]
        autosaveDraft:self.bulletinUUID ?: @""
                title:title
              summary:summary
                 body:body
             bodyHTML:bodyHTML
   recommendationWeight:weight
             isPinned:isPinned
          publishDate:publishDate
        unpublishDate:unpublishDate
           completion:^(NSString *savedUUID, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error) {
                if (!self.bulletinUUID) self.bulletinUUID = savedUUID;
                // Persist the editor mode so it is restored on next load.
                if (savedUUID.length > 0) {
                    [[CPBulletinService sharedService]
                     setEditorMode:currentEditorMode forBulletinUUID:savedUUID];
                }
                self.hasUnsavedChanges = NO;
                [self flashSavedIndicator];
                // Persist cover image to local sandbox if one was selected
                if (self.pendingCoverImage && savedUUID.length > 0) {
                    NSData *jpeg = UIImageJPEGRepresentation(self.pendingCoverImage, 0.85);
                    if (jpeg) {
                        NSURL *docs = [NSFileManager.defaultManager
                                       URLsForDirectory:NSDocumentDirectory
                                       inDomains:NSUserDomainMask].firstObject;
                        NSString *filename = [NSString stringWithFormat:@"bulletin_%@_cover.jpg", savedUUID];
                        NSURL *fileURL = [docs URLByAppendingPathComponent:filename];
                        if ([jpeg writeToURL:fileURL atomically:YES]) {
                            [[CPBulletinService sharedService]
                             setCoverImagePath:fileURL.path
                             forBulletinUUID:savedUUID];
                            self.pendingCoverImage = nil;
                        }
                    }
                }
            }
        });
    }];
}

- (void)flashSavedIndicator {
    self.savedIndicatorLabel.alpha = 1.0;
    [UIView animateWithDuration:1.5 delay:1.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.savedIndicatorLabel.alpha = 0.0;
    } completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)editorModeChanged:(UISegmentedControl *)sender {
    BOOL isWYSIWYG = (sender.selectedSegmentIndex == 1);
    if (isWYSIWYG) {
        // Entering WYSIWYG mode: if we have plain markdown text, convert it for display.
        // Preserve any already-attributed content (e.g. if toggling back and forth).
        NSString *plain = self.bodyTextView.text ?: @"";
        if (plain.length > 0 && self.bodyTextView.attributedText.length == plain.length) {
            // No existing rich content — render plain text using markdown pass.
            self.bodyTextView.attributedText = [self attributedStringFromMarkdown:plain];
        }
        self.formattingToolbar.hidden = NO;
    } else {
        // Switching back to Markdown mode: extract the plain-text (strip rich attributes).
        NSString *plain = self.bodyTextView.attributedText.string ?: self.bodyTextView.text ?: @"";
        self.bodyTextView.text = plain;
        self.bodyTextView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.bodyTextView.textColor = [UIColor labelColor];
        self.formattingToolbar.hidden = YES;
    }
    self.hasUnsavedChanges = YES;
}

- (void)fieldDidChange {
    self.hasUnsavedChanges = YES;
}

- (void)summaryFieldChanged {
    NSInteger len = self.summaryField.text.length;
    self.summaryCounterLabel.text = [NSString stringWithFormat:@"%ld/280", (long)len];
    self.summaryCounterLabel.textColor = (len > kSummaryMaxLength) ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
    self.hasUnsavedChanges = YES;
}

- (void)weightSliderChanged:(UISlider *)sender {
    self.weightValueLabel.text = [NSString stringWithFormat:@"%.0f", sender.value];
    self.hasUnsavedChanges = YES;
}

- (void)scheduleToggleChanged:(UISwitch *)sender {
    if (sender == self.schedulePublishSwitch) {
        [UIView animateWithDuration:0.2 animations:^{
            self.publishDatePicker.hidden = !sender.isOn;
        }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.unpublishDatePicker.hidden = !sender.isOn;
        }];
    }
    self.hasUnsavedChanges = YES;
}

- (void)attachCoverImage {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        config.filter = [PHPickerFilter imagesFilter];
        config.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)cancelTapped {
    if (self.hasUnsavedChanges) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Unsaved Changes"
            message:@"You have unsaved changes. Do you want to save as draft or discard?"
            preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save Draft" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self autosave];
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Discard" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Keep Editing" style:UIAlertActionStyleCancel handler:nil]];
        alert.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)publishTapped {
    NSInteger summaryLen = self.summaryField.text.length;
    if (summaryLen > kSummaryMaxLength) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Summary Too Long"
            message:[NSString stringWithFormat:@"Summary is %ld characters. Maximum is 280.", (long)summaryLen]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *confirm = [UIAlertController
        alertControllerWithTitle:@"Publish Bulletin"
        message:@"This will make the bulletin visible to all users. Continue?"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Publish" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self performPublish];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    confirm.popoverPresentationController.barButtonItem = self.publishBarButton;
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performPublish {
    // First autosave, then publish
    NSString *title = self.titleField.text ?: @"";
    NSString *summary = self.summaryField.text ?: @"";
    BOOL isWYSIWYG = (self.editorModeSegment.selectedSegmentIndex == 1);
    NSString *body = isWYSIWYG
        ? (self.bodyTextView.attributedText.string ?: @"")
        : (self.bodyTextView.text ?: @"");
    NSString *bodyHTML = isWYSIWYG
        ? [self htmlFromAttributedString:self.bodyTextView.attributedText]
        : nil;
    NSNumber *weight = @((NSInteger)self.weightSlider.value);
    BOOL isPinned = self.pinSwitch.isOn;
    NSDate *publishDate = self.schedulePublishSwitch.isOn ? self.publishDatePicker.date : nil;
    NSDate *unpublishDate = self.scheduleUnpublishSwitch.isOn ? self.unpublishDatePicker.date : nil;

    self.publishBarButton.enabled = NO;

    UIImage *imageToSave = self.pendingCoverImage;
    NSString *currentUUID = self.bulletinUUID;

    [[CPBulletinService sharedService]
        autosaveDraft:self.bulletinUUID ?: @""
                title:title
              summary:summary
                 body:body
             bodyHTML:bodyHTML
   recommendationWeight:weight
             isPinned:isPinned
          publishDate:publishDate
        unpublishDate:unpublishDate
           completion:^(NSString *savedUUID, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.publishBarButton.enabled = YES;
                [self showErrorAlert:error.localizedDescription];
            });
            return;
        }
        NSString *uuid = savedUUID ?: currentUUID;
        // Persist pending cover image before publish
        if (imageToSave && uuid.length > 0) {
            NSData *jpeg = UIImageJPEGRepresentation(imageToSave, 0.85);
            if (jpeg) {
                NSURL *docs = [NSFileManager.defaultManager
                               URLsForDirectory:NSDocumentDirectory
                               inDomains:NSUserDomainMask].firstObject;
                NSString *filename = [NSString stringWithFormat:@"bulletin_%@_cover.jpg", uuid];
                NSURL *fileURL = [docs URLByAppendingPathComponent:filename];
                if ([jpeg writeToURL:fileURL atomically:YES]) {
                    [[CPBulletinService sharedService]
                     setCoverImagePath:fileURL.path forBulletinUUID:uuid];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.pendingCoverImage = nil;
                    });
                }
            }
        }
        [[CPBulletinService sharedService] publishBulletinWithUUID:uuid completion:^(NSError *pubErr) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.publishBarButton.enabled = YES;
                if (pubErr) {
                    [self showErrorAlert:pubErr.localizedDescription];
                } else {
                    self.hasUnsavedChanges = NO;
                    [self dismissViewControllerAnimated:YES completion:nil];
                }
            });
        }];
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Formatting toolbar helpers
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// WYSIWYG formatting actions — apply/toggle NSAttributedString attributes directly.
// These operate on the selected text range and never insert Markdown syntax markers.
// ---------------------------------------------------------------------------

- (void)insertBoldMarker   { [self _toggleFontTrait:UIFontDescriptorTraitBold]; }
- (void)insertItalicMarker { [self _toggleFontTrait:UIFontDescriptorTraitItalic]; }
- (void)insertH1Marker     { [self _applyHeadingFontSize:22 weight:UIFontWeightBold]; }
- (void)insertH2Marker     { [self _applyHeadingFontSize:18 weight:UIFontWeightSemibold]; }

/// Toggle bold or italic on the selected range. If all selected glyphs already
/// carry the trait it is removed; otherwise it is added to all of them.
- (void)_toggleFontTrait:(UIFontDescriptorSymbolicTraits)trait {
    UITextRange *textRange = self.bodyTextView.selectedTextRange;
    if (!textRange) return;
    NSRange nsRange = [self _nsRangeFromTextRange:textRange inTextView:self.bodyTextView];
    if (nsRange.length == 0) return;

    NSMutableAttributedString *attrStr = [self.bodyTextView.attributedText mutableCopy];

    // Check whether every character in the selection already carries the trait.
    __block BOOL allHaveTrait = YES;
    [attrStr enumerateAttribute:NSFontAttributeName
                        inRange:nsRange
                        options:0
                     usingBlock:^(UIFont *font, NSRange r, BOOL *stop) {
        UIFont *f = font ?: [UIFont systemFontOfSize:15];
        if (!(f.fontDescriptor.symbolicTraits & trait)) {
            allHaveTrait = NO;
            *stop = YES;
        }
    }];

    // Apply or remove the trait across the selection.
    [attrStr enumerateAttribute:NSFontAttributeName
                        inRange:nsRange
                        options:0
                     usingBlock:^(UIFont *existingFont, NSRange r, BOOL *stop) {
        UIFont *base = existingFont ?: [UIFont systemFontOfSize:15];
        UIFontDescriptorSymbolicTraits current = base.fontDescriptor.symbolicTraits;
        UIFontDescriptorSymbolicTraits updated = allHaveTrait
            ? (current & ~trait)
            : (current | trait);
        UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorWithSymbolicTraits:updated];
        UIFont *newFont = [UIFont fontWithDescriptor:desc size:base.pointSize] ?: base;
        [attrStr addAttribute:NSFontAttributeName value:newFont range:r];
    }];

    self.bodyTextView.attributedText = [attrStr copy];
    self.bodyTextView.selectedTextRange = textRange;
    self.hasUnsavedChanges = YES;
}

/// Apply a heading-style font to the selected range.
- (void)_applyHeadingFontSize:(CGFloat)size weight:(UIFontWeight)weight {
    UITextRange *textRange = self.bodyTextView.selectedTextRange;
    if (!textRange) return;
    NSRange nsRange = [self _nsRangeFromTextRange:textRange inTextView:self.bodyTextView];
    if (nsRange.length == 0) return;

    NSMutableAttributedString *attrStr = [self.bodyTextView.attributedText mutableCopy];
    UIFont *headingFont = [UIFont systemFontOfSize:size weight:weight];
    [attrStr addAttribute:NSFontAttributeName value:headingFont range:nsRange];

    self.bodyTextView.attributedText = [attrStr copy];
    self.bodyTextView.selectedTextRange = textRange;
    self.hasUnsavedChanges = YES;
}

/// Convert a UITextRange to an NSRange using the text view's offset API.
- (NSRange)_nsRangeFromTextRange:(UITextRange *)range inTextView:(UITextView *)tv {
    NSInteger start  = [tv offsetFromPosition:tv.beginningOfDocument toPosition:range.start];
    NSInteger length = [tv offsetFromPosition:range.start toPosition:range.end];
    return NSMakeRange((NSUInteger)MAX(start, 0), (NSUInteger)MAX(length, 0));
}

- (void)dismissKeyboard { [self.bodyTextView resignFirstResponder]; }

// ---------------------------------------------------------------------------
#pragma mark - UITextViewDelegate
// ---------------------------------------------------------------------------

- (void)textViewDidChange:(UITextView *)textView {
    // In WYSIWYG mode the text view manages its own NSAttributedString directly.
    // Do NOT re-render from Markdown here — that would destroy any attributes the
    // user applied via the formatting toolbar.
    self.hasUnsavedChanges = YES;
}

// ---------------------------------------------------------------------------
#pragma mark - PHPickerViewControllerDelegate
// ---------------------------------------------------------------------------

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;
    [result.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(__kindof id<NSItemProviderReading> obj, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *image = (UIImage *)obj;
            if (image) {
                self.pendingCoverImage = image;
                self.coverImagePreview.image = image;
                self.coverImagePreview.hidden = NO;
                self.hasUnsavedChanges = YES;
            }
        });
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - UIImagePickerControllerDelegate (iOS < 14 fallback)
// ---------------------------------------------------------------------------

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) {
        self.pendingCoverImage = image;
        self.coverImagePreview.image = image;
        self.coverImagePreview.hidden = NO;
        self.hasUnsavedChanges = YES;
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Rich-text ↔ HTML serialization
// ---------------------------------------------------------------------------

/// Serialize an NSAttributedString to an HTML string using the system HTML writer.
/// Returns nil for empty attributed strings.
- (nullable NSString *)htmlFromAttributedString:(NSAttributedString *)attrStr {
    if (!attrStr || attrStr.length == 0) return nil;
    NSError *err = nil;
    NSData *data = [attrStr dataFromRange:NSMakeRange(0, attrStr.length)
                       documentAttributes:@{
                           NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                           NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)
                       }
                                    error:&err];
    if (!data || err) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

/// Deserialize an HTML string back to NSAttributedString for display in the editor.
/// Returns nil on parse failure.
- (nullable NSAttributedString *)attributedStringFromHTML:(NSString *)html {
    if (!html.length) return nil;
    NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    NSError *err = nil;
    NSAttributedString *result = [[NSAttributedString alloc]
        initWithData:data
            options:@{
                NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)
            }
  documentAttributes:nil
               error:&err];
    return err ? nil : result;
}

// ---------------------------------------------------------------------------
#pragma mark - Markdown → NSAttributedString (legacy / fallback rendering)
// ---------------------------------------------------------------------------

/// Converts plain Markdown text to a styled NSAttributedString.
/// Used as a **fallback** when loading a bulletin that has no persisted bodyHTML
/// (e.g. bulletins created before the WYSIWYG upgrade).
/// In the live editor, typed text is preserved as-is via NSAttributedString —
/// this method is NOT called on every keystroke.
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    if (!markdown.length) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    UIFont *bodyFont   = [UIFont systemFontOfSize:15];
    UIColor *bodyColor = [UIColor labelColor];
    NSDictionary *baseAttrs = @{NSFontAttributeName: bodyFont,
                                NSForegroundColorAttributeName: bodyColor};

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray<NSString *> *lines = [markdown componentsSeparatedByString:@"\n"];

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];

        if ([line hasPrefix:@"# "]) {
            NSDictionary *h1 = @{
                NSFontAttributeName: [UIFont systemFontOfSize:22 weight:UIFontWeightBold],
                NSForegroundColorAttributeName: bodyColor,
            };
            [result appendAttributedString:
             [[NSAttributedString alloc] initWithString:[line substringFromIndex:2] attributes:h1]];

        } else if ([line hasPrefix:@"## "]) {
            NSDictionary *h2 = @{
                NSFontAttributeName: [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName: bodyColor,
            };
            [result appendAttributedString:
             [[NSAttributedString alloc] initWithString:[line substringFromIndex:3] attributes:h2]];

        } else {
            // Inline bold/italic scan
            NSMutableAttributedString *lineAttr = [[NSMutableAttributedString alloc] init];
            NSString *rem = line;

            while (rem.length > 0) {
                // Locate first ** or * in remaining text
                NSRange boldStart  = [rem rangeOfString:@"**"];
                NSRange italicStart = [rem rangeOfString:@"*"];

                BOOL hasBold   = boldStart.location != NSNotFound;
                BOOL hasItalic = italicStart.location != NSNotFound;

                if (hasBold && (!hasItalic || boldStart.location <= italicStart.location)) {
                    // Append text before **
                    if (boldStart.location > 0) {
                        NSString *pre = [rem substringToIndex:boldStart.location];
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:pre attributes:baseAttrs]];
                    }
                    NSString *after = [rem substringFromIndex:boldStart.location + 2];
                    NSRange closing = [after rangeOfString:@"**"];
                    if (closing.location != NSNotFound) {
                        NSString *bold = [after substringToIndex:closing.location];
                        NSDictionary *boldAttrs = @{
                            NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
                            NSForegroundColorAttributeName: bodyColor,
                        };
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:bold attributes:boldAttrs]];
                        rem = [after substringFromIndex:closing.location + 2];
                    } else {
                        // Unclosed **: treat as literal
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:@"**" attributes:baseAttrs]];
                        rem = after;
                    }

                } else if (hasItalic) {
                    // Append text before *
                    if (italicStart.location > 0) {
                        NSString *pre = [rem substringToIndex:italicStart.location];
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:pre attributes:baseAttrs]];
                    }
                    NSString *after = [rem substringFromIndex:italicStart.location + 1];
                    NSRange closing = [after rangeOfString:@"*"];
                    if (closing.location != NSNotFound) {
                        NSString *italic = [after substringToIndex:closing.location];
                        NSDictionary *italicAttrs = @{
                            NSFontAttributeName: [UIFont italicSystemFontOfSize:15],
                            NSForegroundColorAttributeName: bodyColor,
                        };
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:italic attributes:italicAttrs]];
                        rem = [after substringFromIndex:closing.location + 1];
                    } else {
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:@"*" attributes:baseAttrs]];
                        rem = after;
                    }
                } else {
                    [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:rem attributes:baseAttrs]];
                    rem = @"";
                }
            }
            [result appendAttributedString:lineAttr];
        }

        if (i < lines.count - 1) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:baseAttrs]];
        }
    }
    return [result copy];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

- (void)showErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Error"
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
