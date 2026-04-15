#import "CPBulletin+CoreDataProperties.h"

@implementation CPBulletin (CoreDataProperties)

+ (NSFetchRequest<CPBulletin *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
}

@dynamic uuid, title, summary, body, bodyHTML, statusValue, editorModeValue, isPinned,
         recommendationWeight, coverImagePath, publishDate, unpublishDate,
         createdAt, updatedAt, authorID, currentVersionID, tags, externalURL;

@end
