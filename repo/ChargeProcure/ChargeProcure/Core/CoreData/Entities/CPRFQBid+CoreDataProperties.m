#import "CPRFQBid+CoreDataProperties.h"

@implementation CPRFQBid (CoreDataProperties)

+ (NSFetchRequest<CPRFQBid *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
}

@dynamic uuid, rfqID, vendorID, vendorName, notes, isSelected, unitPrice, totalPrice, taxAmount, submittedAt, rfq;

@end
