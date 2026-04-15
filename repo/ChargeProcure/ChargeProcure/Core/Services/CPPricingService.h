#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPPricingService : NSObject

+ (instancetype)sharedService;

/// Find the best active pricing rule for given parameters (highest specificity match).
/// vehicleClass, storeID, date are matched against PricingRule attributes.
- (nullable id)activePricingRuleForServiceType:(NSString *)serviceType
                                   vehicleClass:(nullable NSString *)vehicleClass
                                        storeID:(nullable NSString *)storeID
                                           date:(nullable NSDate *)date;

/// Calculate price including tiered pricing.
/// Returns NSDecimalNumber with final calculated price.
- (NSDecimalNumber *)calculatePriceForServiceType:(NSString *)serviceType
                                      vehicleClass:(nullable NSString *)vehicleClass
                                           storeID:(nullable NSString *)storeID
                                              date:(nullable NSDate *)date
                                          duration:(NSTimeInterval)duration
                                             error:(NSError **)error;

/// Create a new pricing rule version. Automatically sets effectiveStart.
- (nullable NSString *)createPricingRuleWithServiceType:(NSString *)serviceType
                                            vehicleClass:(nullable NSString *)vehicleClass
                                                 storeID:(nullable NSString *)storeID
                                         effectiveStart:(NSDate *)start
                                           effectiveEnd:(nullable NSDate *)end
                                              basePrice:(NSDecimalNumber *)basePrice
                                               tierJSON:(nullable NSString *)tierJSON
                                                  notes:(nullable NSString *)notes
                                                  error:(NSError **)error;

/// Deprecate a pricing rule (sets effectiveEnd to now).
- (BOOL)deprecatePricingRule:(NSString *)ruleUUID error:(NSError **)error;

/// Fetch all active pricing rules, sorted by serviceType then version descending.
- (NSArray *)fetchActivePricingRules;

/// Fetch version history for a service type.
- (NSArray *)fetchPricingRuleHistoryForServiceType:(NSString *)serviceType;

@end

NS_ASSUME_NONNULL_END
