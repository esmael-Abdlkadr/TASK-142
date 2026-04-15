#import "CPReportExport+CoreDataClass.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPReportExport (CoreDataProperties)

+ (NSFetchRequest<CPReportExport *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *reportType;
@property (nullable, nonatomic, copy) NSString *parameters;
@property (nullable, nonatomic, copy) NSString *filePath;
@property (nullable, nonatomic, copy) NSString *fileFormat;
@property (nullable, nonatomic, copy) NSString *generatedByUserID;
@property (nullable, nonatomic, retain) NSNumber *fileSize;
@property (nullable, nonatomic, copy) NSDate *generatedAt;

@end

NS_ASSUME_NONNULL_END
