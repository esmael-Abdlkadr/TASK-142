#import "CPUser+CoreDataClass.h"
#import "CPUser+CoreDataProperties.h"

// Lockout constants
static const NSInteger CPUserMaxFailedAttempts = 5;
static const NSTimeInterval CPUserLockoutDuration = 900.0; // 15 minutes

@implementation CPUser

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPUser *user = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                inManagedObjectContext:context];
    user.uuid = [[NSUUID UUID] UUIDString];
    user.createdAt = [NSDate date];
    user.failedAttempts = @0;
    user.isActive = @YES;
    user.biometricEnabled = @NO;
    return user;
}

#pragma mark - Lockout Logic

- (BOOL)isLockedOut {
    if (self.lockoutUntil == nil) {
        return NO;
    }
    // Locked out if lockoutUntil is in the future
    return [self.lockoutUntil timeIntervalSinceNow] > 0;
}

- (void)recordFailedAttempt {
    NSInteger currentAttempts = self.failedAttempts ? self.failedAttempts.integerValue : 0;
    currentAttempts += 1;
    self.failedAttempts = @(currentAttempts);

    if (currentAttempts >= CPUserMaxFailedAttempts) {
        self.lockoutUntil = [NSDate dateWithTimeIntervalSinceNow:CPUserLockoutDuration];
        NSLog(@"[CPUser] User '%@' locked out until %@.", self.username, self.lockoutUntil);
    }
}

- (void)resetFailedAttempts {
    self.failedAttempts = @0;
    self.lockoutUntil = nil;
}

@end
