#import "CPBulletin+CoreDataClass.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPBulletin (CoreDataProperties)
+ (NSFetchRequest<CPBulletin *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy)   NSString *uuid;
@property (nullable, nonatomic, copy)   NSString *title;
@property (nullable, nonatomic, copy)   NSString *summary;
@property (nullable, nonatomic, copy)   NSString *body;
@property (nullable, nonatomic, copy)   NSString *bodyHTML;
@property (nullable, nonatomic, strong) NSNumber *statusValue;
@property (nullable, nonatomic, strong) NSNumber *editorModeValue;
@property (nullable, nonatomic, strong) NSNumber *isPinned;
@property (nullable, nonatomic, strong) NSNumber *recommendationWeight;
@property (nullable, nonatomic, copy)   NSString *coverImagePath;
@property (nullable, nonatomic, strong) NSDate   *publishDate;
@property (nullable, nonatomic, strong) NSDate   *unpublishDate;
@property (nullable, nonatomic, strong) NSDate   *createdAt;
@property (nullable, nonatomic, strong) NSDate   *updatedAt;
@property (nullable, nonatomic, copy)   NSString *authorID;
@property (nullable, nonatomic, copy)   NSString *currentVersionID;
@property (nullable, nonatomic, copy)   NSString *tags;
@property (nullable, nonatomic, copy)   NSString *externalURL;

@end

NS_ASSUME_NONNULL_END
