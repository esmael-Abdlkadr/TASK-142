#import "CPAttachment+CoreDataClass.h"
#import "CPAttachment+CoreDataProperties.h"

@implementation CPAttachment

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPAttachment *attachment = [NSEntityDescription insertNewObjectForEntityForName:@"Attachment"
                                                             inManagedObjectContext:context];
    attachment.uuid       = [[NSUUID UUID] UUIDString];
    attachment.uploadedAt = [NSDate date];
    return attachment;
}

@end
