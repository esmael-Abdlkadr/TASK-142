#import "CPDepositRule+CoreDataProperties.h"

@implementation CPDepositRule (CoreDataProperties)

+ (NSFetchRequest<CPDepositRule *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"DepositRule"];
}

@dynamic uuid, serviceType, notes, isActive, depositAmount, preAuthAmount, effectiveStart, effectiveEnd;

@end
