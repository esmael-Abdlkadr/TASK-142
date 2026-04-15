#import "CPBulletinDetailViewController.h"
#import <CoreData/CoreData.h>
#import "CPBulletinEditorViewController.h"
#import "../../Core/CoreData/CPCoreDataStack.h"
#import "../../Core/CoreData/Entities/CPBulletin+CoreDataClass.h"

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
@class CPBulletinService;
@class CPImageCache;
@class CPAuthService;

@interface CPBulletinService : NSObject
+ (instancetype)sharedService;
- (NSManagedObjectContext *)mainContext;
- (void)archiveBulletinWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion;
- (void)restoreDraftBulletinWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion;
- (NSArray *)fetchVersionsForBulletin:(NSString *)bulletinUUID;
- (BOOL)restoreVersion:(NSString *)versionUUID toBulletin:(NSString *)bulletinUUID error:(NSError **)error;
@end

@interface CPImageCache : NSObject
+ (instancetype)sharedCache;
- (void)loadImageFromURLString:(NSString *)urlString
                    completion:(void(^)(UIImage *_Nullable image, NSError *_Nullable error))completion;
@end

@interface CPAuthService : NSObject
+ (instancetype)sharedService;
- (BOOL)currentUserHasPermission:(NSString *)permission;
- (NSString *)currentUserID;
@end

// ---------------------------------------------------------------------------
// Version History VC — real implementation
// ---------------------------------------------------------------------------
@interface CPBulletinVersionHistoryViewController : UITableViewController
@property (nonatomic, strong) NSString *bulletinUUID;
@end

@implementation CPBulletinVersionHistoryViewController {
    NSArray *_versions;
    NSDateFormatter *_df;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Version History";
    _df = [[NSDateFormatter alloc] init];
    _df.dateStyle = NSDateFormatterMediumStyle;
    _df.timeStyle = NSDateFormatterShortStyle;
    [self reloadVersions];
}

- (void)reloadVersions {
    _versions = [[CPBulletinService sharedService] fetchVersionsForBulletin:self.bulletinUUID];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_versions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"VersionCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"VersionCell"];
    }
    NSManagedObject *ver = _versions[(NSUInteger)indexPath.row];
    NSInteger vNum    = [[ver valueForKey:@"versionNumber"] integerValue];
    NSDate   *date    = [ver valueForKey:@"createdAt"];
    NSString *author  = [ver valueForKey:@"createdByUserID"] ?: @"unknown";
    cell.textLabel.text       = [NSString stringWithFormat:@"v%ld  •  %@", (long)vNum, author];
    cell.detailTextLabel.text = date ? [_df stringFromDate:date] : @"";
    cell.accessoryType        = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSManagedObject *ver     = _versions[(NSUInteger)indexPath.row];
    NSString *versionUUID    = [ver valueForKey:@"uuid"];
    NSInteger vNum           = [[ver valueForKey:@"versionNumber"] integerValue];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Restore to v%ld", (long)vNum]
        message:@"The bulletin will be reverted to this version as a new draft. Continue?"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restore"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        NSError *err = nil;
        BOOL ok = [[CPBulletinService sharedService]
                   restoreVersion:versionUUID
                       toBulletin:self.bulletinUUID
                            error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                UIAlertController *errAlert = [UIAlertController
                    alertControllerWithTitle:@"Restore Failed"
                    message:err.localizedDescription
                    preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                            style:UIAlertActionStyleDefault
                                                          handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
            } else {
                [self.navigationController popViewControllerAnimated:YES];
            }
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
@interface CPBulletinDetailViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *coverImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *pinnedBadgeLabel;
@property (nonatomic, strong) UILabel *weightLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UITextView *bodyTextView;
@property (nonatomic, strong) UIButton *versionHistoryButton;
@property (nonatomic, strong) UIButton *archiveRestoreButton;
@property (nonatomic, strong) NSManagedObject *bulletin;
@end

@implementation CPBulletinDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self setupScrollView];
    [self setupShareButton];
    [self loadBulletin];
}

- (void)setupScrollView {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
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

- (void)setupShareButton {
    UIBarButtonItem *shareBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(shareBulletin)];
    self.navigationItem.rightBarButtonItem = shareBtn;
}

- (void)loadBulletin {
    if (!self.bulletinUUID) return;
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", self.bulletinUUID];
    req.fetchLimit = 1;
    NSError *err;
    NSArray *results = [ctx executeFetchRequest:req error:&err];
    self.bulletin = results.firstObject;
    if (self.bulletin) {
        [self buildUI];
    }
}

- (void)buildUI {
    NSManagedObject *b = self.bulletin;
    const CGFloat pad = 16;
    UIView *prev = self.contentView;
    CGFloat prevBottom = 0;

    // Cover image
    self.coverImageView = [UIImageView new];
    self.coverImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.coverImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverImageView.clipsToBounds = YES;
    self.coverImageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [self.contentView addSubview:self.coverImageView];
    [NSLayoutConstraint activateConstraints:@[
        [self.coverImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.coverImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.coverImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.coverImageView.heightAnchor constraintEqualToConstant:200],
    ]];

    NSString *coverPath = [b valueForKey:@"coverImagePath"];
    if (coverPath.length > 0) {
        UIImage *coverImage = [UIImage imageWithContentsOfFile:coverPath];
        if (coverImage) self.coverImageView.image = coverImage;
    }

    // Title row
    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.text = [b valueForKey:@"title"] ?: @"(Untitled)";
    [self.contentView addSubview:self.titleLabel];

    self.pinnedBadgeLabel = [UILabel new];
    self.pinnedBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pinnedBadgeLabel.text = @" Pinned ";
    self.pinnedBadgeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.pinnedBadgeLabel.textColor = [UIColor systemOrangeColor];
    self.pinnedBadgeLabel.backgroundColor = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.12];
    self.pinnedBadgeLabel.layer.cornerRadius = 6;
    self.pinnedBadgeLabel.layer.masksToBounds = YES;
    BOOL isPinned = [[b valueForKey:@"isPinned"] boolValue];
    self.pinnedBadgeLabel.hidden = !isPinned;
    [self.contentView addSubview:self.pinnedBadgeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.coverImageView.bottomAnchor constant:pad],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],

        [self.pinnedBadgeLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
        [self.pinnedBadgeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
    ]];

    // Pinned navigation title icon
    if (isPinned) {
        UIImage *pinImg = [UIImage systemImageNamed:@"pin.fill"];
        UIImageView *pinNav = [[UIImageView alloc] initWithImage:pinImg];
        pinNav.tintColor = [UIColor systemOrangeColor];
        UILabel *titleView = [UILabel new];
        titleView.text = self.title;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[pinNav, titleView]];
        stack.spacing = 4;
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.alignment = UIStackViewAlignmentCenter;
        self.navigationItem.titleView = stack;
    }

    // Weight
    self.weightLabel = [UILabel new];
    self.weightLabel.translatesAutoresizingMaskIntoConstraints = NO;
    NSNumber *weight = [b valueForKey:@"recommendationWeight"];
    self.weightLabel.text = [NSString stringWithFormat:@"Recommendation weight: %@", weight ?: @"0"];
    self.weightLabel.font = [UIFont systemFontOfSize:13];
    self.weightLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.weightLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.weightLabel.topAnchor constraintEqualToAnchor:self.pinnedBadgeLabel.bottomAnchor constant:8],
        [self.weightLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.weightLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];

    // Summary
    self.summaryLabel = [UILabel new];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.text = [b valueForKey:@"summary"];
    self.summaryLabel.font = [UIFont systemFontOfSize:15];
    self.summaryLabel.textColor = [UIColor secondaryLabelColor];
    self.summaryLabel.numberOfLines = 0;
    [self.contentView addSubview:self.summaryLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.weightLabel.bottomAnchor constant:12],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];

    // Separator
    UIView *sep = [UIView new];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [UIColor separatorColor];
    [self.contentView addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor constraintEqualToAnchor:self.summaryLabel.bottomAnchor constant:12],
        [sep.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [sep.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [sep.heightAnchor constraintEqualToConstant:0.5],
    ]];

    // Body
    self.bodyTextView = [UITextView new];
    self.bodyTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bodyTextView.editable = NO;
    self.bodyTextView.scrollEnabled = NO;
    self.bodyTextView.font = [UIFont systemFontOfSize:15];
    self.bodyTextView.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
    self.bodyTextView.textContainer.lineFragmentPadding = 0;
    // Prefer persisted HTML (written by the WYSIWYG editor) for fidelity.
    // Fall back to Markdown rendering for bulletins without an HTML body.
    NSString *bodyHTML = [b valueForKey:@"bodyHTML"];
    NSString *bodyMD   = [b valueForKey:@"body"] ?: @"";
    NSAttributedString *renderedBody = nil;
    if (bodyHTML.length > 0) {
        NSData *htmlData = [bodyHTML dataUsingEncoding:NSUTF8StringEncoding];
        if (htmlData) {
            NSError *htmlErr = nil;
            renderedBody = [[NSAttributedString alloc]
                initWithData:htmlData
                    options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                              NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)}
          documentAttributes:nil
                       error:&htmlErr];
            if (htmlErr) renderedBody = nil;
        }
    }
    self.bodyTextView.attributedText = renderedBody ?: [self attributedStringFromMarkdown:bodyMD];
    [self.contentView addSubview:self.bodyTextView];

    [NSLayoutConstraint activateConstraints:@[
        [self.bodyTextView.topAnchor constraintEqualToAnchor:sep.bottomAnchor constant:12],
        [self.bodyTextView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.bodyTextView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
    ]];

    UIView *lastView = self.bodyTextView;

    // Version history button (admin/author only)
    BOOL isAdmin = [[CPAuthService sharedService] currentUserHasPermission:@"admin"];
    NSString *authorUUID = [b valueForKey:@"authorID"];
    NSString *currentUUID = [[CPAuthService sharedService] currentUserID];
    if (isAdmin || [authorUUID isEqualToString:currentUUID]) {
        self.versionHistoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.versionHistoryButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.versionHistoryButton setTitle:@"View Version History" forState:UIControlStateNormal];
        [self.versionHistoryButton addTarget:self action:@selector(showVersionHistory) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.versionHistoryButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.versionHistoryButton.topAnchor constraintEqualToAnchor:lastView.bottomAnchor constant:16],
            [self.versionHistoryButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        ]];
        lastView = self.versionHistoryButton;
    }

    // Archive/Restore button
    CPBulletinStatus status = (CPBulletinStatus)[[b valueForKey:@"statusValue"] integerValue];
    BOOL canArchive = [[CPAuthService sharedService] currentUserHasPermission:@"bulletin.archive"];
    if (canArchive) {
        self.archiveRestoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.archiveRestoreButton.translatesAutoresizingMaskIntoConstraints = NO;
        if (status == CPBulletinStatusArchived) {
            [self.archiveRestoreButton setTitle:@"Restore to Draft" forState:UIControlStateNormal];
            [self.archiveRestoreButton setTitleColor:[UIColor systemGreenColor] forState:UIControlStateNormal];
            [self.archiveRestoreButton addTarget:self action:@selector(restoreDraft) forControlEvents:UIControlEventTouchUpInside];
        } else {
            [self.archiveRestoreButton setTitle:@"Archive Bulletin" forState:UIControlStateNormal];
            [self.archiveRestoreButton setTitleColor:[UIColor systemOrangeColor] forState:UIControlStateNormal];
            [self.archiveRestoreButton addTarget:self action:@selector(archiveBulletin) forControlEvents:UIControlEventTouchUpInside];
        }
        [self.contentView addSubview:self.archiveRestoreButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.archiveRestoreButton.topAnchor constraintEqualToAnchor:lastView.bottomAnchor constant:12],
            [self.archiveRestoreButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        ]];
        lastView = self.archiveRestoreButton;
    }

    [NSLayoutConstraint activateConstraints:@[
        [lastView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32],
    ]];

    self.title = [b valueForKey:@"title"] ?: @"Bulletin";
}

// ---------------------------------------------------------------------------
#pragma mark - Markdown Parser
// ---------------------------------------------------------------------------

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    UIFont *baseFont = [UIFont systemFontOfSize:15];

    for (NSString *rawLine in lines) {
        NSString *line = rawLine;
        NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithObject:baseFont forKey:NSFontAttributeName];
        NSString *appended;

        // Header detection
        if ([line hasPrefix:@"### "]) {
            line = [line substringFromIndex:4];
            attrs[NSFontAttributeName] = [UIFont boldSystemFontOfSize:16];
        } else if ([line hasPrefix:@"## "]) {
            line = [line substringFromIndex:3];
            attrs[NSFontAttributeName] = [UIFont boldSystemFontOfSize:18];
        } else if ([line hasPrefix:@"# "]) {
            line = [line substringFromIndex:2];
            attrs[NSFontAttributeName] = [UIFont boldSystemFontOfSize:20];
        }

        // Inline bold/italic pass
        NSMutableAttributedString *lineAS = [[NSMutableAttributedString alloc] initWithString:line attributes:attrs];
        [self applyInlineMarkdownTo:lineAS baseFont:attrs[NSFontAttributeName]];

        NSMutableAttributedString *withNewline = [[NSMutableAttributedString alloc] initWithAttributedString:lineAS];
        [withNewline appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [result appendAttributedString:withNewline];
    }
    return result;
}

- (void)applyInlineMarkdownTo:(NSMutableAttributedString *)as baseFont:(UIFont *)base {
    // Bold: **text**
    NSRegularExpression *boldRegex = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*(.+?)\\*\\*" options:0 error:nil];
    NSString *str = as.string;
    NSArray *boldMatches = [boldRegex matchesInString:str options:0 range:NSMakeRange(0, str.length)];
    // Process in reverse to preserve ranges
    for (NSTextCheckingResult *match in [boldMatches reverseObjectEnumerator]) {
        NSRange outerRange = match.range;
        NSRange innerRange = [match rangeAtIndex:1];
        NSString *inner = [str substringWithRange:innerRange];
        UIFont *boldFont = [UIFont boldSystemFontOfSize:base.pointSize];
        NSAttributedString *replacement = [[NSAttributedString alloc] initWithString:inner attributes:@{NSFontAttributeName: boldFont}];
        [as replaceCharactersInRange:outerRange withAttributedString:replacement];
    }

    // Italic: *text*
    str = as.string;
    NSRegularExpression *italicRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)" options:0 error:nil];
    NSArray *italicMatches = [italicRegex matchesInString:str options:0 range:NSMakeRange(0, str.length)];
    for (NSTextCheckingResult *match in [italicMatches reverseObjectEnumerator]) {
        NSRange outerRange = match.range;
        NSRange innerRange = [match rangeAtIndex:1];
        NSString *inner = [str substringWithRange:innerRange];
        UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
        UIFont *italicFont = [UIFont fontWithDescriptor:desc size:base.pointSize];
        NSAttributedString *replacement = [[NSAttributedString alloc] initWithString:inner attributes:@{NSFontAttributeName: italicFont ?: base}];
        [as replaceCharactersInRange:outerRange withAttributedString:replacement];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)showVersionHistory {
    CPBulletinVersionHistoryViewController *vc = [CPBulletinVersionHistoryViewController new];
    vc.bulletinUUID = self.bulletinUUID;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)archiveBulletin {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Archive Bulletin"
        message:@"This bulletin will be archived and hidden from users."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Archive" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[CPBulletinService sharedService] archiveBulletinWithUUID:self.bulletinUUID completion:^(NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (err) {
                    [self showErrorAlert:err.localizedDescription];
                } else {
                    [self.navigationController popViewControllerAnimated:YES];
                }
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreDraft {
    [[CPBulletinService sharedService] restoreDraftBulletinWithUUID:self.bulletinUUID completion:^(NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) {
                [self showErrorAlert:err.localizedDescription];
            } else {
                [self.navigationController popViewControllerAnimated:YES];
            }
        });
    }];
}

- (void)shareBulletin {
    NSString *title = [self.bulletin valueForKey:@"title"] ?: @"Bulletin";
    NSString *summary = [self.bulletin valueForKey:@"summary"] ?: @"";
    NSString *shareText = [NSString stringWithFormat:@"%@\n\n%@", title, summary];
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[shareText]
        applicationActivities:nil];
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)showErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Error"
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
