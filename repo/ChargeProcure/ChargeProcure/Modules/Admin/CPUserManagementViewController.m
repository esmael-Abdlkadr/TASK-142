#import "CPUserManagementViewController.h"
#import <CoreData/CoreData.h>
#import "CPCoreDataStack.h"
#import "CPUser+CoreDataClass.h"
#import "CPUser+CoreDataProperties.h"

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
@class CPUserService;
@class CPAuthService;

@interface CPUserService : NSObject
+ (instancetype)sharedService;
- (NSManagedObjectContext *)mainContext;
- (void)fetchAllUsers:(void(^)(NSArray<NSManagedObject *> *users, NSError *_Nullable))completion;
- (void)deactivateUserWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion;
- (void)removeUserWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion;
- (void)updateRoleForUserUUID:(NSString *)uuid role:(NSString *)role completion:(void(^)(NSError *_Nullable))completion;
@end

@interface CPAuthService : NSObject
+ (instancetype)sharedService;
- (BOOL)currentUserHasPermission:(NSString *)permission;
- (NSString *)currentUserRole;
- (BOOL)createUserWithUsername:(NSString *)username
                      password:(NSString *)password
                      roleName:(NSString *)roleName
                         error:(NSError **)error;
@end

@implementation CPUserService

+ (instancetype)sharedService {
    static CPUserService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[CPUserService alloc] init];
    });
    return service;
}

- (NSManagedObjectContext *)mainContext {
    return [CPCoreDataStack sharedStack].mainContext;
}

- (void)fetchAllUsers:(void(^)(NSArray<NSManagedObject *> *users, NSError *_Nullable))completion {
    NSManagedObjectContext *context = [self mainContext];
    [context performBlock:^{
        NSFetchRequest *request = [CPUser fetchRequest];
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
        NSError *error = nil;
        NSArray *results = [context executeFetchRequest:request error:&error] ?: @[];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(results, error);
            });
        }
    }];
}

- (void)deactivateUserWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion {
    NSManagedObjectContext *context = [self mainContext];
    [context performBlock:^{
        NSError *error = nil;
        NSFetchRequest *request = [CPUser fetchRequest];
        request.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        request.fetchLimit = 1;
        CPUser *user = [[context executeFetchRequest:request error:&error] firstObject];
        if (user && !error) {
            user.isActive = @NO;
            [[CPCoreDataStack sharedStack] saveContext:context];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        }
    }];
}

- (void)removeUserWithUUID:(NSString *)uuid completion:(void(^)(NSError *_Nullable))completion {
    NSManagedObjectContext *context = [self mainContext];
    [context performBlock:^{
        NSError *error = nil;
        NSFetchRequest *request = [CPUser fetchRequest];
        request.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        request.fetchLimit = 1;
        CPUser *user = [[context executeFetchRequest:request error:&error] firstObject];
        if (user && !error) {
            [context deleteObject:user];
            [[CPCoreDataStack sharedStack] saveContext:context];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        }
    }];
}

- (void)updateRoleForUserUUID:(NSString *)uuid role:(NSString *)role completion:(void(^)(NSError *_Nullable))completion {
    NSManagedObjectContext *context = [self mainContext];
    [context performBlock:^{
        NSError *error = nil;

        NSFetchRequest *userRequest = [CPUser fetchRequest];
        userRequest.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        userRequest.fetchLimit = 1;
        CPUser *user = [[context executeFetchRequest:userRequest error:&error] firstObject];

        if (user && !error) {
            NSFetchRequest *roleRequest = [NSFetchRequest fetchRequestWithEntityName:@"Role"];
            roleRequest.predicate = [NSPredicate predicateWithFormat:@"name == %@", role];
            roleRequest.fetchLimit = 1;
            NSManagedObject *roleObj = [[context executeFetchRequest:roleRequest error:&error] firstObject];

            if (!roleObj && !error) {
                roleObj = [NSEntityDescription insertNewObjectForEntityForName:@"Role" inManagedObjectContext:context];
                [roleObj setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
                [roleObj setValue:role forKey:@"name"];
                [roleObj setValue:[NSDate date] forKey:@"createdAt"];
            }

            if (roleObj) {
                [user setValue:roleObj forKey:@"role"];
                [[CPCoreDataStack sharedStack] saveContext:context];
            }
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        }
    }];
}

@end

// ---------------------------------------------------------------------------
// Add/Edit User VC (lightweight inline VC)
// ---------------------------------------------------------------------------
@interface CPAddUserViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, copy) void (^onSave)(NSDictionary *userData);
@end

@implementation CPAddUserViewController {
    UITextField *_usernameField;
    UITextField *_emailField;
    UITextField *_roleField;
    UITextField *_passwordField;
    UITextField *_confirmPasswordField;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"New User";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)];
    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = save;
    self.navigationItem.leftBarButtonItem = cancel;

    const CGFloat pad = 16;
    UITextField *(^makeField)(NSString *, UIView *, CGFloat) = ^UITextField *(NSString *ph, UIView *container, CGFloat topC) {
        UITextField *tf = [UITextField new];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.placeholder = ph;
        tf.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        tf.layer.cornerRadius = 8;
        tf.layer.masksToBounds = YES;
        tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
        tf.leftViewMode = UITextFieldViewModeAlways;
        tf.font = [UIFont systemFontOfSize:15];
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [container addSubview:tf];
        return tf;
    };

    _usernameField = makeField(@"Username", self.view, 0);
    _emailField = makeField(@"Email", self.view, 0);
    _roleField = makeField(@"Role (Administrator / Site Technician / Finance Approver)", self.view, 0);
    _passwordField = makeField(@"Initial password (min 10 chars, 1 digit)", self.view, 0);
    _passwordField.secureTextEntry = YES;
    _confirmPasswordField = makeField(@"Confirm initial password", self.view, 0);
    _confirmPasswordField.secureTextEntry = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_usernameField.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:pad],
        [_usernameField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [_usernameField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [_usernameField.heightAnchor constraintEqualToConstant:44],

        [_emailField.topAnchor constraintEqualToAnchor:_usernameField.bottomAnchor constant:12],
        [_emailField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [_emailField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [_emailField.heightAnchor constraintEqualToConstant:44],

        [_roleField.topAnchor constraintEqualToAnchor:_emailField.bottomAnchor constant:12],
        [_roleField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [_roleField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [_roleField.heightAnchor constraintEqualToConstant:44],

        [_passwordField.topAnchor constraintEqualToAnchor:_roleField.bottomAnchor constant:12],
        [_passwordField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [_passwordField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [_passwordField.heightAnchor constraintEqualToConstant:44],

        [_confirmPasswordField.topAnchor constraintEqualToAnchor:_passwordField.bottomAnchor constant:12],
        [_confirmPasswordField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [_confirmPasswordField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [_confirmPasswordField.heightAnchor constraintEqualToConstant:44],
    ]];
}

- (void)saveTapped {
    NSString *username = [_usernameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (username.length == 0) {
        [self showError:@"Username is required."];
        return;
    }

    // Validate role is a canonical business role.
    NSString *role = [_roleField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *validRoles = @[@"Administrator", @"Site Technician", @"Finance Approver"];
    if (role.length == 0 || ![validRoles containsObject:role]) {
        [self showError:[NSString stringWithFormat:@"Role must be one of: %@.", [validRoles componentsJoinedByString:@", "]]];
        return;
    }

    NSString *password = _passwordField.text ?: @"";
    NSString *confirm  = _confirmPasswordField.text ?: @"";
    if (password.length == 0) {
        [self showError:@"Initial password is required."];
        return;
    }
    if (![password isEqualToString:confirm]) {
        [self showError:@"Passwords do not match."];
        return;
    }

    if (self.onSave) {
        self.onSave(@{
            @"username": username,
            @"email":    _emailField.text ?: @"",
            @"role":     role,
            @"password": password,
        });
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showError:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Error"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

// ---------------------------------------------------------------------------
// User cell
// ---------------------------------------------------------------------------
@interface CPUserCell : UITableViewCell
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UILabel *lockoutLabel;
@end

@implementation CPUserCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.usernameLabel = [UILabel new];
    self.usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.usernameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.contentView addSubview:self.usernameLabel];

    self.roleLabel = [UILabel new];
    self.roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.roleLabel.font = [UIFont systemFontOfSize:13];
    self.roleLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.roleLabel];

    self.statusBadge = [UILabel new];
    self.statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.statusBadge.layer.cornerRadius = 6;
    self.statusBadge.layer.masksToBounds = YES;
    self.statusBadge.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.statusBadge];

    self.lockoutLabel = [UILabel new];
    self.lockoutLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.lockoutLabel.font = [UIFont systemFontOfSize:11];
    self.lockoutLabel.textColor = [UIColor systemRedColor];
    self.lockoutLabel.hidden = YES;
    [self.contentView addSubview:self.lockoutLabel];

    const CGFloat p = 12;
    [NSLayoutConstraint activateConstraints:@[
        [self.usernameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:p],
        [self.usernameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.usernameLabel.trailingAnchor constraintEqualToAnchor:self.statusBadge.leadingAnchor constant:-8],

        [self.statusBadge.centerYAnchor constraintEqualToAnchor:self.usernameLabel.centerYAnchor],
        [self.statusBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [self.statusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:60],

        [self.roleLabel.topAnchor constraintEqualToAnchor:self.usernameLabel.bottomAnchor constant:4],
        [self.roleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.roleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],

        [self.lockoutLabel.topAnchor constraintEqualToAnchor:self.roleLabel.bottomAnchor constant:4],
        [self.lockoutLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:p],
        [self.lockoutLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-p],
        [self.lockoutLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-p],
    ]];
    return self;
}

- (void)configureWithUser:(NSManagedObject *)user {
    self.usernameLabel.text = [user valueForKey:@"username"] ?: @"(Unknown)";
    NSManagedObject *roleObj = [user valueForKey:@"role"];
    NSString *roleName = roleObj ? [roleObj valueForKey:@"name"] : nil;
    self.roleLabel.text = [NSString stringWithFormat:@"Role: %@", roleName ?: @"—"];

    NSString *status = [user valueForKey:@"status"] ?: @"active";
    if ([status isEqualToString:@"active"]) {
        self.statusBadge.text = @" Active ";
        self.statusBadge.textColor = [UIColor systemGreenColor];
        self.statusBadge.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.12];
    } else if ([status isEqualToString:@"inactive"]) {
        self.statusBadge.text = @" Inactive ";
        self.statusBadge.textColor = [UIColor systemGrayColor];
        self.statusBadge.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.12];
    } else if ([status isEqualToString:@"lockedout"]) {
        self.statusBadge.text = @" Locked ";
        self.statusBadge.textColor = [UIColor systemRedColor];
        self.statusBadge.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.12];
    }

    NSDate *lockoutUntil = [user valueForKey:@"lockoutUntil"];
    if (lockoutUntil && [lockoutUntil compare:[NSDate date]] == NSOrderedDescending) {
        NSTimeInterval remaining = [lockoutUntil timeIntervalSinceNow];
        NSInteger minutes = (NSInteger)(remaining / 60);
        self.lockoutLabel.text = [NSString stringWithFormat:@"Locked out for %ld more minute%@", (long)minutes, minutes == 1 ? @"" : @"s"];
        self.lockoutLabel.hidden = NO;
    } else {
        self.lockoutLabel.hidden = YES;
    }
}

@end

// ---------------------------------------------------------------------------
// Main View Controller
// ---------------------------------------------------------------------------
@interface CPUserManagementViewController () <UITableViewDelegate, UITableViewDataSource, NSFetchedResultsControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSManagedObject *> *users;
@end

@implementation CPUserManagementViewController

static NSString * const kCellID = @"CPUserCell";

- (void)viewDidLoad {
    [super viewDidLoad];

    // RBAC guard
    if (![[CPAuthService sharedService] currentUserHasPermission:@"admin"]) {
        [self showAccessDenied];
        return;
    }

    self.title = @"User Management";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self setupTableView];
    [self setupNavigationBar];
    [self loadUsers];
}

- (void)showAccessDenied {
    self.title = @"Access Denied";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = @"Administrator access required.";
    lbl.textColor = [UIColor secondaryLabelColor];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.numberOfLines = 0;
    [self.view addSubview:lbl];
    [NSLayoutConstraint activateConstraints:@[
        [lbl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [lbl.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [lbl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [lbl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76;
    [self.tableView registerClass:[CPUserCell class] forCellReuseIdentifier:kCellID];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupNavigationBar {
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"person.badge.plus"]
                style:UIBarButtonItemStylePlain
               target:self action:@selector(addUser)];
    self.navigationItem.rightBarButtonItem = addBtn;
}

- (void)loadUsers {
    [[CPUserService sharedService] fetchAllUsers:^(NSArray *users, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err) {
                self.users = users;
                [self.tableView reloadData];
            } else {
                NSLog(@"[CPUserManagement] Error loading users: %@", err);
            }
        });
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)addUser {
    CPAddUserViewController *addVC = [CPAddUserViewController new];
    addVC.onSave = ^(NSDictionary *userData) {
        NSString *username = userData[@"username"] ?: @"";
        NSString *password = userData[@"password"] ?: @"";
        NSString *roleName = userData[@"role"]     ?: @"Administrator";

        NSError *createError = nil;
        BOOL ok = [[CPAuthService sharedService] createUserWithUsername:username
                                                               password:password
                                                               roleName:roleName
                                                                  error:&createError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                UIAlertController *err = [UIAlertController
                    alertControllerWithTitle:@"Create Failed"
                    message:createError.localizedDescription ?: @"Could not create user."
                    preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:err animated:YES completion:nil];
            } else {
                [self loadUsers];
            }
        });
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:addVC];
    [self presentViewController:nav animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.users.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CPUserCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    NSManagedObject *user = self.users[indexPath.row];
    [cell configureWithUser:user];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%ld User%@", (long)self.users.count, self.users.count == 1 ? @"" : @"s"];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableViewDelegate
// ---------------------------------------------------------------------------

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSManagedObject *user = self.users[indexPath.row];
    [self showUserActionSheetForUser:user];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *user = self.users[indexPath.row];
    NSString *status = [user valueForKey:@"status"] ?: @"active";

    UIContextualAction *deactivateAction;
    if ([status isEqualToString:@"active"]) {
        deactivateAction = [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleDestructive
            title:@"Deactivate"
            handler:^(UIContextualAction *a, UIView *sv, void(^complete)(BOOL)) {
                [self confirmDeactivateUser:user completion:complete];
            }];
    } else {
        deactivateAction = [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
            title:@"Reactivate"
            handler:^(UIContextualAction *a, UIView *sv, void(^complete)(BOOL)) {
                // reactivation would call service
                complete(YES);
                [self loadUsers];
            }];
        deactivateAction.backgroundColor = [UIColor systemGreenColor];
    }

    UIContextualAction *removeAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Remove"
        handler:^(UIContextualAction *a, UIView *sv, void(^complete)(BOOL)) {
            [self confirmRemoveUser:user completion:complete];
        }];

    return [UISwipeActionsConfiguration configurationWithActions:@[removeAction, deactivateAction]];
}

// ---------------------------------------------------------------------------
#pragma mark - User Actions
// ---------------------------------------------------------------------------

- (void)showUserActionSheetForUser:(NSManagedObject *)user {
    NSString *username = [user valueForKey:@"username"] ?: @"User";
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:username
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    // Role assignment — canonical business roles only.
    for (NSString *role in @[@"Administrator", @"Site Technician", @"Finance Approver"]) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Set Role: %@", role]
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                [[CPUserService sharedService] updateRoleForUserUUID:[user valueForKey:@"uuid"]
                    role:role completion:^(NSError *err) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self loadUsers];
                    });
                }];
            }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Deactivate" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self confirmDeactivateUser:user completion:^(BOOL _) {}];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Remove User" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self confirmRemoveUser:user completion:^(BOOL _) {}];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmDeactivateUser:(NSManagedObject *)user completion:(void(^)(BOOL))completion {
    NSString *username = [user valueForKey:@"username"] ?: @"this user";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Deactivate User"
        message:[NSString stringWithFormat:@"Deactivate %@?", username]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Deactivate" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[CPUserService sharedService] deactivateUserWithUUID:[user valueForKey:@"uuid"]
            completion:^(NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(!err);
                [self loadUsers];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmRemoveUser:(NSManagedObject *)user completion:(void(^)(BOOL))completion {
    NSString *username = [user valueForKey:@"username"] ?: @"this user";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Remove User"
        message:[NSString stringWithFormat:@"Permanently remove %@? This cannot be undone.", username]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[CPUserService sharedService] removeUserWithUUID:[user valueForKey:@"uuid"]
            completion:^(NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(!err);
                [self loadUsers];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
