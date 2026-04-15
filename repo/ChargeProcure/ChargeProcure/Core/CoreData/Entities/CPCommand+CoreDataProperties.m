#import "CPCommand+CoreDataProperties.h"

@implementation CPCommand (CoreDataProperties)

+ (NSFetchRequest<CPCommand *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Command"];
}

@dynamic uuid, chargerID, commandType, parameters, issuedByUserID, pendingReviewReason, status;
@dynamic issuedAt, acknowledgedAt;
@dynamic charger;

@end
