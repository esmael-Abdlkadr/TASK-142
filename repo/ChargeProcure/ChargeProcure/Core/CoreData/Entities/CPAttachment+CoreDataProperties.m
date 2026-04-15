#import "CPAttachment+CoreDataProperties.h"

@implementation CPAttachment (CoreDataProperties)

+ (NSFetchRequest<CPAttachment *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
}

@dynamic uuid, ownerID, ownerType, filename, mimeType, filePath, fileType;
@dynamic fileSize;
@dynamic uploadedAt;
@dynamic invoice, payment, receipt, returnRecord, bulletin;

@end
