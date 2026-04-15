#import "CPInvoiceLineItem+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPInvoiceLineItem

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPInvoiceLineItem *obj = [NSEntityDescription insertNewObjectForEntityForName:@"InvoiceLineItem" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
