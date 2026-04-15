#import "CPPricingRule+CoreDataClass.h"
#import "CPPricingRule+CoreDataProperties.h"

@implementation CPPricingRule

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPPricingRule *rule = [NSEntityDescription insertNewObjectForEntityForName:@"PricingRule"
                                                        inManagedObjectContext:context];
    rule.uuid      = [[NSUUID UUID] UUIDString];
    rule.createdAt = [NSDate date];
    rule.isActive  = @YES;
    rule.version   = @(1);
    rule.basePrice = [NSDecimalNumber zero];
    return rule;
}

#pragma mark - Tier JSON

- (nullable NSArray<NSDictionary *> *)parsedTiers {
    if (self.tierJSON.length == 0) {
        return nil;
    }
    NSData *data = [self.tierJSON dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) { return nil; }

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![parsed isKindOfClass:[NSArray class]]) {
        return nil;
    }
    return (NSArray<NSDictionary *> *)parsed;
}

- (void)setTiersFromArray:(NSArray<NSDictionary *> *)tiers {
    NSParameterAssert(tiers);
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:tiers options:0 error:&error];
    if (!error && data) {
        self.tierJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
}

#pragma mark - Date Range

- (BOOL)isActiveOnDate:(NSDate *)date {
    NSParameterAssert(date);
    if (!self.isActive.boolValue) {
        return NO;
    }
    // effectiveStart must be <= date
    if (self.effectiveStart && [self.effectiveStart compare:date] == NSOrderedDescending) {
        return NO;
    }
    // effectiveEnd (if set) must be > date
    if (self.effectiveEnd && [self.effectiveEnd compare:date] != NSOrderedDescending) {
        return NO;
    }
    return YES;
}

#pragma mark - Price Calculation

- (NSDecimalNumber *)priceForDuration:(NSTimeInterval)duration {
    // Tiers are expected as array of dicts with "minSeconds", "maxSeconds", "price" keys.
    // The first tier whose [minSeconds, maxSeconds) range contains duration is used.
    NSArray<NSDictionary *> *tiers = [self parsedTiers];
    if (tiers.count > 0) {
        for (NSDictionary *tier in tiers) {
            NSNumber *minSec = tier[@"minSeconds"];
            NSNumber *maxSec = tier[@"maxSeconds"]; // nil means open-ended upper bound
            NSNumber *price  = tier[@"price"];

            if (!minSec || !price) { continue; }

            BOOL aboveMin = (duration >= minSec.doubleValue);
            BOOL belowMax = (maxSec == nil) || (duration < maxSec.doubleValue);

            if (aboveMin && belowMax) {
                NSString *priceStr = [price isKindOfClass:[NSString class]]
                                        ? (NSString *)price
                                        : [price stringValue];
                NSDecimalNumber *result = [NSDecimalNumber decimalNumberWithString:priceStr];
                if (![result isEqual:[NSDecimalNumber notANumber]]) {
                    return result;
                }
            }
        }
    }

    // Fall back to basePrice
    return self.basePrice ?: [NSDecimalNumber zero];
}

@end
