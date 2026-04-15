#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages the current user session (stored in NSUserDefaults, not keychain, for demo simplicity)
@interface CPSessionManager : NSObject

+ (instancetype)sharedManager;

/// Returns YES if a session is currently stored
@property (nonatomic, readonly) BOOL isSessionValid;

/// Stored user UUID
@property (nonatomic, readonly, nullable) NSString *currentUserID;

/// Stored username
@property (nonatomic, readonly, nullable) NSString *currentUsername;

/// Stored role name
@property (nonatomic, readonly, nullable) NSString *currentUserRole;

/// Store session after successful login
- (void)storeSessionForUserID:(NSString *)userID
                     username:(NSString *)username
                     roleName:(NSString *)roleName;

/// Clear the stored session on logout
- (void)clearSession;

@end

NS_ASSUME_NONNULL_END
