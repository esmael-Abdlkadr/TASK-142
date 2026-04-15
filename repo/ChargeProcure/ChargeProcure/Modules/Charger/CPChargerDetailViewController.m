// CPChargerDetailViewController.m
// ChargeProcure
//
// Full detail screen for a single charger: info, RBAC-gated commands,
// pending-review list, recent events, and admin parameter editor.

#import "CPChargerDetailViewController.h"
#import "CPCharger+CoreDataClass.h"
#import "CPCharger+CoreDataProperties.h"
#import "CPChargerService.h"
#import "CPRBACService.h"
#import "CPCoreDataStack.h"
#import "CPDateFormatter.h"
#import "CPAuditService.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// MARK: - Section indices
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, CPDetailSection) {
    CPDetailSectionHeader        = 0,
    CPDetailSectionInfo          = 1,
    CPDetailSectionCommands      = 2,
    CPDetailSectionPendingReview = 3,
    CPDetailSectionRecentEvents  = 4,
    CPDetailSectionParameters    = 5,
    CPDetailSectionCount         = 6,
};

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface CPChargerDetailViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView      *tableView;
@property (nonatomic, strong) CPCharger        *charger;
@property (nonatomic, strong) NSArray          *pendingReviewCommands;
@property (nonatomic, strong) NSArray          *recentEvents;

// Command execution state
@property (nonatomic, assign) BOOL              isExecutingCommand;
@property (nonatomic, strong) UIProgressView   *commandProgressView;
@property (nonatomic, strong) NSTimer          *commandTimer;
@property (nonatomic, assign) NSTimeInterval    commandElapsed;

// Parameter editor (admin only)
@property (nonatomic, strong) UITextView       *parameterTextView;
@property (nonatomic, strong) UIButton         *saveParametersButton;

// Cached RBAC flags
@property (nonatomic, assign) BOOL canExecuteCommands;
@property (nonatomic, assign) BOOL canEditParameters;

@end

// ---------------------------------------------------------------------------
// MARK: - Implementation
// ---------------------------------------------------------------------------

static NSTimeInterval const kCommandTimeoutSeconds = 8.0;

@implementation CPChargerDetailViewController

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self loadCharger];
    [self checkPermissions];
    [self buildTableView];
    [self buildCommandProgressBar];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(commandAcknowledged:)
                                                 name:CPCommandAcknowledgedNotification
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopCommandTimer];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopCommandTimer];
}

// ---------------------------------------------------------------------------
#pragma mark - Data Loading
// ---------------------------------------------------------------------------

- (void)loadCharger {
    if (!self.chargerUUID) { return; }
    self.charger = (CPCharger *)[[CPChargerService sharedService] fetchChargerWithUUID:self.chargerUUID];
    self.title = self.charger.model ?: @"Charger Detail";

    // Load pending review commands
    self.pendingReviewCommands = [[CPChargerService sharedService] fetchPendingReviewCommands];
    // Filter to commands for this charger (commands are NSManagedObjects).
    // The Command entity stores the charger identifier under the key "chargerID"
    // (set by CPChargerService.issueCommand:); "chargerUUID" does not exist on Command.
    NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
        NSManagedObject *cmd = (NSManagedObject *)obj;
        NSString *cUUID = [cmd valueForKey:@"chargerID"];
        return [cUUID isEqualToString:self.chargerUUID];
    }];
    self.pendingReviewCommands = [self.pendingReviewCommands filteredArrayUsingPredicate:pred];

    // Load last 10 audit events for this charger
    self.recentEvents = [[CPAuditService sharedService]
                         fetchEventsForResource:@"Charger"
                                     resourceID:self.chargerUUID];
    if (self.recentEvents.count > 10) {
        self.recentEvents = [self.recentEvents subarrayWithRange:NSMakeRange(0, 10)];
    }
}

- (void)reloadData {
    [self loadCharger];
    [self.tableView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - RBAC
// ---------------------------------------------------------------------------

- (void)checkPermissions {
    CPRBACService *rbac = [CPRBACService sharedService];
    self.canExecuteCommands = [rbac currentUserCanPerform:CPActionExecute onResource:CPResourceCharger];
    self.canEditParameters  = [rbac currentUserCanPerform:CPActionUpdate  onResource:CPResourceCharger];
}

// ---------------------------------------------------------------------------
#pragma mark - UI Construction
// ---------------------------------------------------------------------------

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.delegate   = self;
    _tableView.dataSource = self;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildCommandProgressBar {
    _commandProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _commandProgressView.progressTintColor = UIColor.systemBlueColor;
    _commandProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    _commandProgressView.hidden = YES;
    _commandProgressView.accessibilityLabel = @"Command in progress";
    [self.view addSubview:_commandProgressView];
    [NSLayoutConstraint activateConstraints:@[
        [_commandProgressView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_commandProgressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_commandProgressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_commandProgressView.heightAnchor constraintEqualToConstant:4],
    ]];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource: Sections
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CPDetailSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case CPDetailSectionHeader:        return nil;
        case CPDetailSectionInfo:          return @"Device Information";
        case CPDetailSectionCommands:      return @"Commands";
        case CPDetailSectionPendingReview: return self.pendingReviewCommands.count > 0 ? @"Pending Review Commands" : nil;
        case CPDetailSectionRecentEvents:  return @"Recent Events";
        case CPDetailSectionParameters:    return self.canEditParameters ? @"Parameters (Admin)" : nil;
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CPDetailSectionHeader:        return 1;
        case CPDetailSectionInfo:          return 3; // vendor ID, firmware, location
        case CPDetailSectionCommands:      return 4; // RemoteStart, RemoteStop, SoftReset, PushParameters
        case CPDetailSectionPendingReview: return (NSInteger)self.pendingReviewCommands.count;
        case CPDetailSectionRecentEvents:  return MAX((NSInteger)self.recentEvents.count, 1);
        case CPDetailSectionParameters:    return self.canEditParameters ? 1 : 0;
        default: return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == CPDetailSectionHeader) return 100;
    if (indexPath.section == CPDetailSectionParameters) return 200;
    return UITableViewAutomaticDimension;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource: Cells
// ---------------------------------------------------------------------------

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case CPDetailSectionHeader:        return [self headerCell];
        case CPDetailSectionInfo:          return [self infoCellAtRow:indexPath.row];
        case CPDetailSectionCommands:      return [self commandCellAtRow:indexPath.row];
        case CPDetailSectionPendingReview: return [self pendingReviewCellAtRow:indexPath.row];
        case CPDetailSectionRecentEvents:  return [self eventCellAtRow:indexPath.row];
        case CPDetailSectionParameters:    return [self parameterCell];
        default: return [UITableViewCell new];
    }
}

// ---- Header cell ----

- (UITableViewCell *)headerCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    CPCharger *charger = self.charger;
    CPChargerStatus status = charger ? [charger chargerStatus] : CPChargerStatusUnknown;

    UILabel *modelLabel = [UILabel new];
    modelLabel.text = charger.model ?: @"Unknown Model";
    modelLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    modelLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *serialLabel = [UILabel new];
    serialLabel.text = [NSString stringWithFormat:@"SN: %@", charger.serialNumber ?: @"—"];
    serialLabel.font = [UIFont systemFontOfSize:14];
    serialLabel.textColor = UIColor.secondaryLabelColor;
    serialLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *badge = [self statusBadgeForStatus:status];
    badge.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lastSeen = [UILabel new];
    lastSeen.font = [UIFont systemFontOfSize:12];
    lastSeen.textColor = UIColor.tertiaryLabelColor;
    lastSeen.translatesAutoresizingMaskIntoConstraints = NO;
    if (charger.lastSeenAt) {
        lastSeen.text = [NSString stringWithFormat:@"Last seen: %@",
                         [[CPDateFormatter sharedFormatter] relativeStringFromDate:charger.lastSeenAt]];
    } else {
        lastSeen.text = @"Last seen: Never";
    }

    UIStackView *leftStack = [[UIStackView alloc] initWithArrangedSubviews:@[modelLabel, serialLabel, lastSeen]];
    leftStack.axis = UILayoutConstraintAxisVertical;
    leftStack.spacing = 4;
    leftStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[leftStack, badge]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionEqualSpacing;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [row.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
    ]];
    return cell;
}

// ---- Info cells ----

- (UITableViewCell *)infoCellAtRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    switch (row) {
        case 0:
            cell.textLabel.text = @"Vendor ID";
            cell.detailTextLabel.text = self.charger.vendorID ?: @"—";
            break;
        case 1:
            cell.textLabel.text = @"Firmware";
            cell.detailTextLabel.text = self.charger.firmwareVersion ?: @"—";
            break;
        case 2:
            cell.textLabel.text = @"Location";
            cell.detailTextLabel.text = self.charger.location ?: @"—";
            break;
    }
    return cell;
}

// ---- Command cells ----

- (UITableViewCell *)commandCellAtRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];

    NSString *title;
    UIColor  *color;
    NSString *commandType;
    NSString *a11yHint;

    switch (row) {
        case 0:
            title       = @"Remote Start";
            color       = UIColor.systemGreenColor;
            commandType = @"RemoteStart";
            a11yHint    = @"Starts the charger remotely";
            break;
        case 1:
            title       = @"Remote Stop";
            color       = UIColor.systemRedColor;
            commandType = @"RemoteStop";
            a11yHint    = @"Stops the charger remotely";
            break;
        case 2:
            title       = @"Soft Reset";
            color       = UIColor.systemOrangeColor;
            commandType = @"SoftReset";
            a11yHint    = @"Performs a soft reset of the charger";
            break;
        case 3:
            title       = @"Push Parameters";
            color       = UIColor.systemBlueColor;
            commandType = @"ParameterPush";
            a11yHint    = @"Pushes configuration parameters to the charger";
            break;
        default:
            return cell;
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = self.canExecuteCommands ? color : UIColor.systemGrayColor;
    button.layer.cornerRadius = 8;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.enabled = self.canExecuteCommands && !self.isExecutingCommand;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = title;
    button.accessibilityHint  = self.canExecuteCommands ? a11yHint : @"You do not have permission to execute this command";

    NSString *cmdTypeTag = commandType;
    [button addAction:[UIAction actionWithTitle:@"" image:nil identifier:nil
                                       handler:^(__kindof UIAction *action) {
        [self handleCommandButtonTapped:cmdTypeTag];
    }] forControlEvents:UIControlEventTouchUpInside];

    [cell.contentView addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [button.heightAnchor constraintEqualToConstant:44],
    ]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// ---- Pending review cells ----

- (UITableViewCell *)pendingReviewCellAtRow:(NSInteger)row {
    if (row >= (NSInteger)self.pendingReviewCommands.count) {
        UITableViewCell *c = [UITableViewCell new];
        c.textLabel.text = @"No pending review commands";
        return c;
    }
    NSManagedObject *cmd = self.pendingReviewCommands[row];
    NSString *type = [cmd valueForKey:@"commandType"] ?: @"Unknown";
    NSDate   *date = [cmd valueForKey:@"createdAt"];
    NSString *uuid = [cmd valueForKey:@"uuid"] ?: @"";

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = [NSString stringWithFormat:@"Pending: %@", type];
    cell.detailTextLabel.text = date ? [[CPDateFormatter sharedFormatter] relativeStringFromDate:date] : @"";
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    [retry setTitle:@"Retry" forState:UIControlStateNormal];
    retry.layer.borderColor = UIColor.systemBlueColor.CGColor;
    retry.layer.borderWidth = 1;
    retry.layer.cornerRadius = 6;
    retry.contentEdgeInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    retry.translatesAutoresizingMaskIntoConstraints = NO;
    retry.accessibilityLabel = [NSString stringWithFormat:@"Retry %@ command", type];

    NSString *capturedUUID = uuid;
    [retry addAction:[UIAction actionWithTitle:@"" image:nil identifier:nil
                                       handler:^(__kindof UIAction *action) {
        [self retryCommandWithUUID:capturedUUID];
    }] forControlEvents:UIControlEventTouchUpInside];

    [cell.contentView addSubview:retry];
    [NSLayoutConstraint activateConstraints:@[
        [retry.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [retry.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
    ]];
    return cell;
}

// ---- Event cells ----

- (UITableViewCell *)eventCellAtRow:(NSInteger)row {
    if (self.recentEvents.count == 0) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.textLabel.text = @"No events recorded";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    NSManagedObject *event = self.recentEvents[row];
    NSString *action  = [event valueForKey:@"action"]  ?: @"—";
    NSString *detail  = [event valueForKey:@"detail"]  ?: @"";
    NSDate   *date    = [event valueForKey:@"createdAt"];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = action;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@",
                                 detail,
                                 date ? [[CPDateFormatter sharedFormatter] relativeStringFromDate:date] : @""];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// ---- Parameter cell (admin only) ----

- (UITableViewCell *)parameterCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (!_parameterTextView) {
        _parameterTextView = [UITextView new];
        _parameterTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        _parameterTextView.layer.borderColor = UIColor.separatorColor.CGColor;
        _parameterTextView.layer.borderWidth = 0.5;
        _parameterTextView.layer.cornerRadius = 6;
        _parameterTextView.accessibilityLabel = @"Charger parameters JSON editor";
    }
    NSDictionary *params = self.charger ? [self.charger parsedParameters] : @{};
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&jsonError];
    _parameterTextView.text = jsonData
        ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]
        : @"{}";

    if (!_saveParametersButton) {
        _saveParametersButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_saveParametersButton setTitle:@"Save Parameters" forState:UIControlStateNormal];
        _saveParametersButton.backgroundColor = UIColor.systemBlueColor;
        [_saveParametersButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _saveParametersButton.layer.cornerRadius = 8;
        _saveParametersButton.accessibilityLabel = @"Save charger parameters";
        [_saveParametersButton addTarget:self action:@selector(saveParametersTapped) forControlEvents:UIControlEventTouchUpInside];
    }

    _parameterTextView.translatesAutoresizingMaskIntoConstraints = NO;
    _saveParametersButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:_parameterTextView];
    [cell.contentView addSubview:_saveParametersButton];

    [NSLayoutConstraint activateConstraints:@[
        [_parameterTextView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [_parameterTextView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [_parameterTextView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [_parameterTextView.heightAnchor constraintEqualToConstant:130],
        [_saveParametersButton.topAnchor constraintEqualToAnchor:_parameterTextView.bottomAnchor constant:8],
        [_saveParametersButton.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [_saveParametersButton.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [_saveParametersButton.heightAnchor constraintEqualToConstant:40],
        [_saveParametersButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
    ]];
    return cell;
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == CPDetailSectionPendingReview && self.pendingReviewCommands.count == 0) return 0.01;
    if (section == CPDetailSectionParameters   && !self.canEditParameters)               return 0.01;
    return UITableViewAutomaticDimension;
}

// ---------------------------------------------------------------------------
#pragma mark - Command Execution
// ---------------------------------------------------------------------------

- (void)handleCommandButtonTapped:(NSString *)commandType {
    if ([commandType isEqualToString:@"RemoteStop"]) {
        [self confirmRemoteStop];
    } else {
        [self executeCommand:commandType parameters:nil];
    }
}

- (void)confirmRemoteStop {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [haptic impactOccurred];

    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:@"Confirm Remote Stop"
                                message:@"Are you sure you want to stop this charger remotely? Any active session will be terminated."
                                preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Stop Charger"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [self executeCommand:@"RemoteStop" parameters:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)executeCommand:(NSString *)commandType parameters:(nullable NSDictionary *)params {
    if (!self.chargerUUID || self.isExecutingCommand) return;

    self.isExecutingCommand = YES;
    [self startCommandTimer];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:CPDetailSectionCommands]
                  withRowAnimation:UITableViewRowAnimationNone];

    __weak typeof(self) weakSelf = self;
    [[CPChargerService sharedService]
     issueCommandToCharger:self.chargerUUID
     commandType:commandType
     parameters:params
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf stopCommandTimer];
            weakSelf.isExecutingCommand = NO;

            if (error) {
                [weakSelf showCommandError:error];
            } else if (!acknowledged) {
                [weakSelf showCommandPendingReviewAlert];
            } else {
                [weakSelf showCommandSuccessToast:commandType];
            }
            [weakSelf reloadData];
        });
    }];
}

- (void)retryCommandWithUUID:(NSString *)commandUUID {
    if (!commandUUID || self.isExecutingCommand) return;
    self.isExecutingCommand = YES;
    [self startCommandTimer];

    __weak typeof(self) weakSelf = self;
    [[CPChargerService sharedService] retryCommand:commandUUID completion:^(BOOL acknowledged, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf stopCommandTimer];
            weakSelf.isExecutingCommand = NO;
            if (error) {
                [weakSelf showCommandError:error];
            } else if (!acknowledged) {
                [weakSelf showCommandPendingReviewAlert];
            } else {
                [weakSelf showCommandSuccessToast:@"Retry"];
            }
            [weakSelf reloadData];
        });
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Command Timer (8-second progress)
// ---------------------------------------------------------------------------

- (void)startCommandTimer {
    self.commandElapsed = 0;
    self.commandProgressView.progress = 0;
    self.commandProgressView.hidden = NO;
    [self.commandTimer invalidate];
    self.commandTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                        target:self
                                                      selector:@selector(timerTick)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopCommandTimer {
    [self.commandTimer invalidate];
    self.commandTimer = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.commandProgressView.hidden = YES;
        self.commandProgressView.progress = 0;
    });
}

- (void)timerTick {
    self.commandElapsed += 0.1;
    float progress = (float)(self.commandElapsed / kCommandTimeoutSeconds);
    [self.commandProgressView setProgress:MIN(progress, 1.0f) animated:YES];
    if (self.commandElapsed >= kCommandTimeoutSeconds) {
        [self stopCommandTimer];
        self.isExecutingCommand = NO;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:CPDetailSectionCommands]
                      withRowAnimation:UITableViewRowAnimationNone];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Notification Handling
// ---------------------------------------------------------------------------

- (void)commandAcknowledged:(NSNotification *)notification {
    NSString *chargerUUID = notification.userInfo[@"chargerUUID"];
    if (![chargerUUID isEqualToString:self.chargerUUID]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadData];
    });
}

// ---------------------------------------------------------------------------
#pragma mark - Parameter Saving
// ---------------------------------------------------------------------------

- (void)saveParametersTapped {
    NSString *text = _parameterTextView.text;
    if (!text.length || !self.charger) return;

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

    if (jsonError || ![parsed isKindOfClass:[NSDictionary class]]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invalid JSON"
                                                                       message:@"Please enter valid JSON for the parameters."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [self.charger setParametersFromDictionary:(NSDictionary *)parsed];
    [[CPCoreDataStack sharedStack] saveMainContext];

    UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Parameters Saved"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

- (UIView *)statusBadgeForStatus:(CPChargerStatus)status {
    NSString *text;
    UIColor  *color;
    switch (status) {
        case CPChargerStatusOnline:   text = @"Online";   color = UIColor.systemGreenColor;  break;
        case CPChargerStatusCharging: text = @"Charging"; color = UIColor.systemBlueColor;   break;
        case CPChargerStatusIdle:     text = @"Idle";     color = UIColor.systemYellowColor; break;
        case CPChargerStatusFault:    text = @"Fault";    color = UIColor.systemRedColor;    break;
        case CPChargerStatusOffline:  text = @"Offline";  color = UIColor.systemGrayColor;   break;
        default:                      text = @"Unknown";  color = UIColor.systemGrayColor;   break;
    }

    UIView  *badge = [UIView new];
    badge.backgroundColor    = color;
    badge.layer.cornerRadius = 10;
    badge.clipsToBounds      = YES;
    badge.isAccessibilityElement = YES;
    badge.accessibilityLabel     = [NSString stringWithFormat:@"Status: %@", text];

    UILabel *label = [UILabel new];
    label.text      = text;
    label.font      = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:badge.topAnchor constant:4],
        [label.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor constant:-4],
        [label.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-10],
    ]];
    return badge;
}

- (void)showCommandError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Command Failed"
                                                                   message:error.localizedDescription
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCommandPendingReviewAlert {
    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:@"Pending Review"
                                message:@"The command did not receive an acknowledgment within 8 seconds and has been queued for review."
                                preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCommandSuccessToast:(NSString *)commandType {
    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:@"Command Acknowledged"
                                message:[NSString stringWithFormat:@"%@ was acknowledged by the charger.", commandType]
                                preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
