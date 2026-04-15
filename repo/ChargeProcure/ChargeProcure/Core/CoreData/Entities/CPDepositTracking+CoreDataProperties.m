#import "CPDepositTracking+CoreDataProperties.h"

@implementation CPDepositTracking (CoreDataProperties)

+ (NSFetchRequest<CPDepositTracking *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"DepositTracking"];
}

@dynamic uuid, chargerID, customerRef, status, notes, depositAmount, preAuthAmount, capturedAt, releasedAt;

@end
