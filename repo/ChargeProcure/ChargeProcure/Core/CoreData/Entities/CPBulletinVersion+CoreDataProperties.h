#import "CPBulletinVersion+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPBulletin;

NS_ASSUME_NONNULL_BEGIN

@interface CPBulletinVersion (CoreDataProperties)
+ (NSFetchRequest<CPBulletinVersion *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this version snapshot.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Identifier of the parent bulletin this version was snapshotted from.
@property (nullable, nonatomic, copy) NSString *bulletinID;

/// Monotonically increasing version number within the bulletin's history.
@property (nullable, nonatomic, strong) NSNumber *versionNumber;

/// Title of the bulletin at the time of snapshot.
@property (nullable, nonatomic, copy) NSString *title;

/// Summary/excerpt of the bulletin at the time of snapshot.
@property (nullable, nonatomic, copy) NSString *summary;

/// Markdown body content at the time of snapshot.
@property (nullable, nonatomic, copy) NSString *bodyMarkdown;

/// Rendered HTML body content at the time of snapshot.
@property (nullable, nonatomic, copy) NSString *bodyHTML;

/// File path of the cover image at the time of snapshot.
@property (nullable, nonatomic, copy) NSString *coverImagePath;

/// User ID of the person who triggered this version snapshot.
@property (nullable, nonatomic, copy) NSString *createdByUserID;

/// When this version snapshot was created.
@property (nullable, nonatomic, strong) NSDate *createdAt;

// MARK: - Relationships

/// The parent bulletin this version belongs to.
@property (nullable, nonatomic, retain) CPBulletin *bulletin;

@end

NS_ASSUME_NONNULL_END
