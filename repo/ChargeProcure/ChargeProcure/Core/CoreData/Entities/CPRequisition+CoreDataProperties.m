#import "CPRequisition+CoreDataProperties.h"

@implementation CPRequisition (CoreDataProperties)

+ (NSFetchRequest<CPRequisition *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Requisition"];
}

@dynamic uuid, caseID, requestedBy, desc, justification, status, notes, approvedByUserID, estimatedAmount, createdAt, approvedAt, procurementCase, lineItems;

@end
