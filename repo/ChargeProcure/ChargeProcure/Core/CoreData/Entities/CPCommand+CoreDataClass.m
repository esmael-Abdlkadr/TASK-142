#import "CPCommand+CoreDataClass.h"
#import "CPCommand+CoreDataProperties.h"

/// Maps between CPCommandStatus enum and its canonical string representation.
static NSString * const kCPCommandStatusPending       = @"Pending";
static NSString * const kCPCommandStatusAcknowledged  = @"Acknowledged";
static NSString * const kCPCommandStatusFailed        = @"Failed";
static NSString * const kCPCommandStatusPendingReview = @"PendingReview";
static NSString * const kCPCommandStatusTimedOut      = @"TimedOut";

@implementation CPCommand

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPCommand *command = [NSEntityDescription insertNewObjectForEntityForName:@"Command"
                                                       inManagedObjectContext:context];
    command.uuid     = [[NSUUID UUID] UUIDString];
    command.issuedAt = [NSDate date];
    command.status   = kCPCommandStatusPending;
    return command;
}

#pragma mark - Typed Status Accessors

- (CPCommandStatus)commandStatus {
    NSString *s = self.status;
    if ([s isEqualToString:kCPCommandStatusAcknowledged])  { return CPCommandStatusAcknowledged; }
    if ([s isEqualToString:kCPCommandStatusFailed])        { return CPCommandStatusFailed; }
    if ([s isEqualToString:kCPCommandStatusPendingReview]) { return CPCommandStatusPendingReview; }
    if ([s isEqualToString:kCPCommandStatusTimedOut])      { return CPCommandStatusTimedOut; }
    return CPCommandStatusPending;
}

- (void)setCommandStatus:(CPCommandStatus)commandStatus {
    switch (commandStatus) {
        case CPCommandStatusAcknowledged:
            self.status = kCPCommandStatusAcknowledged;
            break;
        case CPCommandStatusFailed:
            self.status = kCPCommandStatusFailed;
            break;
        case CPCommandStatusPendingReview:
            self.status = kCPCommandStatusPendingReview;
            break;
        case CPCommandStatusTimedOut:
            self.status = kCPCommandStatusTimedOut;
            break;
        case CPCommandStatusPending:
        default:
            self.status = kCPCommandStatusPending;
            break;
    }
}

@end
