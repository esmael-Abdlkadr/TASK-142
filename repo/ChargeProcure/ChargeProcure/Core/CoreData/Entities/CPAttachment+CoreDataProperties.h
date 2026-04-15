#import "CPAttachment+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPInvoice, CPPayment;

NS_ASSUME_NONNULL_BEGIN

/// Forward declarations for optional polymorphic owner relationships.
@class CPReceipt, CPReturn, CPBulletin;

@interface CPAttachment (CoreDataProperties)
+ (NSFetchRequest<CPAttachment *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this attachment record.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Identifier of the owning entity (polymorphic, paired with ownerType).
@property (nullable, nonatomic, copy) NSString *ownerID;

/// Class/entity name of the owning entity (e.g. "Invoice", "Receipt").
@property (nullable, nonatomic, copy) NSString *ownerType;

/// Original filename including extension.
@property (nullable, nonatomic, copy) NSString *filename;

/// MIME type of the file (e.g. "application/pdf", "image/jpeg").
@property (nullable, nonatomic, copy) NSString *mimeType;

/// Relative or absolute path to the stored file on disk or in the bundle.
@property (nullable, nonatomic, copy) NSString *filePath;

/// Logical file type category (e.g. "Invoice", "Photo", "Contract").
@property (nullable, nonatomic, copy) NSString *fileType;

/// File size in bytes.
@property (nullable, nonatomic, strong) NSNumber *fileSize;

/// When the attachment was uploaded or saved.
@property (nullable, nonatomic, strong) NSDate *uploadedAt;

// MARK: - Optional polymorphic owner relationships

/// Invoice this attachment belongs to (optional).
@property (nullable, nonatomic, retain) CPInvoice *invoice;

/// Payment record this attachment belongs to (optional).
@property (nullable, nonatomic, retain) CPPayment *payment;

/// Receipt this attachment belongs to (optional).
@property (nullable, nonatomic, retain) CPReceipt *receipt;

/// Return record this attachment belongs to (optional).
@property (nullable, nonatomic, retain) CPReturn *returnRecord;

/// Bulletin this attachment belongs to (optional).
@property (nullable, nonatomic, retain) CPBulletin *bulletin;

@end

NS_ASSUME_NONNULL_END
