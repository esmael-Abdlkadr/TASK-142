#import "CPSessionManager.h"

static NSString * const kCPSessionUserID = @"com.chargeprocure.session.userID";
static NSString * const kCPSessionUsername = @"com.chargeprocure.session.username";
static NSString * const kCPSessionRole = @"com.chargeprocure.session.role";

@implementation CPSessionManager

+ (instancetype)sharedManager {
    static CPSessionManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPSessionManager alloc] init];
    });
    return instance;
}

- (BOOL)isSessionValid {
    return [NSUserDefaults.standardUserDefaults stringForKey:kCPSessionUserID] != nil;
}

- (nullable NSString *)currentUserID {
    return [NSUserDefaults.standardUserDefaults stringForKey:kCPSessionUserID];
}

- (nullable NSString *)currentUsername {
    return [NSUserDefaults.standardUserDefaults stringForKey:kCPSessionUsername];
}

- (nullable NSString *)currentUserRole {
    return [NSUserDefaults.standardUserDefaults stringForKey:kCPSessionRole];
}

- (void)storeSessionForUserID:(NSString *)userID username:(NSString *)username roleName:(NSString *)roleName {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:userID forKey:kCPSessionUserID];
    [defaults setObject:username forKey:kCPSessionUsername];
    [defaults setObject:roleName forKey:kCPSessionRole];
    [defaults synchronize];
}

- (void)clearSession {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:kCPSessionUserID];
    [defaults removeObjectForKey:kCPSessionUsername];
    [defaults removeObjectForKey:kCPSessionRole];
    [defaults synchronize];
}

@end
