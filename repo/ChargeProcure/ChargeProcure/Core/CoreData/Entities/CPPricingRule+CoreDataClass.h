#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPPricingRule : NSManagedObject

+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

/// Parse tierJSON into an array of tier dictionaries.
/// Returns nil if tierJSON is absent or not valid JSON.
- (nullable NSArray<NSDictionary *> *)parsedTiers;

/// Serialise an array of tier dictionaries back into tierJSON.
- (void)setTiersFromArray:(NSArray<NSDictionary *> *)tiers;

/// Returns YES if this rule's effectiveStart <= date < effectiveEnd
/// (effectiveEnd == nil is treated as open-ended / no expiry).
- (BOOL)isActiveOnDate:(NSDate *)date;

/// Calculate the price for a given session duration (seconds) using tier pricing.
/// Falls back to basePrice when no matching tier is found.
- (NSDecimalNumber *)priceForDuration:(NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END

#import "CPPricingRule+CoreDataProperties.h"
