#import "CPBulletin+CoreDataClass.h"
#import "CPBulletin+CoreDataProperties.h"

@implementation CPBulletin

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPBulletin *bulletin = [NSEntityDescription insertNewObjectForEntityForName:@"Bulletin"
                                                         inManagedObjectContext:context];
    bulletin.uuid = [[NSUUID UUID] UUIDString];
    bulletin.createdAt = [NSDate date];
    bulletin.updatedAt = [NSDate date];
    bulletin.statusValue = @(CPBulletinStatusDraft);
    bulletin.editorModeValue = @(CPBulletinEditorModeMarkdown);
    bulletin.isPinned = @NO;
    return bulletin;
}

#pragma mark - Business Logic

- (BOOL)isPastUnpublishDate {
    if (self.unpublishDate == nil) {
        return NO;
    }
    // Returns YES if unpublishDate is in the past (i.e. now is after unpublishDate)
    return [self.unpublishDate timeIntervalSinceNow] < 0;
}

- (BOOL)shouldAutoPublish {
    // A bulletin should auto-publish only when it is in the Scheduled state
    // and its publishDate has arrived (is now or in the past).
    if (self.statusValue.integerValue != CPBulletinStatusScheduled) {
        return NO;
    }
    if (self.publishDate == nil) {
        return NO;
    }
    return [self.publishDate timeIntervalSinceNow] <= 0;
}

@end
