#import "CPReturn+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPProcurementCase;
@class CPAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface CPReturn (CoreDataProperties)

+ (NSFetchRequest<CPReturn *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *caseID;
@property (nullable, nonatomic, copy) NSString *receiptID;
@property (nullable, nonatomic, copy) NSString *returnNumber;
@property (nullable, nonatomic, copy) NSString *reason;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, copy) NSString *returnedByUserID;
@property (nullable, nonatomic, retain) NSDecimalNumber *amount;
@property (nullable, nonatomic, copy) NSDate *returnedAt;

@property (nullable, nonatomic, retain) CPProcurementCase *procurementCase;
@property (nullable, nonatomic, retain) NSSet<CPAttachment *> *attachments;

@end

@interface CPReturn (CoreDataGeneratedAccessors)

- (void)addAttachmentsObject:(CPAttachment *)value;
- (void)removeAttachmentsObject:(CPAttachment *)value;
- (void)addAttachments:(NSSet<CPAttachment *> *)values;
- (void)removeAttachments:(NSSet<CPAttachment *> *)values;

@end

NS_ASSUME_NONNULL_END
