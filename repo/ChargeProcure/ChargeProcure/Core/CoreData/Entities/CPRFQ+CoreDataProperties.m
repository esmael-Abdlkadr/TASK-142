#import "CPRFQ+CoreDataProperties.h"

@implementation CPRFQ (CoreDataProperties)

+ (NSFetchRequest<CPRFQ *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"RFQ"];
}

@dynamic uuid, caseID, status, notes, issuedAt, dueDate, procurementCase, bids;

@end
