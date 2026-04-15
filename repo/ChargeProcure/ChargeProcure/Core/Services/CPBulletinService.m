#import "CPBulletinService.h"
#import "CPAuditService.h"
#import "CPAuthService.h"
#import "../CoreData/CPCoreDataStack.h"
#import "../Utilities/CPIDGenerator.h"
#import "../CoreData/Entities/CPBulletin+CoreDataClass.h"
#import "../CoreData/Entities/CPBulletin+CoreDataProperties.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

NSString * const CPBulletinErrorDomain           = @"com.chargeprocure.bulletin";
NSString * const CPBulletinAutosavedNotification  = @"CPBulletinAutosavedNotification";
NSInteger  const CPBulletinMaxSummaryLength       = 280;

// ---------------------------------------------------------------------------
// Editor mode name ↔ enum helpers
// ---------------------------------------------------------------------------

static CPBulletinEditorMode _editorModeFromString(NSString *name) {
    if ([name isEqualToString:@"WYSIWYG"]) return CPBulletinEditorModeWYSIWYG;
    return CPBulletinEditorModeMarkdown; // default
}

static NSString *_editorModeToString(CPBulletinEditorMode mode) {
    switch (mode) {
        case CPBulletinEditorModeWYSIWYG: return @"WYSIWYG";
        default:                           return @"Markdown";
    }
}

static NSString *_statusStringForValue(CPBulletinStatus status) {
    switch (status) {
        case CPBulletinStatusDraft:     return @"Draft";
        case CPBulletinStatusPublished: return @"Published";
        case CPBulletinStatusScheduled: return @"Scheduled";
        case CPBulletinStatusArchived:  return @"Archived";
    }
    return @"Draft";
}

static CPBulletinStatus _statusValueFromString(NSString *str) {
    if ([str isEqualToString:@"Published"]) return CPBulletinStatusPublished;
    if ([str isEqualToString:@"Scheduled"]) return CPBulletinStatusScheduled;
    if ([str isEqualToString:@"Archived"])  return CPBulletinStatusArchived;
    return CPBulletinStatusDraft;
}

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface CPBulletinService ()
- (NSError *)errorWithCode:(CPBulletinError)code description:(NSString *)desc;
- (nullable CPBulletin *)_fetchBulletinWithUUID:(NSString *)uuid
                                      inContext:(NSManagedObjectContext *)ctx;
/// Creates and saves a BulletinVersion snapshot from the current bulletin state.
/// Returns the new version's UUID, or nil on failure.
- (nullable NSString *)_createVersionSnapshotForBulletin:(CPBulletin *)bulletin
                                               inContext:(NSManagedObjectContext *)ctx;
@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation CPBulletinService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPBulletinService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPBulletinService alloc] init];
    });
    return _shared;
}

#pragma mark - Compatibility Accessors

- (NSManagedObjectContext *)mainContext {
    return [CPCoreDataStack sharedStack].mainContext;
}

#pragma mark - Create Draft

- (nullable NSString *)createDraftWithTitle:(NSString *)title
                                 editorMode:(NSString *)editorMode
                                      error:(NSError **)error {
    NSParameterAssert(title.length > 0);

    __block NSString *bulletinUUID = nil;
    __block NSError *opError       = nil;
    dispatch_semaphore_t sem       = dispatch_semaphore_create(0);
    NSString *authorID             = [CPAuthService sharedService].currentUserID;

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPBulletin *bulletin = [CPBulletin insertInContext:ctx];
        bulletin.title           = title;
        bulletin.authorID        = authorID;
        bulletin.statusValue     = @(CPBulletinStatusDraft);
        bulletin.editorModeValue = @(_editorModeFromString(editorMode));
        bulletin.isPinned        = @NO;

        bulletinUUID = bulletin.uuid;

        NSError *saveErr = nil;
        if (![ctx save:&saveErr]) {
            opError = saveErr;
            bulletinUUID = nil;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return bulletinUUID;
}

#pragma mark - Autosave Draft

- (BOOL)autosaveDraft:(NSString *)bulletinUUID
                title:(NSString *)title
              summary:(nullable NSString *)summary
         bodyMarkdown:(nullable NSString *)bodyMarkdown
             bodyHTML:(nullable NSString *)bodyHTML
                error:(NSError **)error {
    NSParameterAssert(bulletinUUID.length > 0);

    // Validate summary length
    if (summary && (NSInteger)summary.length > CPBulletinMaxSummaryLength) {
        if (error) *error = [self errorWithCode:CPBulletinErrorSummaryTooLong
                                    description:[NSString stringWithFormat:
                                                 @"Summary must be %ld characters or fewer (got %lu).",
                                                 (long)CPBulletinMaxSummaryLength,
                                                 (unsigned long)summary.length]];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPBulletin *bulletin = [self _fetchBulletinWithUUID:bulletinUUID inContext:ctx];
        if (!bulletin) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        if (bulletin.statusValue.integerValue != CPBulletinStatusDraft) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft
                              description:@"Cannot autosave: bulletin is not a draft."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Update fields; DO NOT create a BulletinVersion
        if (title.length > 0) {
            bulletin.title = title;
        }
        if (summary)      bulletin.summary  = summary;
        if (bodyMarkdown) bulletin.body     = bodyMarkdown;
        // Store the HTML representation when provided (WYSIWYG mode).
        // bodyHTML is the canonical rich-text payload; body holds the plain-text fallback.
        if (bodyHTML != nil) bulletin.bodyHTML = bodyHTML;
        bulletin.updatedAt = [NSDate date];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;

            // Post autosaved notification on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:CPBulletinAutosavedNotification
                 object:self
                 userInfo:@{@"bulletinUUID": bulletinUUID}];
            });
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Publish Bulletin

- (BOOL)publishBulletin:(NSString *)bulletinUUID
              publishAt:(nullable NSDate *)publishAt
            unpublishAt:(nullable NSDate *)unpublishAt
     recommendationWeight:(NSInteger)weight
                  isPinned:(BOOL)isPinned
                    error:(NSError **)error {
    NSParameterAssert(bulletinUUID.length > 0);

    if (weight < 0 || weight > 100) {
        if (error) *error = [self errorWithCode:CPBulletinErrorInvalidWeight
                                    description:@"Recommendation weight must be between 0 and 100."];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPBulletin *bulletin = [self _fetchBulletinWithUUID:bulletinUUID inContext:ctx];
        if (!bulletin) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        CPBulletinStatus currentStatus = (CPBulletinStatus)bulletin.statusValue.integerValue;
        if (currentStatus == CPBulletinStatusArchived) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft
                              description:@"Cannot publish an archived bulletin."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Validate summary length
        if (bulletin.summary && (NSInteger)bulletin.summary.length > CPBulletinMaxSummaryLength) {
            opError = [self errorWithCode:CPBulletinErrorSummaryTooLong
                              description:[NSString stringWithFormat:
                                           @"Summary must be %ld characters or fewer.",
                                           (long)CPBulletinMaxSummaryLength]];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Determine effective status
        CPBulletinStatus newStatus;
        if (publishAt && [publishAt timeIntervalSinceNow] > 0) {
            // Future publish date → Scheduled
            newStatus = CPBulletinStatusScheduled;
        } else {
            // Immediate publish
            newStatus = CPBulletinStatusPublished;
        }

        bulletin.statusValue             = @(newStatus);
        bulletin.publishDate             = publishAt;
        bulletin.unpublishDate           = unpublishAt;
        bulletin.isPinned                = @(isPinned);
        bulletin.recommendationWeight    = @(weight);
        bulletin.updatedAt               = [NSDate date];

        // Create immutable BulletinVersion snapshot
        NSString *versionUUID = [self _createVersionSnapshotForBulletin:bulletin inContext:ctx];
        if (versionUUID) {
            bulletin.currentVersionID = versionUUID;
        }

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"bulletin_published"
                                             resource:@"Bulletin"
                                           resourceID:bulletinUUID
                                               detail:[NSString stringWithFormat:
                                                       @"Status=%@ Weight=%ld Pinned=%@ VersionUUID=%@",
                                                       _statusStringForValue(newStatus),
                                                       (long)weight,
                                                       isPinned ? @"YES" : @"NO",
                                                       versionUUID ?: @"none"]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Restore Version

- (BOOL)restoreVersion:(NSString *)versionUUID
           toBulletin:(NSString *)bulletinUUID
                error:(NSError **)error {
    NSParameterAssert(versionUUID.length > 0);
    NSParameterAssert(bulletinUUID.length > 0);

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        // Fetch the version
        NSFetchRequest *verReq = [NSFetchRequest fetchRequestWithEntityName:@"BulletinVersion"];
        verReq.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", versionUUID];
        verReq.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSArray *verArr   = [ctx executeFetchRequest:verReq error:&fetchErr];
        NSManagedObject *version = verArr.firstObject;

        if (!version) {
            opError = [self errorWithCode:CPBulletinErrorVersionNotFound
                              description:[NSString stringWithFormat:@"Version not found: %@", versionUUID]];
            dispatch_semaphore_signal(sem);
            return;
        }

        CPBulletin *bulletin = [self _fetchBulletinWithUUID:bulletinUUID inContext:ctx];
        if (!bulletin) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Determine current max version number
        NSFetchRequest *allVerReq = [NSFetchRequest fetchRequestWithEntityName:@"BulletinVersion"];
        allVerReq.predicate = [NSPredicate predicateWithFormat:@"bulletinID == %@", bulletinUUID];
        NSArray *allVersions = [ctx executeFetchRequest:allVerReq error:nil];
        NSInteger maxVersionNumber = 0;
        for (NSManagedObject *v in allVersions) {
            NSInteger vNum = [[v valueForKey:@"versionNumber"] integerValue];
            if (vNum > maxVersionNumber) maxVersionNumber = vNum;
        }

        // Copy version fields back to bulletin as a new draft
        bulletin.title           = [version valueForKey:@"title"]       ?: bulletin.title;
        bulletin.summary         = [version valueForKey:@"summary"];
        bulletin.body            = [version valueForKey:@"bodyMarkdown"];
        bulletin.bodyHTML        = [version valueForKey:@"bodyHTML"];
        bulletin.statusValue     = @(CPBulletinStatusDraft);
        bulletin.updatedAt       = [NSDate date];

        // Create a new BulletinVersion to record the restore point
        NSManagedObject *restoreVer = [NSEntityDescription insertNewObjectForEntityForName:@"BulletinVersion"
                                                                    inManagedObjectContext:ctx];
        [restoreVer setValue:[CPIDGenerator generateUUID]           forKey:@"uuid"];
        [restoreVer setValue:bulletinUUID                           forKey:@"bulletinID"];
        [restoreVer setValue:@(maxVersionNumber + 1)               forKey:@"versionNumber"];
        [restoreVer setValue:bulletin.title                         forKey:@"title"];
        [restoreVer setValue:bulletin.summary                       forKey:@"summary"];
        [restoreVer setValue:bulletin.body                          forKey:@"bodyMarkdown"];
        [restoreVer setValue:[version valueForKey:@"bodyHTML"]      forKey:@"bodyHTML"];
        [restoreVer setValue:[version valueForKey:@"coverImagePath"] forKey:@"coverImagePath"];
        [restoreVer setValue:[NSDate date]                          forKey:@"createdAt"];
        [restoreVer setValue:[CPAuthService sharedService].currentUserID forKey:@"createdByUserID"];
        [restoreVer setValue:bulletin                               forKey:@"bulletin"];

        bulletin.currentVersionID = [restoreVer valueForKey:@"uuid"];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"bulletin_version_restored"
                                             resource:@"Bulletin"
                                           resourceID:bulletinUUID
                                               detail:[NSString stringWithFormat:
                                                       @"RestoredFromVersionUUID=%@ NewVersionNumber=%ld",
                                                       versionUUID, (long)(maxVersionNumber + 1)]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Archive Bulletin

- (BOOL)archiveBulletin:(NSString *)bulletinUUID error:(NSError **)error {
    NSParameterAssert(bulletinUUID.length > 0);

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPBulletin *bulletin = [self _fetchBulletinWithUUID:bulletinUUID inContext:ctx];
        if (!bulletin) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        CPBulletinStatus currentStatus = (CPBulletinStatus)bulletin.statusValue.integerValue;
        if (currentStatus == CPBulletinStatusArchived) {
            // Already archived — idempotent success
            success = YES;
            dispatch_semaphore_signal(sem);
            return;
        }

        bulletin.statusValue = @(CPBulletinStatusArchived);
        bulletin.updatedAt   = [NSDate date];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"bulletin_archived"
                                             resource:@"Bulletin"
                                           resourceID:bulletinUUID
                                               detail:[NSString stringWithFormat:
                                                       @"PreviousStatus=%@",
                                                       _statusStringForValue(currentStatus)]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Fetch Bulletins

- (NSArray *)fetchBulletinsWithStatus:(nullable NSString *)status
                                offset:(NSInteger)offset
                                 limit:(NSInteger)limit {
    __block NSArray *results = @[];
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [CPBulletin fetchRequest];

        // Filter by status if provided
        if (status.length > 0) {
            CPBulletinStatus statusValue = _statusValueFromString(status);
            req.predicate = [NSPredicate predicateWithFormat:@"statusValue == %@", @(statusValue)];
        }

        // Sort: pinned first (isPinned DESC), then recommendationWeight DESC, then createdAt DESC
        req.sortDescriptors = @[
            // isPinned is stored as 0/1; descending puts YES (1) before NO (0)
            [NSSortDescriptor sortDescriptorWithKey:@"isPinned" ascending:NO],
            [NSSortDescriptor sortDescriptorWithKey:@"recommendationWeight" ascending:NO],
            [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO],
        ];

        if (offset > 0)  req.fetchOffset = (NSUInteger)offset;
        if (limit > 0)   req.fetchLimit  = (NSUInteger)limit;

        NSError *err = nil;
        results = [ctx executeFetchRequest:req error:&err];
        if (err) {
            NSLog(@"[CPBulletinService] fetchBulletins error: %@", err.localizedDescription);
        }
    }];
    return results ?: @[];
}

#pragma mark - Fetch Versions

- (NSArray *)fetchVersionsForBulletin:(NSString *)bulletinUUID {
    NSParameterAssert(bulletinUUID.length > 0);

    __block NSArray *results = @[];
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"BulletinVersion"];
        req.predicate       = [NSPredicate predicateWithFormat:@"bulletinID == %@", bulletinUUID];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"versionNumber"
                                                              ascending:NO]];
        NSError *err = nil;
        results = [ctx executeFetchRequest:req error:&err];
        if (err) {
            NSLog(@"[CPBulletinService] fetchVersionsForBulletin error: %@", err.localizedDescription);
        }
    }];
    return results ?: @[];
}

#pragma mark - Process Scheduled Bulletins

- (void)processScheduledBulletins {
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSDate *now = [NSDate date];

        // --- Scheduled → Published ---
        NSFetchRequest *scheduledReq = [CPBulletin fetchRequest];
        scheduledReq.predicate = [NSPredicate predicateWithFormat:
                                  @"statusValue == %@ AND publishDate != nil AND publishDate <= %@",
                                  @(CPBulletinStatusScheduled), now];
        NSError *err = nil;
        NSArray *toPublish = [ctx executeFetchRequest:scheduledReq error:&err];
        for (CPBulletin *bulletin in toPublish) {
            bulletin.statusValue = @(CPBulletinStatusPublished);
            bulletin.updatedAt   = now;
            NSLog(@"[CPBulletinService] Auto-published bulletin: %@", bulletin.uuid);
            [[CPAuditService sharedService] logAction:@"bulletin_auto_published"
                                             resource:@"Bulletin"
                                           resourceID:bulletin.uuid
                                               detail:@"Scheduled publish date reached"];
        }

        // --- Published → Archived (unpublish date passed) ---
        NSFetchRequest *expiredReq = [CPBulletin fetchRequest];
        expiredReq.predicate = [NSPredicate predicateWithFormat:
                                @"statusValue == %@ AND unpublishDate != nil AND unpublishDate <= %@",
                                @(CPBulletinStatusPublished), now];
        NSArray *toUnpublish = [ctx executeFetchRequest:expiredReq error:&err];
        for (CPBulletin *bulletin in toUnpublish) {
            bulletin.statusValue = @(CPBulletinStatusArchived);
            bulletin.updatedAt   = now;
            NSLog(@"[CPBulletinService] Auto-archived bulletin: %@", bulletin.uuid);
            [[CPAuditService sharedService] logAction:@"bulletin_auto_archived"
                                             resource:@"Bulletin"
                                           resourceID:bulletin.uuid
                                               detail:@"Unpublish date reached"];
        }

        if (toPublish.count > 0 || toUnpublish.count > 0) {
            NSError *saveErr = nil;
            [ctx save:&saveErr];
            if (saveErr) {
                NSLog(@"[CPBulletinService] processScheduledBulletins save error: %@",
                      saveErr.localizedDescription);
            }
        }
    }];
}

#pragma mark - Compatibility Wrappers

- (void)autosaveDraft:(NSString *)uuid
                title:(NSString *)title
              summary:(nullable NSString *)summary
                 body:(nullable NSString *)body
             bodyHTML:(nullable NSString *)bodyHTML
 recommendationWeight:(nullable NSNumber *)weight
             isPinned:(BOOL)isPinned
          publishDate:(nullable NSDate *)publishDate
        unpublishDate:(nullable NSDate *)unpublishDate
           completion:(void(^)(NSString *_Nullable savedUUID, NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSError *error = nil;
        NSString *savedUUID = uuid;
        NSString *draftTitle = title.length > 0 ? title : @"Untitled Bulletin";
        // Infer editor mode from whether an HTML body is provided
        NSString *editorMode = bodyHTML.length > 0 ? @"WYSIWYG" : @"Markdown";

        if (savedUUID.length == 0) {
            savedUUID = [self createDraftWithTitle:draftTitle editorMode:editorMode error:&error];
        }

        if (!error && savedUUID.length > 0) {
            BOOL autosaved = [self autosaveDraft:savedUUID
                                           title:draftTitle
                                         summary:summary
                                    bodyMarkdown:body
                                        bodyHTML:bodyHTML
                                           error:&error];
            if (!autosaved && !error) {
                error = [self errorWithCode:CPBulletinErrorNotDraft description:@"Unable to autosave draft."];
            }
        }

        if (!error && savedUUID.length > 0) {
            NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
            [ctx performBlockAndWait:^{
                CPBulletin *bulletin = [self _fetchBulletinWithUUID:savedUUID inContext:ctx];
                if (!bulletin) {
                    error = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
                    return;
                }

                bulletin.recommendationWeight = weight ?: @0;
                bulletin.isPinned = @(isPinned);
                bulletin.publishDate = publishDate;
                bulletin.unpublishDate = unpublishDate;
                bulletin.updatedAt = [NSDate date];

                NSError *saveError = nil;
                if (![ctx save:&saveError]) {
                    error = saveError;
                }
            }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(savedUUID, error);
        });
    });
}

- (void)setCoverImagePath:(NSString *)path forBulletinUUID:(NSString *)bulletinUUID {
    if (bulletinUUID.length == 0) return;
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPBulletin *bulletin = [self _fetchBulletinWithUUID:bulletinUUID inContext:ctx];
        if (!bulletin) return;
        bulletin.coverImagePath = path;
        bulletin.updatedAt = [NSDate date];
        [ctx save:nil];
    }];
}

- (void)setEditorMode:(NSInteger)mode forBulletinUUID:(NSString *)bulletinUUID {
    if (bulletinUUID.length == 0) return;
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPBulletin *bulletin = [self _fetchBulletinWithUUID:bulletinUUID inContext:ctx];
        if (!bulletin) return;
        bulletin.editorModeValue = @(mode);
        bulletin.updatedAt = [NSDate date];
        [ctx save:nil];
    }];
}

- (void)publishBulletinWithUUID:(NSString *)uuid
                     completion:(void(^)(NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSDate *publishAt = nil;
        __block NSDate *unpublishAt = nil;
        __block NSInteger weight = 0;
        __block BOOL isPinned = NO;
        __block NSError *error = nil;

        NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [ctx performBlockAndWait:^{
            CPBulletin *bulletin = [self _fetchBulletinWithUUID:uuid inContext:ctx];
            if (!bulletin) {
                error = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
                return;
            }

            publishAt = bulletin.publishDate;
            unpublishAt = bulletin.unpublishDate;
            weight = bulletin.recommendationWeight.integerValue;
            isPinned = bulletin.isPinned.boolValue;
        }];

        if (!error) {
            [self publishBulletin:uuid
                        publishAt:publishAt
                      unpublishAt:unpublishAt
             recommendationWeight:weight
                         isPinned:isPinned
                            error:&error];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    });
}

- (void)archiveBulletinWithUUID:(NSString *)uuid
                     completion:(void(^)(NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        [self archiveBulletin:uuid error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    });
}

- (void)restoreDraftBulletinWithUUID:(NSString *)uuid
                          completion:(void(^)(NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSError *error = nil;
        NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [ctx performBlockAndWait:^{
            CPBulletin *bulletin = [self _fetchBulletinWithUUID:uuid inContext:ctx];
            if (!bulletin) {
                error = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
                return;
            }

            bulletin.statusValue = @(CPBulletinStatusDraft);
            bulletin.publishDate = nil;
            bulletin.unpublishDate = nil;
            bulletin.updatedAt = [NSDate date];

            NSError *saveError = nil;
            if (![ctx save:&saveError]) {
                error = saveError;
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    });
}

#pragma mark - Delete Draft

- (BOOL)deleteDraft:(NSString *)bulletinUUID error:(NSError **)error {
    NSParameterAssert(bulletinUUID.length > 0);

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPBulletin *bulletin = [self _fetchBulletinWithUUID:bulletinUUID inContext:ctx];
        if (!bulletin) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft description:@"Bulletin not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        CPBulletinStatus currentStatus = (CPBulletinStatus)bulletin.statusValue.integerValue;
        if (currentStatus != CPBulletinStatusDraft) {
            opError = [self errorWithCode:CPBulletinErrorNotDraft
                              description:[NSString stringWithFormat:
                                           @"Only draft bulletins can be deleted. Current status: %@.",
                                           _statusStringForValue(currentStatus)]];
            dispatch_semaphore_signal(sem);
            return;
        }

        [ctx deleteObject:bulletin];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Private Helpers

- (nullable CPBulletin *)_fetchBulletinWithUUID:(NSString *)uuid
                                      inContext:(NSManagedObjectContext *)ctx {
    if (!uuid.length) return nil;
    NSFetchRequest *req = [CPBulletin fetchRequest];
    req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
    req.fetchLimit = 1;
    NSError *err = nil;
    NSArray *arr = [ctx executeFetchRequest:req error:&err];
    return (CPBulletin *)arr.firstObject;
}

- (nullable NSString *)_createVersionSnapshotForBulletin:(CPBulletin *)bulletin
                                               inContext:(NSManagedObjectContext *)ctx {
    // Calculate the next version number
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"BulletinVersion"];
    req.predicate = [NSPredicate predicateWithFormat:@"bulletinID == %@", bulletin.uuid];
    NSError *err = nil;
    NSArray *existingVersions = [ctx executeFetchRequest:req error:&err];
    NSInteger maxVersionNumber = 0;
    for (NSManagedObject *v in existingVersions) {
        NSInteger vNum = [[v valueForKey:@"versionNumber"] integerValue];
        if (vNum > maxVersionNumber) maxVersionNumber = vNum;
    }
    NSInteger nextVersionNumber = maxVersionNumber + 1;

    NSString *versionUUID = [CPIDGenerator generateUUID];
    NSManagedObject *version = [NSEntityDescription insertNewObjectForEntityForName:@"BulletinVersion"
                                                             inManagedObjectContext:ctx];
    [version setValue:versionUUID                                        forKey:@"uuid"];
    [version setValue:bulletin.uuid                                      forKey:@"bulletinID"];
    [version setValue:@(nextVersionNumber)                               forKey:@"versionNumber"];
    [version setValue:bulletin.title                                     forKey:@"title"];
    [version setValue:bulletin.summary                                   forKey:@"summary"];
    [version setValue:bulletin.body                                      forKey:@"bodyMarkdown"];
    [version setValue:bulletin.bodyHTML                                  forKey:@"bodyHTML"];
    [version setValue:bulletin.coverImagePath                           forKey:@"coverImagePath"];
    [version setValue:[NSDate date]                                      forKey:@"createdAt"];
    [version setValue:[CPAuthService sharedService].currentUserID       forKey:@"createdByUserID"];
    [version setValue:bulletin                                           forKey:@"bulletin"];

    return versionUUID;
}

- (NSError *)errorWithCode:(CPBulletinError)code description:(NSString *)desc {
    return [NSError errorWithDomain:CPBulletinErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: desc}];
}

@end
