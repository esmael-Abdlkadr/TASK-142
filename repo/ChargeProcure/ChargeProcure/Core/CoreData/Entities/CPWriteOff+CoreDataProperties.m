#import "CPWriteOff+CoreDataProperties.h"

@implementation CPWriteOff (CoreDataProperties)

+ (NSFetchRequest<CPWriteOff *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"WriteOff"];
}

@dynamic uuid, invoiceID, approvedByUserID, reason, status, amount, approvedAt, invoice;

@end
