#import "CPBulletinVersion+CoreDataProperties.h"

@implementation CPBulletinVersion (CoreDataProperties)

+ (NSFetchRequest<CPBulletinVersion *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"BulletinVersion"];
}

@dynamic uuid, bulletinID, versionNumber;
@dynamic title, summary, bodyMarkdown, bodyHTML, coverImagePath, createdByUserID;
@dynamic createdAt;
@dynamic bulletin;

@end
