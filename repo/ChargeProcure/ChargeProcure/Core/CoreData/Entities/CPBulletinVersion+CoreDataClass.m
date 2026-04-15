#import "CPBulletinVersion+CoreDataClass.h"
#import "CPBulletinVersion+CoreDataProperties.h"
#import "CPBulletin+CoreDataClass.h"
#import "CPBulletin+CoreDataProperties.h"

@implementation CPBulletinVersion

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context
           snapshotFromBulletin:(CPBulletin *)bulletin {
    NSParameterAssert(context);
    NSParameterAssert(bulletin);

    CPBulletinVersion *version = [NSEntityDescription
        insertNewObjectForEntityForName:@"BulletinVersion"
                 inManagedObjectContext:context];

    version.uuid      = [[NSUUID UUID] UUIDString];
    version.createdAt = [NSDate date];

    // Copy identifying link
    version.bulletinID = bulletin.uuid;
    version.bulletin   = bulletin;

    // Copy all content fields from the bulletin at the moment of snapshot
    version.title          = bulletin.title;
    version.summary        = bulletin.summary;
    version.createdByUserID = bulletin.authorID;

    // Snapshot both representations: `body` holds the plain-text / Markdown fallback,
    // `bodyHTML` holds the rich-text HTML written by the WYSIWYG editor (may be nil
    // for Markdown-mode bulletins).  Keep them distinct — do NOT copy body → bodyHTML.
    version.bodyMarkdown   = bulletin.body;
    version.bodyHTML       = bulletin.bodyHTML;

    // Determine next version number by inspecting existing versions on the bulletin.
    // If the bulletin's versions relationship is available, use max + 1; otherwise 1.
    NSInteger nextVersionNumber = 1;
    if ([bulletin respondsToSelector:NSSelectorFromString(@"versions")]) {
        NSSet *existingVersions = [bulletin valueForKey:@"versions"];
        for (CPBulletinVersion *v in existingVersions) {
            NSInteger n = v.versionNumber.integerValue;
            if (n >= nextVersionNumber) {
                nextVersionNumber = n + 1;
            }
        }
    }
    version.versionNumber = @(nextVersionNumber);

    return version;
}

@end
