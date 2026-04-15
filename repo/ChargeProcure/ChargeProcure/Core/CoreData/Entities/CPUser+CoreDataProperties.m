#import "CPUser+CoreDataProperties.h"

@implementation CPUser (CoreDataProperties)

+ (NSFetchRequest<CPUser *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"User"];
}

@dynamic uuid, username, passwordHash, salt, failedAttempts, lockoutUntil, createdAt, lastLoginAt, isActive, biometricEnabled, role, auditEvents;

@end
