#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPBulletinErrorDomain;
FOUNDATION_EXPORT NSString * const CPBulletinAutosavedNotification;
FOUNDATION_EXPORT NSInteger const CPBulletinMaxSummaryLength;  // 280

typedef NS_ENUM(NSInteger, CPBulletinError) {
    CPBulletinErrorSummaryTooLong = 3001,
    CPBulletinErrorInvalidWeight = 3002,
    CPBulletinErrorNotDraft = 3003,
    CPBulletinErrorAttachmentTooLarge = 3004,
    CPBulletinErrorVersionNotFound = 3005,
};

@interface CPBulletinService : NSObject

+ (instancetype)sharedService;

/// Compatibility access to the shared view context used by older view controllers.
- (NSManagedObjectContext *)mainContext;

/// Create a new draft bulletin. Returns UUID.
- (nullable NSString *)createDraftWithTitle:(NSString *)title
                                 editorMode:(NSString *)editorMode
                                      error:(NSError **)error;

/// Autosave draft. Does NOT create a version. Called every 10 seconds by the editor.
- (BOOL)autosaveDraft:(NSString *)bulletinUUID
                title:(NSString *)title
              summary:(nullable NSString *)summary
         bodyMarkdown:(nullable NSString *)bodyMarkdown
             bodyHTML:(nullable NSString *)bodyHTML
                error:(NSError **)error;

/// Publish bulletin. Creates immutable BulletinVersion snapshot.
/// publishAt: nil = immediately; unpublishAt: nil = indefinite.
- (BOOL)publishBulletin:(NSString *)bulletinUUID
              publishAt:(nullable NSDate *)publishAt
            unpublishAt:(nullable NSDate *)unpublishAt
     recommendationWeight:(NSInteger)weight
                  isPinned:(BOOL)isPinned
                    error:(NSError **)error;

/// Restore bulletin from a historical version (creates new draft from version).
- (BOOL)restoreVersion:(NSString *)versionUUID toBulletin:(NSString *)bulletinUUID error:(NSError **)error;

/// Archive a published bulletin.
- (BOOL)archiveBulletin:(NSString *)bulletinUUID error:(NSError **)error;

/// Fetch bulletins sorted by pin status then recommendation weight.
- (NSArray *)fetchBulletinsWithStatus:(nullable NSString *)status
                                offset:(NSInteger)offset
                                 limit:(NSInteger)limit;

/// Fetch version history for a bulletin.
- (NSArray *)fetchVersionsForBulletin:(NSString *)bulletinUUID;

/// Check and process scheduled publish/unpublish actions. Called periodically.
- (void)processScheduledBulletins;

/// Delete a draft. Only drafts can be deleted; published bulletins are archived.
- (BOOL)deleteDraft:(NSString *)bulletinUUID error:(NSError **)error;

/// Persist a locally saved cover image path onto the bulletin entity.
- (void)setCoverImagePath:(NSString *)path forBulletinUUID:(NSString *)bulletinUUID;

/// Persist the editor mode (0 = Markdown, 1 = WYSIWYG) onto the bulletin entity.
/// Called by the editor after each autosave so the mode is restored on next open.
- (void)setEditorMode:(NSInteger)mode forBulletinUUID:(NSString *)bulletinUUID;

/// Compatibility wrapper used by the bulletin editor. Persists body text, HTML
/// (for WYSIWYG mode), scheduling fields, and weight/pin in a single async call.
- (void)autosaveDraft:(NSString *)uuid
                title:(NSString *)title
              summary:(nullable NSString *)summary
                 body:(nullable NSString *)body
             bodyHTML:(nullable NSString *)bodyHTML
 recommendationWeight:(nullable NSNumber *)weight
             isPinned:(BOOL)isPinned
          publishDate:(nullable NSDate *)publishDate
        unpublishDate:(nullable NSDate *)unpublishDate
           completion:(void(^)(NSString *_Nullable savedUUID, NSError *_Nullable error))completion;

/// Compatibility wrapper used by older bulletin detail/editor flows.
- (void)publishBulletinWithUUID:(NSString *)uuid
                     completion:(void(^)(NSError *_Nullable error))completion;

/// Compatibility wrapper used by older bulletin detail flows.
- (void)archiveBulletinWithUUID:(NSString *)uuid
                     completion:(void(^)(NSError *_Nullable error))completion;

/// Compatibility wrapper used by older bulletin detail flows.
- (void)restoreDraftBulletinWithUUID:(NSString *)uuid
                          completion:(void(^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
