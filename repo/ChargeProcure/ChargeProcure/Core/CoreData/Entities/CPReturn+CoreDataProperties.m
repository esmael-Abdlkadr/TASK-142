#import "CPReturn+CoreDataProperties.h"

@implementation CPReturn (CoreDataProperties)

+ (NSFetchRequest<CPReturn *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Return"];
}

@dynamic uuid, caseID, receiptID, returnNumber, reason, status, returnedByUserID, amount, returnedAt, procurementCase, attachments;

@end
