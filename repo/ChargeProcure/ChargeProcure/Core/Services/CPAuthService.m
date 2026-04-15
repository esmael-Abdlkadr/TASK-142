#import "CPAuthService.h"
#import "CPAuditService.h"
#import "CPRBACService.h"
#import "../CoreData/CPCoreDataStack.h"
#import <CommonCrypto/CommonCrypto.h>
#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

NSString * const CPAuthErrorDomain               = @"com.chargeprocure.auth";
NSString * const CPAuthSessionChangedNotification = @"CPAuthSessionChangedNotification";

static NSString * const kCurrentUserIDKey           = @"cp_current_user_id";
static NSString * const kCurrentUsernameKey         = @"cp_current_username";
static NSString * const kCurrentUserRoleKey         = @"cp_current_user_role";
static NSString * const kBiometricUsernameKey       = @"cp_biometric_username";
/// NSUserDefaults key: NSArray of user UUID strings that must rotate the default password.
static NSString * const kMustChangePasswordUUIDsKey = @"cp_must_change_password_uuids";

static const NSInteger kMaxFailedAttempts       = 5;
static const NSTimeInterval kLockoutDuration    = 15.0 * 60.0; // 15 minutes
static const NSUInteger kMinPasswordLength      = 10;
static const NSUInteger kSaltByteCount          = 16;
// Hardcoded bootstrap credentials for first-run seeded accounts.
static NSString * const kDefaultAdminPassword   = @"Admin1234Pass";
static NSString * const kDefaultTechPassword    = @"Tech1234Pass";
static NSString * const kDefaultFinancePassword = @"Fin1234Pass";

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface CPAuthService ()

@property (nonatomic, readwrite) BOOL           isSessionValid;
@property (nonatomic, readwrite) BOOL           needsPasswordChange;
@property (nonatomic, readwrite, nullable) NSString *currentUserID;
@property (nonatomic, readwrite, nullable) NSString *currentUsername;
@property (nonatomic, readwrite, nullable) NSString *currentUserRole;
// Serial queue: ensures concurrent loginWithUsername: calls are processed one at a
// time so the failedAttempts read-modify-write is never lost to a race condition.
@property (nonatomic, strong) dispatch_queue_t  loginQueue;
// Ephemeral bootstrap credentials awaiting one-time display by AppDelegate.
@property (nonatomic, readwrite, nullable, copy) NSDictionary<NSString *, NSString *> *pendingBootstrapCredentials;

@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation CPAuthService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPAuthService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPAuthService alloc] init];
    });
    return _shared;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _loginQueue = dispatch_queue_create("com.chargeprocure.auth.login",
                                            DISPATCH_QUEUE_SERIAL);
        [self restoreSessionFromDefaults];
    }
    return self;
}

- (void)restoreSessionFromDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *userID   = [defaults stringForKey:kCurrentUserIDKey];
    NSString *username = [defaults stringForKey:kCurrentUsernameKey];
    NSString *role     = [defaults stringForKey:kCurrentUserRoleKey];

    if (userID.length > 0 && username.length > 0) {
        _currentUserID   = userID;
        _currentUsername = username;
        _currentUserRole = role;
        _isSessionValid  = YES;
    }
}

#pragma mark - Login

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSParameterAssert(username);
    NSParameterAssert(password);
    NSParameterAssert(completion);

    // All login work runs on the serial _loginQueue so that concurrent callers
    // process failedAttempts one at a time (no read-modify-write race condition).
    dispatch_async(self.loginQueue, ^{
        NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [context performBlockAndWait:^{

        // --- Fetch user by username ---
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"username ==[c] %@", username];
        fetchRequest.fetchLimit = 1;
        fetchRequest.relationshipKeyPathsForPrefetching = @[@"role"];

        NSError *fetchError = nil;
        NSArray *results    = [context executeFetchRequest:fetchRequest error:&fetchError];

        if (fetchError || results.count == 0) {
            NSError *authError = [self errorWithCode:CPAuthErrorUserNotFound
                                         description:@"No account found with that username."];
            [[CPAuditService sharedService] logAction:@"login_failed"
                                             resource:@"User"
                                           resourceID:nil
                                               detail:[NSString stringWithFormat:@"Username not found: %@", username]];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
            return;
        }

        NSManagedObject *user = results.firstObject;

        // --- Active check ---
        NSNumber *isActive = [user valueForKey:@"isActive"];
        if (!isActive.boolValue) {
            NSError *authError = [self errorWithCode:CPAuthErrorUserInactive
                                         description:@"This account has been deactivated."];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
            return;
        }

        // --- Lockout check ---
        NSDate *lockoutUntil = [user valueForKey:@"lockoutUntil"];
        if (lockoutUntil && [lockoutUntil timeIntervalSinceNow] > 0) {
            NSError *authError = [self errorWithCode:CPAuthErrorLockedOut
                                         description:@"Account is temporarily locked due to too many failed attempts."];
            [[CPAuditService sharedService] logAction:@"login_blocked_lockout"
                                             resource:@"User"
                                           resourceID:[user valueForKey:@"uuid"]
                                               detail:[NSString stringWithFormat:@"Locked until: %@", lockoutUntil]];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
            return;
        }

        // --- Hash verification ---
        NSString *storedHash = [user valueForKey:@"passwordHash"];
        NSString *storedSalt = [user valueForKey:@"salt"];
        NSString *computedHash = [self hashPassword:password withSalt:storedSalt];

        if (![computedHash isEqualToString:storedHash]) {
            // Increment failed attempts
            NSNumber *failedAttempts = [user valueForKey:@"failedAttempts"];
            NSInteger newCount = failedAttempts.integerValue + 1;
            [user setValue:@(newCount) forKey:@"failedAttempts"];

            if (newCount >= kMaxFailedAttempts) {
                NSDate *lockout = [NSDate dateWithTimeIntervalSinceNow:kLockoutDuration];
                [user setValue:lockout forKey:@"lockoutUntil"];
                NSError *saveErr = nil;
                [context save:&saveErr];

                [[CPAuditService sharedService] logAction:@"account_locked"
                                                 resource:@"User"
                                               resourceID:[user valueForKey:@"uuid"]
                                                   detail:@"Account locked after 5 failed login attempts"];

                NSError *authError = [self errorWithCode:CPAuthErrorLockedOut
                                             description:@"Account locked for 15 minutes after 5 failed attempts."];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
            } else {
                NSError *saveErr = nil;
                [context save:&saveErr];

                [[CPAuditService sharedService] logAction:@"login_failed"
                                                 resource:@"User"
                                               resourceID:[user valueForKey:@"uuid"]
                                                   detail:[NSString stringWithFormat:@"Invalid password attempt %ld of %ld",
                                                           (long)newCount, (long)kMaxFailedAttempts]];

                NSError *authError = [self errorWithCode:CPAuthErrorInvalidCredentials
                                             description:@"Invalid username or password."];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
            }
            return;
        }

        // --- Successful login ---
        [user setValue:@(0) forKey:@"failedAttempts"];
        [user setValue:nil  forKey:@"lockoutUntil"];
        [user setValue:[NSDate date] forKey:@"lastLoginAt"];

        NSString *userID   = [user valueForKey:@"uuid"];
        NSString *uname    = [user valueForKey:@"username"];
        NSManagedObject *role = [user valueForKey:@"role"];
        NSString *roleName = role ? [role valueForKey:@"name"] : nil;

        NSError *saveErr = nil;
        [context save:&saveErr];

        [[CPAuditService sharedService] logAction:@"login_success"
                                         resource:@"User"
                                       resourceID:userID
                                           detail:[NSString stringWithFormat:@"Login successful for: %@", uname]];

        // Check whether this account was seeded with a default password.
        NSArray *mustChangelist = [[NSUserDefaults standardUserDefaults]
                                       arrayForKey:kMustChangePasswordUUIDsKey] ?: @[];
        BOOL mustChange = [mustChangelist containsObject:userID];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self establishSessionWithUserID:userID username:uname role:roleName];
            self.needsPasswordChange = mustChange;
            completion(YES, nil);
        });
        }]; // end performBlockAndWait
    }); // end dispatch_async loginQueue
}

#pragma mark - Session Management

- (void)establishSessionWithUserID:(NSString *)userID
                          username:(NSString *)username
                              role:(nullable NSString *)role {
    self.currentUserID   = userID;
    self.currentUsername = username;
    self.currentUserRole = role;
    self.isSessionValid  = YES;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:userID   forKey:kCurrentUserIDKey];
    [defaults setObject:username forKey:kCurrentUsernameKey];
    if (role) {
        [defaults setObject:role forKey:kCurrentUserRoleKey];
    } else {
        [defaults removeObjectForKey:kCurrentUserRoleKey];
    }
    [defaults synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:CPAuthSessionChangedNotification object:self];
}

- (void)logout {
    self.currentUserID   = nil;
    self.currentUsername = nil;
    self.currentUserRole = nil;
    self.isSessionValid  = NO;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kCurrentUserIDKey];
    [defaults removeObjectForKey:kCurrentUsernameKey];
    [defaults removeObjectForKey:kCurrentUserRoleKey];
    [defaults synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:CPAuthSessionChangedNotification object:self];
}

#pragma mark - Biometric Authentication

- (void)authenticateWithBiometrics:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSParameterAssert(completion);

    NSString *storedUsername = [[NSUserDefaults standardUserDefaults] stringForKey:kBiometricUsernameKey];
    if (!storedUsername.length) {
        // Fall back to current username if set
        storedUsername = self.currentUsername;
    }
    if (!storedUsername.length) {
        NSError *error = [self errorWithCode:CPAuthErrorBiometricUnavailable
                                 description:@"No username stored for biometric authentication."];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
        return;
    }

    LAContext *context = [[LAContext alloc] init];
    NSError *canEvalError = nil;
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&canEvalError]) {
        NSError *error = [self errorWithCode:CPAuthErrorBiometricUnavailable
                                 description:canEvalError.localizedDescription ?: @"Biometrics not available on this device."];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
        return;
    }

    NSString *biometryName = @"Biometrics";
    if (@available(iOS 11.0, *)) {
        if (context.biometryType == LABiometryTypeFaceID) {
            biometryName = @"Face ID";
        } else if (context.biometryType == LABiometryTypeTouchID) {
            biometryName = @"Touch ID";
        }
    }

    NSString *localizedReason = [NSString stringWithFormat:@"Authenticate with %@ to sign in to ChargeProcure.", biometryName];

    __weak typeof(self) weakSelf = self;
    NSString *capturedUsername = storedUsername;

    [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:localizedReason
                      reply:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            NSError *authError = [weakSelf errorWithCode:CPAuthErrorBiometricFailed
                                             description:error.localizedDescription ?: @"Biometric authentication failed."];
            [[CPAuditService sharedService] logAction:@"biometric_auth_failed"
                                             resource:@"User"
                                           resourceID:weakSelf.currentUserID
                                               detail:[NSString stringWithFormat:@"Biometric failure for: %@", capturedUsername]];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
            return;
        }

        // Check that biometric is enabled for this user in Core Data
        [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *bgContext) {
            NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
            req.predicate = [NSPredicate predicateWithFormat:@"username ==[c] %@", capturedUsername];
            req.fetchLimit = 1;
            req.relationshipKeyPathsForPrefetching = @[@"role"];

            NSError *fetchErr = nil;
            NSArray *results  = [bgContext executeFetchRequest:req error:&fetchErr];
            NSManagedObject *user = results.firstObject;

            if (!user) {
                NSError *authError = [weakSelf errorWithCode:CPAuthErrorUserNotFound
                                                 description:@"User account not found."];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
                return;
            }

            NSNumber *biometricEnabled = [user valueForKey:@"biometricEnabled"];
            if (!biometricEnabled.boolValue) {
                NSError *authError = [weakSelf errorWithCode:CPAuthErrorBiometricUnavailable
                                                 description:@"Biometric authentication is not enabled for this account."];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
                return;
            }

            NSNumber *isActive = [user valueForKey:@"isActive"];
            if (!isActive.boolValue) {
                NSError *authError = [weakSelf errorWithCode:CPAuthErrorUserInactive
                                                 description:@"This account has been deactivated."];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
                return;
            }

            // Check lockout
            NSDate *lockoutUntil = [user valueForKey:@"lockoutUntil"];
            if (lockoutUntil && [lockoutUntil timeIntervalSinceNow] > 0) {
                NSError *authError = [weakSelf errorWithCode:CPAuthErrorLockedOut
                                                 description:@"Account is temporarily locked."];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, authError); });
                return;
            }

            NSString *userID   = [user valueForKey:@"uuid"];
            NSString *uname    = [user valueForKey:@"username"];
            NSManagedObject *role = [user valueForKey:@"role"];
            NSString *roleName = role ? [role valueForKey:@"name"] : nil;

            [user setValue:[NSDate date] forKey:@"lastLoginAt"];
            NSError *saveErr = nil;
            [bgContext save:&saveErr];

            [[CPAuditService sharedService] logAction:@"biometric_auth_success"
                                             resource:@"User"
                                           resourceID:userID
                                               detail:[NSString stringWithFormat:@"Biometric login: %@", uname]];

            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf establishSessionWithUserID:userID username:uname role:roleName];
                completion(YES, nil);
            });
        }];
    }];
}

- (void)setBiometricEnabled:(BOOL)enabled {
    NSString *userID = self.currentUserID;
    if (!userID) return;

    [[NSUserDefaults standardUserDefaults] setObject:self.currentUsername forKey:kBiometricUsernameKey];

    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *context) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", userID];
        req.fetchLimit = 1;

        NSError *err = nil;
        NSArray *results = [context executeFetchRequest:req error:&err];
        NSManagedObject *user = results.firstObject;
        if (user) {
            [user setValue:@(enabled) forKey:@"biometricEnabled"];
            [context save:&err];
        }
    }];
}

#pragma mark - User Management

- (BOOL)createUserWithUsername:(NSString *)username
                      password:(NSString *)password
                      roleName:(NSString *)roleName
                         error:(NSError **)error {
    NSParameterAssert(username);
    NSParameterAssert(password);
    NSParameterAssert(roleName);

    // Validate password
    NSError *validationError = nil;
    if (![self validatePassword:password error:&validationError]) {
        if (error) *error = validationError;
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *operationError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [context performBlock:^{
        // Check username uniqueness
        NSFetchRequest *uniqueCheck = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        uniqueCheck.predicate = [NSPredicate predicateWithFormat:@"username ==[c] %@", username];
        uniqueCheck.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSArray *existing = [context executeFetchRequest:uniqueCheck error:&fetchErr];
        if (existing.count > 0) {
            operationError = [self errorWithCode:CPAuthErrorInvalidCredentials
                                     description:[NSString stringWithFormat:@"Username '%@' is already taken.", username]];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        // Fetch or create role
        NSManagedObject *role = [self fetchOrCreateRoleNamed:roleName inContext:context];

        // Generate salt and hash
        NSString *salt = [self generateSalt];
        NSString *hash = [self hashPassword:password withSalt:salt];

        // Create user entity
        NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [user setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
        [user setValue:username forKey:@"username"];
        [user setValue:hash forKey:@"passwordHash"];
        [user setValue:salt forKey:@"salt"];
        [user setValue:@(0) forKey:@"failedAttempts"];
        [user setValue:@(YES) forKey:@"isActive"];
        [user setValue:@(NO) forKey:@"biometricEnabled"];
        [user setValue:[NSDate date] forKey:@"createdAt"];
        [user setValue:role forKey:@"role"];

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"user_created"
                                             resource:@"User"
                                           resourceID:[user valueForKey:@"uuid"]
                                               detail:[NSString stringWithFormat:@"Created user '%@' with role '%@'", username, roleName]];
        } else {
            operationError = saveErr;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (error && operationError) *error = operationError;
    return success;
}

- (BOOL)changePasswordForUserID:(NSString *)userID
                    oldPassword:(NSString *)oldPassword
                    newPassword:(NSString *)newPassword
                          error:(NSError **)error {
    NSParameterAssert(userID);
    NSParameterAssert(oldPassword);
    NSParameterAssert(newPassword);

    NSError *validationError = nil;
    if (![self validatePassword:newPassword error:&validationError]) {
        if (error) *error = validationError;
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *operationError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [context performBlock:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", userID];
        req.fetchLimit = 1;

        NSError *fetchErr = nil;
        NSArray *results = [context executeFetchRequest:req error:&fetchErr];
        NSManagedObject *user = results.firstObject;

        if (!user) {
            operationError = [self errorWithCode:CPAuthErrorUserNotFound description:@"User not found."];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSString *storedHash = [user valueForKey:@"passwordHash"];
        NSString *storedSalt = [user valueForKey:@"salt"];
        NSString *oldHash    = [self hashPassword:oldPassword withSalt:storedSalt];

        if (![oldHash isEqualToString:storedHash]) {
            operationError = [self errorWithCode:CPAuthErrorInvalidCredentials
                                     description:@"Old password is incorrect."];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSString *newSalt = [self generateSalt];
        NSString *newHash = [self hashPassword:newPassword withSalt:newSalt];
        [user setValue:newHash forKey:@"passwordHash"];
        [user setValue:newSalt forKey:@"salt"];

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"password_changed"
                                             resource:@"User"
                                           resourceID:userID
                                               detail:@"Password changed successfully"];
        } else {
            operationError = saveErr;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    // If the change succeeded and this was a seeded account, clear the rotation flag.
    if (success) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray *currentList = [defaults arrayForKey:kMustChangePasswordUUIDsKey] ?: @[];
        NSMutableArray *updated = [currentList mutableCopy];
        [updated removeObject:userID];
        [defaults setObject:[updated copy] forKey:kMustChangePasswordUUIDsKey];
        [defaults synchronize];

        if ([userID isEqualToString:self.currentUserID]) {
            self.needsPasswordChange = NO;
        }
    }

    if (error && operationError) *error = operationError;
    return success;
}

- (BOOL)forceChangePasswordForUserID:(NSString *)userID
                         newPassword:(NSString *)newPassword
                               error:(NSError **)error {
    NSParameterAssert(userID);
    NSParameterAssert(newPassword);

    NSError *validationError = nil;
    if (![self validatePassword:newPassword error:&validationError]) {
        if (error) *error = validationError;
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *operationError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [context performBlock:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", userID];
        req.fetchLimit = 1;

        NSError *fetchErr = nil;
        NSArray *results = [context executeFetchRequest:req error:&fetchErr];
        NSManagedObject *user = results.firstObject;

        if (!user) {
            operationError = [self errorWithCode:CPAuthErrorUserNotFound
                                     description:@"User not found."];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSString *newSalt = [self generateSalt];
        NSString *newHash = [self hashPassword:newPassword withSalt:newSalt];
        [user setValue:newHash forKey:@"passwordHash"];
        [user setValue:newSalt forKey:@"salt"];

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"password_force_changed"
                                             resource:@"User"
                                           resourceID:userID
                                               detail:@"Password set during mandatory first-login rotation"];
        } else {
            operationError = saveErr;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    // Clear the rotation flag on success.
    if (success) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray *currentList = [defaults arrayForKey:kMustChangePasswordUUIDsKey] ?: @[];
        NSMutableArray *updated = [currentList mutableCopy];
        [updated removeObject:userID];
        [defaults setObject:[updated copy] forKey:kMustChangePasswordUUIDsKey];
        [defaults synchronize];

        if ([userID isEqualToString:self.currentUserID]) {
            self.needsPasswordChange = NO;
        }
    }

    if (error && operationError) *error = operationError;
    return success;
}

#pragma mark - Password Validation

- (BOOL)validatePassword:(NSString *)password error:(NSError **)error {
    if (!password || password.length < kMinPasswordLength) {
        if (error) {
            *error = [self errorWithCode:CPAuthErrorPasswordTooShort
                             description:[NSString stringWithFormat:@"Password must be at least %lu characters.", (unsigned long)kMinPasswordLength]];
        }
        return NO;
    }

    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSRange range = [password rangeOfCharacterFromSet:digits];
    if (range.location == NSNotFound) {
        if (error) {
            *error = [self errorWithCode:CPAuthErrorPasswordNoNumber
                             description:@"Password must contain at least one digit."];
        }
        return NO;
    }
    return YES;
}

#pragma mark - Seeding Default Users

- (BOOL)seedDefaultUsersIfNeeded {
    __block BOOL seeded = NO;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [context performBlock:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.fetchLimit = 1;
        NSError *err = nil;
        NSArray *existing = [context executeFetchRequest:req error:&err];
        if (existing.count > 0) {
            dispatch_semaphore_signal(semaphore);
            return;
        }

        // Create roles with permissions
        NSManagedObject *adminRole = [self createRoleNamed:@"Administrator"
                                               permissions:[self administratorPermissions]
                                                 inContext:context];
        NSManagedObject *techRole  = [self createRoleNamed:@"Site Technician"
                                               permissions:[self siteTechnicianPermissions]
                                                 inContext:context];
        NSManagedObject *finRole   = [self createRoleNamed:@"Finance Approver"
                                               permissions:[self financeApproverPermissions]
                                                 inContext:context];

        // Use fixed first-run bootstrap passwords for seeded accounts.
        // These values are intentionally deterministic and surfaced in-app once
        // via AppDelegate so operators can copy them before first login.
        NSString *adminPass = kDefaultAdminPassword;
        NSString *techPass  = kDefaultTechPassword;
        NSString *finPass   = kDefaultFinancePassword;

        NSString *adminUUID = [self createDefaultUserWithUsername:@"admin"
                                                         password:adminPass
                                                             role:adminRole
                                                        inContext:context];
        NSString *techUUID  = [self createDefaultUserWithUsername:@"technician"
                                                         password:techPass
                                                             role:techRole
                                                        inContext:context];
        NSString *finUUID   = [self createDefaultUserWithUsername:@"finance"
                                                         password:finPass
                                                             role:finRole
                                                        inContext:context];

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            seeded = YES;
            // Mark all three seeded accounts as requiring a password change on first login.
            NSArray *uuids = @[adminUUID, techUUID, finUUID];
            [[NSUserDefaults standardUserDefaults] setObject:uuids
                                                      forKey:kMustChangePasswordUUIDsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            // Store credentials for one-time display via AppDelegate after window is ready.
            // No credentials are written to any log or persistent store.
            self.pendingBootstrapCredentials = @{
                @"admin":      adminPass,
                @"technician": techPass,
                @"finance":    finPass,
            };
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return seeded;
}

- (void)clearPendingBootstrapCredentials {
    self.pendingBootstrapCredentials = nil;
}

- (BOOL)seedDefaultUsersWithPassword:(NSString *)password {
    NSParameterAssert(password.length > 0);
    __block BOOL seeded = NO;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [context performBlock:^{
        // Create roles with permissions (always, for clean test state)
        NSManagedObject *adminRole = [self createRoleNamed:@"Administrator"
                                               permissions:[self administratorPermissions]
                                                 inContext:context];
        NSManagedObject *techRole  = [self createRoleNamed:@"Site Technician"
                                               permissions:[self siteTechnicianPermissions]
                                                 inContext:context];
        NSManagedObject *finRole   = [self createRoleNamed:@"Finance Approver"
                                               permissions:[self financeApproverPermissions]
                                                 inContext:context];

        NSString *adminUUID = [self createDefaultUserWithUsername:@"admin"
                                                         password:password
                                                             role:adminRole
                                                        inContext:context];
        NSString *techUUID  = [self createDefaultUserWithUsername:@"technician"
                                                         password:password
                                                             role:techRole
                                                        inContext:context];
        NSString *finUUID   = [self createDefaultUserWithUsername:@"finance"
                                                         password:password
                                                             role:finRole
                                                        inContext:context];

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            seeded = YES;
            NSArray *uuids = @[adminUUID, techUUID, finUUID];
            [[NSUserDefaults standardUserDefaults] setObject:uuids
                                                      forKey:kMustChangePasswordUUIDsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return seeded;
}

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

- (NSManagedObject *)createRoleNamed:(NSString *)name
                         permissions:(NSArray<NSDictionary *> *)permissions
                           inContext:(NSManagedObjectContext *)context {
    NSManagedObject *role = [NSEntityDescription insertNewObjectForEntityForName:@"Role" inManagedObjectContext:context];
    [role setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [role setValue:name forKey:@"name"];
    [role setValue:[NSDate date] forKey:@"createdAt"];

    NSMutableSet *permSet = [NSMutableSet set];
    for (NSDictionary *perm in permissions) {
        NSManagedObject *permObj = [NSEntityDescription insertNewObjectForEntityForName:@"Permission" inManagedObjectContext:context];
        [permObj setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
        [permObj setValue:perm[@"resource"] forKey:@"resource"];
        [permObj setValue:perm[@"action"]   forKey:@"action"];
        [permObj setValue:@(YES)            forKey:@"isGranted"];
        [permObj setValue:role              forKey:@"role"];
        [permSet addObject:permObj];
    }
    [role setValue:permSet forKey:@"permissions"];
    return role;
}

/// Creates a seeded default user and returns the new UUID string.
- (NSString *)createDefaultUserWithUsername:(NSString *)username
                                   password:(NSString *)password
                                       role:(NSManagedObject *)role
                                  inContext:(NSManagedObjectContext *)context {
    NSString *newUUID = [[NSUUID UUID] UUIDString];
    NSString *salt = [self generateSalt];
    NSString *hash = [self hashPassword:password withSalt:salt];

    NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
    [user setValue:newUUID  forKey:@"uuid"];
    [user setValue:username forKey:@"username"];
    [user setValue:hash forKey:@"passwordHash"];
    [user setValue:salt forKey:@"salt"];
    [user setValue:@(0)    forKey:@"failedAttempts"];
    [user setValue:@(YES)  forKey:@"isActive"];
    [user setValue:@(NO)   forKey:@"biometricEnabled"];
    [user setValue:[NSDate date] forKey:@"createdAt"];
    [user setValue:role forKey:@"role"];
    return newUUID;
}

// ---------------------------------------------------------------------------
// Permission definitions for each role
// ---------------------------------------------------------------------------

- (NSArray<NSDictionary *> *)administratorPermissions {
    NSArray *resources = @[
        @"Charger", @"Procurement", @"Bulletin",
        @"Pricing", @"User", @"Audit",
        @"Invoice", @"WriteOff", @"Report"
    ];
    NSArray *actions = @[@"read", @"create", @"update", @"delete", @"approve", @"execute", @"export"];
    NSMutableArray *perms = [NSMutableArray array];
    for (NSString *resource in resources) {
        for (NSString *action in actions) {
            [perms addObject:@{@"resource": resource, @"action": action}];
        }
    }
    return [perms copy];
}

- (NSArray<NSDictionary *> *)siteTechnicianPermissions {
    return @[
        @{@"resource": @"Charger",      @"action": @"read"},
        @{@"resource": @"Charger",      @"action": @"update"},
        @{@"resource": @"Procurement",  @"action": @"read"},
        @{@"resource": @"Procurement",  @"action": @"create"},
        @{@"resource": @"Bulletin",     @"action": @"create"},
        @{@"resource": @"Bulletin",     @"action": @"update"},
    ];
}

- (NSArray<NSDictionary *> *)financeApproverPermissions {
    return @[
        @{@"resource": @"Procurement", @"action": @"read"},
        @{@"resource": @"Procurement", @"action": @"update"},
        @{@"resource": @"Invoice",     @"action": @"read"},
        @{@"resource": @"Invoice",     @"action": @"approve"},
        @{@"resource": @"WriteOff",    @"action": @"read"},
        @{@"resource": @"WriteOff",    @"action": @"approve"},
    ];
}

#pragma mark - Core Data Helpers

- (NSManagedObject *)fetchOrCreateRoleNamed:(NSString *)roleName
                                  inContext:(NSManagedObjectContext *)context {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Role"];
    req.predicate = [NSPredicate predicateWithFormat:@"name == %@", roleName];
    req.fetchLimit = 1;

    NSError *err = nil;
    NSArray *results = [context executeFetchRequest:req error:&err];
    if (results.firstObject) {
        return results.firstObject;
    }

    NSManagedObject *role = [NSEntityDescription insertNewObjectForEntityForName:@"Role" inManagedObjectContext:context];
    [role setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [role setValue:roleName forKey:@"name"];
    [role setValue:[NSDate date] forKey:@"createdAt"];
    return role;
}

#pragma mark - Cryptography

- (NSString *)generateSalt {
    uint8_t bytes[kSaltByteCount];
    int result = SecRandomCopyBytes(kSecRandomDefault, kSaltByteCount, bytes);
    if (result != errSecSuccess) {
        // Fallback to arc4random if SecRandom fails
        for (NSUInteger i = 0; i < kSaltByteCount; i++) {
            bytes[i] = (uint8_t)(arc4random_uniform(256));
        }
    }
    NSMutableString *hex = [NSMutableString stringWithCapacity:kSaltByteCount * 2];
    for (NSUInteger i = 0; i < kSaltByteCount; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [hex copy];
}

- (NSString *)hashPassword:(NSString *)password withSalt:(NSString *)salt {
    NSString *combined = [salt stringByAppendingString:password];
    NSData *data = [combined dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex copy];
}

#pragma mark - Permission Check

- (BOOL)currentUserHasPermission:(NSString *)permission {
    if (!self.isSessionValid) return NO;

    // "admin" shorthand: requires User.create permission, which only the
    // Administrator role holds in the RBAC data.
    if ([permission isEqualToString:@"admin"]) {
        return [[CPRBACService sharedService] currentUserCanPerform:CPActionCreate
                                                         onResource:CPResourceUser];
    }

    // Parse "resource.action" format (e.g. "bulletin.create").
    NSArray<NSString *> *parts = [permission componentsSeparatedByString:@"."];
    if (parts.count < 2) return NO;
    NSString *resource = [parts[0] capitalizedString]; // "bulletin" → "Bulletin"
    NSString *action   = parts[1];

    return [[CPRBACService sharedService] currentUserCanPerform:action
                                                     onResource:resource];
}

#pragma mark - Error Factory

- (NSError *)errorWithCode:(CPAuthError)code description:(NSString *)description {
    return [NSError errorWithDomain:CPAuthErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@end
