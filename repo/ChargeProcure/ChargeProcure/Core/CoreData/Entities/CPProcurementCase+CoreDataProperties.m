#import "CPProcurementCase+CoreDataProperties.h"

@implementation CPProcurementCase (CoreDataProperties)

+ (NSFetchRequest<CPProcurementCase *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
}

@dynamic uuid, caseNumber, title, caseDescription, stageValue, estimatedAmount, actualAmount, currencyCode, requestorID, assigneeID, vendorName, poNumber, invoiceNumber, createdAt, updatedAt, requiredByDate, closedAt, metadata, priority, requiresComplianceReview;

@end
