#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPAttachmentErrorDomain;
FOUNDATION_EXPORT NSInteger const CPAttachmentMaxSizeBytes;  // 25 * 1024 * 1024

typedef NS_ENUM(NSInteger, CPAttachmentError) {
    CPAttachmentErrorFileTooLarge = 4001,
    CPAttachmentErrorInvalidType  = 4002,
    CPAttachmentErrorSaveFailed   = 4003,
};

typedef NS_ENUM(NSInteger, CPAttachmentFileType) {
    CPAttachmentFileTypePDF,
    CPAttachmentFileTypeJPEG,
    CPAttachmentFileTypePNG,
    CPAttachmentFileTypeUnknown,
};

@interface CPAttachmentService : NSObject

+ (instancetype)sharedService;

/// Save attachment data, validate magic headers (PDF: %PDF, JPEG: FFD8FF, PNG: 89504E47).
/// ownerType: "Receipt" | "Return" | "Invoice" | "Payment" | "Bulletin"
- (nullable NSString *)saveAttachmentData:(NSData *)data
                                 filename:(NSString *)filename
                                  ownerID:(NSString *)ownerID
                                ownerType:(NSString *)ownerType
                                    error:(NSError **)error;

/// Load attachment data from sandbox.
- (nullable NSData *)loadAttachmentWithUUID:(NSString *)attachmentUUID error:(NSError **)error;

/// Delete attachment file and Core Data record.
- (BOOL)deleteAttachment:(NSString *)attachmentUUID error:(NSError **)error;

/// Run cleanup: delete unreferenced files and drafts older than 90 days (unless pinned).
- (void)runWeeklyCleanup;

/// Detect file type from magic bytes.
- (CPAttachmentFileType)detectFileTypeFromData:(NSData *)data;

/// Fetch all attachments for owner.
- (NSArray *)fetchAttachmentsForOwnerID:(NSString *)ownerID ownerType:(NSString *)ownerType;

@end

NS_ASSUME_NONNULL_END
