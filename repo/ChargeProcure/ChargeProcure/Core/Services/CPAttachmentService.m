#import "CPAttachmentService.h"
#import "CPCoreDataStack.h"
#import "CPAuthService.h"
#import <CoreData/CoreData.h>

NSString * const CPAttachmentErrorDomain = @"com.chargeprocure.attachment";
NSInteger  const CPAttachmentMaxSizeBytes = 25 * 1024 * 1024; // 25 MB

// Magic byte signatures
static const uint8_t kPDFMagic[]  = {0x25, 0x50, 0x44, 0x46}; // %PDF
static const uint8_t kJPEGMagic[] = {0xFF, 0xD8, 0xFF};
static const uint8_t kPNGMagic[]  = {0x89, 0x50, 0x4E, 0x47}; // .PNG

// Valid owner types
static NSArray<NSString *> *validOwnerTypes(void) {
    return @[@"Receipt", @"Return", @"Invoice", @"Payment", @"Bulletin"];
}

@implementation CPAttachmentService

+ (instancetype)sharedService {
    static CPAttachmentService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPAttachmentService alloc] init];
    });
    return instance;
}

#pragma mark - Attachments Directory

- (NSString *)attachmentsDirectory {
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docsDir stringByAppendingPathComponent:@"Attachments"];
}

- (BOOL)ensureAttachmentsDirectoryExists:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [self attachmentsDirectory];
    if (![fm fileExistsAtPath:dir]) {
        return [fm createDirectoryAtPath:dir
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:error];
    }
    return YES;
}

#pragma mark - File Type Detection

- (CPAttachmentFileType)detectFileTypeFromData:(NSData *)data {
    if (!data || data.length < 4) {
        return CPAttachmentFileTypeUnknown;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;

    // PDF: first 4 bytes == 0x25 0x50 0x44 0x46 (%PDF)
    if (data.length >= 4 &&
        bytes[0] == kPDFMagic[0] &&
        bytes[1] == kPDFMagic[1] &&
        bytes[2] == kPDFMagic[2] &&
        bytes[3] == kPDFMagic[3]) {
        return CPAttachmentFileTypePDF;
    }

    // JPEG: first 3 bytes == 0xFF 0xD8 0xFF
    if (data.length >= 3 &&
        bytes[0] == kJPEGMagic[0] &&
        bytes[1] == kJPEGMagic[1] &&
        bytes[2] == kJPEGMagic[2]) {
        return CPAttachmentFileTypeJPEG;
    }

    // PNG: first 4 bytes == 0x89 0x50 0x4E 0x47
    if (data.length >= 4 &&
        bytes[0] == kPNGMagic[0] &&
        bytes[1] == kPNGMagic[1] &&
        bytes[2] == kPNGMagic[2] &&
        bytes[3] == kPNGMagic[3]) {
        return CPAttachmentFileTypePNG;
    }

    return CPAttachmentFileTypeUnknown;
}

- (NSString *)extensionForFileType:(CPAttachmentFileType)fileType {
    switch (fileType) {
        case CPAttachmentFileTypePDF:  return @"pdf";
        case CPAttachmentFileTypeJPEG: return @"jpg";
        case CPAttachmentFileTypePNG:  return @"png";
        default:                        return @"bin";
    }
}

- (NSString *)mimeTypeForFileType:(CPAttachmentFileType)fileType {
    switch (fileType) {
        case CPAttachmentFileTypePDF:  return @"application/pdf";
        case CPAttachmentFileTypeJPEG: return @"image/jpeg";
        case CPAttachmentFileTypePNG:  return @"image/png";
        default:                        return @"application/octet-stream";
    }
}

#pragma mark - Save Attachment

- (nullable NSString *)saveAttachmentData:(NSData *)data
                                 filename:(NSString *)filename
                                  ownerID:(NSString *)ownerID
                                ownerType:(NSString *)ownerType
                                    error:(NSError **)error {
    // Validate owner type
    if (![validOwnerTypes() containsObject:ownerType]) {
        if (error) {
            *error = [NSError errorWithDomain:CPAttachmentErrorDomain
                                         code:CPAttachmentErrorInvalidType
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Invalid owner type '%@'. Must be one of: %@.",
                                                     ownerType, [validOwnerTypes() componentsJoinedByString:@", "]]}];
        }
        return nil;
    }

    // Size check before writing
    if ((NSInteger)data.length > CPAttachmentMaxSizeBytes) {
        if (error) {
            *error = [NSError errorWithDomain:CPAttachmentErrorDomain
                                         code:CPAttachmentErrorFileTooLarge
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"File size (%lu bytes) exceeds 25MB limit.",
                                                     (unsigned long)data.length]}];
        }
        return nil;
    }

    // Validate magic bytes
    CPAttachmentFileType fileType = [self detectFileTypeFromData:data];
    if (fileType == CPAttachmentFileTypeUnknown) {
        if (error) {
            *error = [NSError errorWithDomain:CPAttachmentErrorDomain
                                         code:CPAttachmentErrorInvalidType
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Unsupported file type. Allowed: PDF, JPEG, PNG."}];
        }
        return nil;
    }

    __block NSString *attachmentUUID = nil;
    __block NSError *opError = nil;

    // All file I/O on background queue
    dispatch_queue_t ioQueue = dispatch_queue_create("com.chargeprocure.attachment.io", DISPATCH_QUEUE_SERIAL);
    dispatch_sync(ioQueue, ^{
        NSError *dirError = nil;
        if (![self ensureAttachmentsDirectoryExists:&dirError]) {
            opError = dirError;
            return;
        }

        // Build file path: Attachments/<uuid>.<ext>
        NSString *uuid = [[NSUUID UUID] UUIDString];
        NSString *ext  = [self extensionForFileType:fileType];
        NSString *storedFilename = [NSString stringWithFormat:@"%@.%@", uuid, ext];
        NSString *filePath = [[self attachmentsDirectory] stringByAppendingPathComponent:storedFilename];

        NSError *writeError = nil;
        BOOL written = [data writeToFile:filePath options:NSDataWritingAtomic error:&writeError];
        if (!written) {
            opError = writeError ?: [NSError errorWithDomain:CPAttachmentErrorDomain
                                                        code:CPAttachmentErrorSaveFailed
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to write attachment file."}];
            return;
        }

        // Create Core Data record
        NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
        __block NSError *saveError = nil;

        [context performBlockAndWait:^{
            NSManagedObject *attachment = [NSEntityDescription insertNewObjectForEntityForName:@"Attachment"
                                                                       inManagedObjectContext:context];
            [attachment setValue:uuid                                  forKey:@"uuid"];
            [attachment setValue:ownerID                               forKey:@"ownerID"];
            [attachment setValue:ownerType                             forKey:@"ownerType"];
            [attachment setValue:filename                              forKey:@"filename"];
            [attachment setValue:[self mimeTypeForFileType:fileType]   forKey:@"mimeType"];
            [attachment setValue:filePath                              forKey:@"filePath"];
            [attachment setValue:@(data.length)                        forKey:@"fileSize"];
            [attachment setValue:[NSDate date]                         forKey:@"uploadedAt"];
            [attachment setValue:[self extensionForFileType:fileType]  forKey:@"fileType"];

            if (![context save:&saveError]) {
                // Rollback: delete the file we just wrote
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                opError = saveError;
            } else {
                attachmentUUID = uuid;
            }
        }];
    });

    if (opError) {
        if (error) {
            *error = opError;
        }
        return nil;
    }

    return attachmentUUID;
}

#pragma mark - Load Attachment

- (nullable NSData *)loadAttachmentWithUUID:(NSString *)attachmentUUID error:(NSError **)error {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
    request.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", attachmentUUID];
    request.fetchLimit = 1;

    NSError *fetchError = nil;
    NSArray *results = [context executeFetchRequest:request error:&fetchError];
    NSManagedObject *attachment = results.firstObject;

    if (!attachment) {
        if (error) {
            *error = [NSError errorWithDomain:CPAttachmentErrorDomain
                                         code:CPAttachmentErrorSaveFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Attachment '%@' not found.", attachmentUUID]}];
        }
        return nil;
    }

    NSString *filePath = [attachment valueForKey:@"filePath"];
    if (!filePath) {
        if (error) {
            *error = [NSError errorWithDomain:CPAttachmentErrorDomain
                                         code:CPAttachmentErrorSaveFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Attachment has no file path recorded."}];
        }
        return nil;
    }

    __block NSData *fileData = nil;
    __block NSError *readError = nil;

    dispatch_queue_t ioQueue = dispatch_queue_create("com.chargeprocure.attachment.io.read", DISPATCH_QUEUE_SERIAL);
    dispatch_sync(ioQueue, ^{
        fileData = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&readError];
    });

    if (readError && error) {
        *error = readError;
    }
    return fileData;
}

#pragma mark - Delete Attachment

- (BOOL)deleteAttachment:(NSString *)attachmentUUID error:(NSError **)error {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
    request.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", attachmentUUID];
    request.fetchLimit = 1;

    NSError *fetchError = nil;
    NSArray *results = [context executeFetchRequest:request error:&fetchError];
    NSManagedObject *attachment = results.firstObject;

    if (!attachment) {
        if (error) {
            *error = [NSError errorWithDomain:CPAttachmentErrorDomain
                                         code:CPAttachmentErrorSaveFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Attachment '%@' not found for deletion.", attachmentUUID]}];
        }
        return NO;
    }

    NSString *filePath = [attachment valueForKey:@"filePath"];

    __block BOOL success = NO;
    __block NSError *opError = nil;

    dispatch_queue_t ioQueue = dispatch_queue_create("com.chargeprocure.attachment.io.delete", DISPATCH_QUEUE_SERIAL);
    dispatch_sync(ioQueue, ^{
        // Delete file from disk
        if (filePath) {
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:filePath]) {
                NSError *removeError = nil;
                if (![fm removeItemAtPath:filePath error:&removeError]) {
                    opError = removeError;
                    return;
                }
            }
        }

        // Delete Core Data record
        [context performBlockAndWait:^{
            [context deleteObject:attachment];
            NSError *saveError = nil;
            if ([context save:&saveError]) {
                success = YES;
            } else {
                opError = saveError;
            }
        }];
    });

    if (!success && error) {
        *error = opError ?: [NSError errorWithDomain:CPAttachmentErrorDomain
                                                code:CPAttachmentErrorSaveFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to delete attachment."}];
    }
    return success;
}

#pragma mark - Weekly Cleanup

- (void)runWeeklyCleanup {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self performWeeklyCleanup];
    });
}

- (void)performWeeklyCleanup {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];

    [context performBlockAndWait:^{
        // --- 1. Delete Attachment records where file no longer exists (orphaned records) ---
        NSFetchRequest *attachRequest = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
        NSError *fetchError = nil;
        NSArray *allAttachments = [context executeFetchRequest:attachRequest error:&fetchError];

        for (NSManagedObject *attachment in allAttachments) {
            NSString *filePath = [attachment valueForKey:@"filePath"];
            if (!filePath || ![fm fileExistsAtPath:filePath]) {
                [context deleteObject:attachment];
                NSLog(@"[CPAttachmentService] Cleanup: removed orphaned Attachment record %@",
                      [attachment valueForKey:@"uuid"]);
            }
        }

        // --- 2. Delete unreferenced files in Attachments directory ---
        NSString *attachmentsDir = [self attachmentsDirectory];
        NSError *dirError = nil;
        NSArray *filesOnDisk = [fm contentsOfDirectoryAtPath:attachmentsDir error:&dirError];

        if (!dirError) {
            // Build set of known file paths from Core Data
            NSFetchRequest *pathRequest = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
            pathRequest.resultType = NSDictionaryResultType;
            pathRequest.propertiesToFetch = @[@"filePath"];
            NSArray *pathRows = [context executeFetchRequest:pathRequest error:nil];
            NSMutableSet *knownPaths = [NSMutableSet set];
            for (NSDictionary *row in pathRows) {
                NSString *fp = row[@"filePath"];
                if (fp) [knownPaths addObject:fp];
            }

            for (NSString *filename in filesOnDisk) {
                NSString *fullPath = [attachmentsDir stringByAppendingPathComponent:filename];
                if (![knownPaths containsObject:fullPath]) {
                    NSError *removeErr = nil;
                    [fm removeItemAtPath:fullPath error:&removeErr];
                    if (!removeErr) {
                        NSLog(@"[CPAttachmentService] Cleanup: removed unreferenced file %@", filename);
                    }
                }
            }
        }

        // --- 3. Delete draft Bulletins older than 90 days unless isPinned ---
        NSDate *cutoffDate = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay
                                                                       value:-90
                                                                      toDate:[NSDate date]
                                                                     options:0];
        NSFetchRequest *bulletinRequest = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        // statusValue == 0 (CPBulletinStatusDraft), created > 90 days ago, not pinned
        bulletinRequest.predicate = [NSPredicate predicateWithFormat:
            @"statusValue == %d AND createdAt < %@ AND isPinned == NO",
            0, cutoffDate];

        NSError *bulletinFetchError = nil;
        NSArray *staleDrafts = [context executeFetchRequest:bulletinRequest error:&bulletinFetchError];

        for (NSManagedObject *bulletin in staleDrafts) {
            NSLog(@"[CPAttachmentService] Cleanup: deleting stale draft Bulletin %@",
                  [bulletin valueForKey:@"uuid"]);
            [context deleteObject:bulletin];
        }

        // Save all deletions
        NSError *saveError = nil;
        if (![context save:&saveError]) {
            NSLog(@"[CPAttachmentService] Cleanup save error: %@", saveError.localizedDescription);
        }
    }];
}

#pragma mark - Fetch Attachments

- (NSArray *)fetchAttachmentsForOwnerID:(NSString *)ownerID ownerType:(NSString *)ownerType {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
    request.predicate = [NSPredicate predicateWithFormat:@"ownerID == %@ AND ownerType == %@",
                         ownerID, ownerType];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"uploadedAt" ascending:NO]];

    NSError *error = nil;
    NSArray *results = [context executeFetchRequest:request error:&error];
    return results ?: @[];
}

@end
