#import "CPPricingRule+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPVendor;

NS_ASSUME_NONNULL_BEGIN

@interface CPPricingRule (CoreDataProperties)
+ (NSFetchRequest<CPPricingRule *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this pricing rule.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Type of charging service this rule applies to (e.g. "Level2", "DCFC").
@property (nullable, nonatomic, copy) NSString *serviceType;

/// Vehicle class or category this rule targets (e.g. "Passenger", "Fleet").
@property (nullable, nonatomic, copy) NSString *vehicleClass;

/// Store or site identifier this rule is scoped to.
@property (nullable, nonatomic, copy) NSString *storeID;

/// JSON string encoding the pricing tier array.
@property (nullable, nonatomic, copy) NSString *tierJSON;

/// Free-text notes about the pricing rule.
@property (nullable, nonatomic, copy) NSString *notes;

/// Date from which this rule becomes effective.
@property (nullable, nonatomic, strong) NSDate *effectiveStart;

/// Date after which this rule is no longer effective (nil = open-ended).
@property (nullable, nonatomic, strong) NSDate *effectiveEnd;

/// When this rule record was created.
@property (nullable, nonatomic, strong) NSDate *createdAt;

/// Flat base price applied when no matching tier is found.
@property (nullable, nonatomic, strong) NSDecimalNumber *basePrice;

/// Whether the rule is currently active.
@property (nullable, nonatomic, strong) NSNumber *isActive;

/// Schema version number for the tier structure.
@property (nullable, nonatomic, strong) NSNumber *version;

// MARK: - Relationships

/// The vendor associated with this pricing rule.
@property (nullable, nonatomic, retain) CPVendor *vendor;

@end

NS_ASSUME_NONNULL_END
