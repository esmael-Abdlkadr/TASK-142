#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPAuthErrorDomain;
FOUNDATION_EXPORT NSString * const CPAuthSessionChangedNotification;

typedef NS_ENUM(NSInteger, CPAuthError) {
    CPAuthErrorInvalidCredentials = 1001,
    CPAuthErrorLockedOut = 1002,
    CPAuthErrorPasswordTooShort = 1003,
    CPAuthErrorPasswordNoNumber = 1004,
    CPAuthErrorBiometricUnavailable = 1005,
    CPAuthErrorBiometricFailed = 1006,
    CPAuthErrorUserNotFound = 1007,
    CPAuthErrorUserInactive = 1008,
    /// Returned when the account was seeded with a default password that must be changed.
    CPAuthErrorMustChangePassword = 1009,
};

@interface CPAuthService : NSObject

+ (instancetype)sharedService;

/// Returns YES if there is currently a valid session (user logged in).
@property (nonatomic, readonly) BOOL isSessionValid;
/// The currently authenticated user UUID. Nil when no session.
@property (nonatomic, readonly, nullable) NSString *currentUserID;
/// The currently authenticated user's username.
@property (nonatomic, readonly, nullable) NSString *currentUsername;
/// The currently authenticated user's role name.
@property (nonatomic, readonly, nullable) NSString *currentUserRole;

/// Login with username and password. Checks lockout, validates hash, logs audit.
- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Attempt biometric authentication for the current stored username.
- (void)authenticateWithBiometrics:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Logout the current session. Posts CPAuthSessionChangedNotification.
- (void)logout;

/// Create a new user. Admin only. Password must be >= 10 chars with >= 1 digit.
- (BOOL)createUserWithUsername:(NSString *)username
                      password:(NSString *)password
                      roleName:(NSString *)roleName
                         error:(NSError **)error;

/// Change password for userID. Old password must match.
- (BOOL)changePasswordForUserID:(NSString *)userID
                    oldPassword:(NSString *)oldPassword
                    newPassword:(NSString *)newPassword
                          error:(NSError **)error;

/// Change password without requiring the old password.
/// Valid only for accounts in the forced-rotation list (needsPasswordChange == YES).
/// Used during first-run bootstrap when the user cannot know the randomly-generated
/// initial password.  Clears the rotation flag on success.
- (BOOL)forceChangePasswordForUserID:(NSString *)userID
                         newPassword:(NSString *)newPassword
                               error:(NSError **)error;

/// Enable/disable biometric authentication for current user.
- (void)setBiometricEnabled:(BOOL)enabled;

/// Validate password meets requirements (>= 10 chars, >= 1 digit).
- (BOOL)validatePassword:(NSString *)password error:(NSError **)error;

/// Create default admin/technician/finance accounts if none exist. Returns YES if seeded.
/// On first run the generated credentials are stored in pendingBootstrapCredentials for
/// one-time display by AppDelegate; they are never written to logs.
- (BOOL)seedDefaultUsersIfNeeded;

/// Same as seedDefaultUsersIfNeeded but uses a caller-supplied password for all seeded
/// accounts instead of generating random ones. Intended for deterministic test setup only.
/// Must not be called in production code paths.
- (BOOL)seedDefaultUsersWithPassword:(NSString *)password;

/// Ephemeral bootstrap credentials set after first-run seeding.
/// Non-nil only during the first launch sequence; AppDelegate must consume and clear this
/// before the user can interact with the app to guarantee one-time display.
/// Never persisted to disk or written to any log.
@property (nonatomic, readonly, nullable, copy) NSDictionary<NSString *, NSString *> *pendingBootstrapCredentials;

/// Clears pendingBootstrapCredentials after the one-time display has been shown.
- (void)clearPendingBootstrapCredentials;

/// YES if the current session was seeded with a default password that must be rotated
/// before the user is permitted to use the app. Cleared on successful password change.
@property (nonatomic, readonly) BOOL needsPasswordChange;

/// Returns YES if the current user's role grants the given permission.
/// Use "admin" to check for Administrator role only.
/// Use "resource.action" format for specific permissions (e.g. "bulletin.create").
- (BOOL)currentUserHasPermission:(NSString *)permission;

@end

NS_ASSUME_NONNULL_END
