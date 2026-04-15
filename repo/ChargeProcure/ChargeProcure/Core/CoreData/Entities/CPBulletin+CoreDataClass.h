#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents the publication lifecycle of a bulletin.
typedef NS_ENUM(NSInteger, CPBulletinStatus) {
    CPBulletinStatusDraft      = 0,
    CPBulletinStatusPublished  = 1,
    CPBulletinStatusScheduled  = 2,
    CPBulletinStatusArchived   = 3
};

/// Determines how bulletin content was authored.
typedef NS_ENUM(NSInteger, CPBulletinEditorMode) {
    CPBulletinEditorModeMarkdown = 0,
    CPBulletinEditorModeWYSIWYG  = 1
};

@interface CPBulletin : NSManagedObject

+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

/// Returns YES if the bulletin's unpublishDate is non-nil and is in the past.
- (BOOL)isPastUnpublishDate;

/// Returns YES if the bulletin is scheduled and its publishDate is now or in the past.
- (BOOL)shouldAutoPublish;

@end

NS_ASSUME_NONNULL_END

#import "CPBulletin+CoreDataProperties.h"
