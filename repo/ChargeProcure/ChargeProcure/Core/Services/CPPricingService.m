#import "CPPricingService.h"
#import "CPCoreDataStack.h"
#import "CPAuthService.h"
#import "CPIDGenerator.h"
#import <CoreData/CoreData.h>

// Error domain for pricing service
static NSString * const CPPricingErrorDomain = @"com.chargeprocure.pricing";

typedef NS_ENUM(NSInteger, CPPricingError) {
    CPPricingErrorNoRuleFound      = 5001,
    CPPricingErrorInvalidTierJSON  = 5002,
    CPPricingErrorSaveFailed       = 5003,
    CPPricingErrorRuleNotFound     = 5004,
};

@implementation CPPricingService

+ (instancetype)sharedService {
    static CPPricingService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPPricingService alloc] init];
    });
    return instance;
}

#pragma mark - Active Rule Lookup

- (nullable id)activePricingRuleForServiceType:(NSString *)serviceType
                                   vehicleClass:(nullable NSString *)vehicleClass
                                        storeID:(nullable NSString *)storeID
                                           date:(nullable NSDate *)date {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];

    NSDate *queryDate = date ?: [NSDate date];

    // Fetch rules matching serviceType, currently active (isActive == YES),
    // and where effectiveStart <= queryDate and (effectiveEnd == nil OR effectiveEnd >= queryDate)
    NSPredicate *predicate = [NSPredicate predicateWithFormat:
        @"serviceType == %@ AND isActive == YES AND effectiveStart <= %@ AND (effectiveEnd == nil OR effectiveEnd >= %@)",
        serviceType, queryDate, queryDate];
    request.predicate = predicate;
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO]];

    NSError *fetchError = nil;
    NSArray *rules = [context executeFetchRequest:request error:&fetchError];
    if (!rules || rules.count == 0) {
        return nil;
    }

    // Score each candidate rule by specificity
    NSManagedObject *bestRule = nil;
    NSInteger bestScore = -1;

    for (NSManagedObject *rule in rules) {
        NSInteger score = 0;

        // vehicleClass match: +10
        NSString *ruleVehicleClass = [rule valueForKey:@"vehicleClass"];
        if (vehicleClass && ruleVehicleClass && [ruleVehicleClass isEqualToString:vehicleClass]) {
            score += 10;
        } else if (!vehicleClass && (!ruleVehicleClass || ruleVehicleClass.length == 0)) {
            // Both nil/empty: neutral, no bonus but not penalized
        } else if (vehicleClass && (!ruleVehicleClass || ruleVehicleClass.length == 0)) {
            // Rule is more generic, lower specificity: no bonus
        } else if (!vehicleClass && ruleVehicleClass && ruleVehicleClass.length > 0) {
            // Rule requires specific vehicle class but we have none: skip scoring bonus
        }

        // storeID match: +5
        NSString *ruleStoreID = [rule valueForKey:@"storeID"];
        if (storeID && ruleStoreID && [ruleStoreID isEqualToString:storeID]) {
            score += 5;
        }

        // Date range match exactness: +3 if both effectiveStart and effectiveEnd tightly bracket the date
        NSDate *effStart = [rule valueForKey:@"effectiveStart"];
        NSDate *effEnd   = [rule valueForKey:@"effectiveEnd"];
        if (effStart && effEnd) {
            // Has both bounds — more specific than open-ended
            score += 3;
        }

        if (score > bestScore) {
            bestScore = score;
            bestRule = rule;
        }
    }

    return bestRule;
}

#pragma mark - Price Calculation

- (NSDecimalNumber *)calculatePriceForServiceType:(NSString *)serviceType
                                      vehicleClass:(nullable NSString *)vehicleClass
                                           storeID:(nullable NSString *)storeID
                                              date:(nullable NSDate *)date
                                          duration:(NSTimeInterval)duration
                                             error:(NSError **)error {
    NSManagedObject *rule = [self activePricingRuleForServiceType:serviceType
                                                      vehicleClass:vehicleClass
                                                           storeID:storeID
                                                              date:date];
    if (!rule) {
        if (error) {
            *error = [NSError errorWithDomain:CPPricingErrorDomain
                                         code:CPPricingErrorNoRuleFound
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"No active pricing rule found for service type '%@'.", serviceType]}];
        }
        return [NSDecimalNumber notANumber];
    }

    NSString *tierJSON = [rule valueForKey:@"tierJSON"];
    NSDecimalNumber *basePrice = [rule valueForKey:@"basePrice"] ?: [NSDecimalNumber zero];

    // If no tier JSON, return base price
    if (!tierJSON || tierJSON.length == 0) {
        return basePrice;
    }

    // Parse tier JSON
    NSData *jsonData = [tierJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    NSArray *tiers = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    if (jsonError || ![tiers isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:CPPricingErrorDomain
                                         code:CPPricingErrorInvalidTierJSON
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid tier JSON in pricing rule."}];
        }
        return [NSDecimalNumber notANumber];
    }

    // Find matching tier: find first tier where duration <= maxDuration
    // Tiers are sorted by maxDuration ascending; null maxDuration means "unlimited" (last tier)
    NSDecimalNumber *tierPrice = nil;
    for (NSDictionary *tier in tiers) {
        id maxDurationVal = tier[@"maxDuration"];
        NSNumber *price   = tier[@"price"];

        if (!price) {
            continue;
        }

        if (maxDurationVal == nil || [maxDurationVal isKindOfClass:[NSNull class]]) {
            // Unlimited/catch-all tier
            tierPrice = [NSDecimalNumber decimalNumberWithDecimal:[price decimalValue]];
            break;
        }

        NSTimeInterval maxDuration = [maxDurationVal doubleValue];
        if (duration <= maxDuration) {
            tierPrice = [NSDecimalNumber decimalNumberWithDecimal:[price decimalValue]];
            break;
        }
    }

    if (tierPrice) {
        return tierPrice;
    }

    // Fallback to base price if no tier matched
    return basePrice;
}

#pragma mark - Rule Creation

- (nullable NSString *)createPricingRuleWithServiceType:(NSString *)serviceType
                                            vehicleClass:(nullable NSString *)vehicleClass
                                                 storeID:(nullable NSString *)storeID
                                         effectiveStart:(NSDate *)start
                                           effectiveEnd:(nullable NSDate *)end
                                              basePrice:(NSDecimalNumber *)basePrice
                                               tierJSON:(nullable NSString *)tierJSON
                                                  notes:(nullable NSString *)notes
                                                  error:(NSError **)error {
    // Validate tier JSON if provided
    if (tierJSON && tierJSON.length > 0) {
        NSData *jsonData = [tierJSON dataUsingEncoding:NSUTF8StringEncoding];
        NSError *jsonError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
        if (jsonError || ![parsed isKindOfClass:[NSArray class]]) {
            if (error) {
                *error = [NSError errorWithDomain:CPPricingErrorDomain
                                             code:CPPricingErrorInvalidTierJSON
                                         userInfo:@{NSLocalizedDescriptionKey: @"tierJSON must be a valid JSON array."}];
            }
            return nil;
        }
    }

    __block NSString *newUUID = nil;
    __block NSError *saveError = nil;
    __block NSInteger nextVersion = 1;

    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;

    [context performBlockAndWait:^{
        // Determine next version number for this serviceType
        NSFetchRequest *versionReq = [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];
        versionReq.predicate = [NSPredicate predicateWithFormat:@"serviceType == %@", serviceType];
        versionReq.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO]];
        versionReq.fetchLimit = 1;

        NSError *fetchErr = nil;
        NSArray *existing = [context executeFetchRequest:versionReq error:&fetchErr];
        nextVersion = 1;
        if (existing.count > 0) {
            NSNumber *maxVersion = [existing.firstObject valueForKey:@"version"];
            nextVersion = maxVersion.integerValue + 1;
        }

        // Create new PricingRule entity
        NSManagedObject *rule = [NSEntityDescription insertNewObjectForEntityForName:@"PricingRule"
                                                              inManagedObjectContext:context];
        newUUID = [[NSUUID UUID] UUIDString];
        [rule setValue:newUUID          forKey:@"uuid"];
        [rule setValue:serviceType      forKey:@"serviceType"];
        [rule setValue:vehicleClass     forKey:@"vehicleClass"];
        [rule setValue:storeID          forKey:@"storeID"];
        [rule setValue:start            forKey:@"effectiveStart"];
        [rule setValue:end              forKey:@"effectiveEnd"];
        [rule setValue:basePrice        forKey:@"basePrice"];
        [rule setValue:tierJSON         forKey:@"tierJSON"];
        [rule setValue:notes            forKey:@"notes"];
        [rule setValue:@(nextVersion)   forKey:@"version"];
        [rule setValue:@YES             forKey:@"isActive"];
        [rule setValue:[NSDate date]    forKey:@"createdAt"];

        if (![context save:&saveError]) {
            newUUID = nil;
        }
    }];

    if (saveError) {
        if (error) {
            *error = [NSError errorWithDomain:CPPricingErrorDomain
                                         code:CPPricingErrorSaveFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to save pricing rule.",
                                                NSUnderlyingErrorKey: saveError}];
        }
        return nil;
    }

    // Audit log
    [self logAuditAction:@"CREATE_PRICING_RULE"
              resourceID:newUUID
                  detail:[NSString stringWithFormat:@"Created pricing rule for serviceType=%@ version=%@",
                          serviceType, @(nextVersion)]];

    return newUUID;
}

#pragma mark - Rule Deprecation

- (BOOL)deprecatePricingRule:(NSString *)ruleUUID error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *opError = nil;

    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;

    [context performBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];
        request.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", ruleUUID];
        request.fetchLimit = 1;

        NSError *fetchErr = nil;
        NSArray *results = [context executeFetchRequest:request error:&fetchErr];
        if (fetchErr || results.count == 0) {
            opError = [NSError errorWithDomain:CPPricingErrorDomain
                                          code:CPPricingErrorRuleNotFound
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Pricing rule '%@' not found.", ruleUUID]}];
            return;
        }

        NSManagedObject *rule = results.firstObject;
        [rule setValue:[NSDate date] forKey:@"effectiveEnd"];
        [rule setValue:@NO           forKey:@"isActive"];

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            success = YES;
        } else {
            opError = saveErr;
        }
    }];

    if (!success && error) {
        *error = opError ?: [NSError errorWithDomain:CPPricingErrorDomain
                                                code:CPPricingErrorSaveFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to deprecate pricing rule."}];
    }

    if (success) {
        [self logAuditAction:@"DEPRECATE_PRICING_RULE"
                  resourceID:ruleUUID
                      detail:@"Pricing rule deprecated (effectiveEnd set to now)"];
    }

    return success;
}

#pragma mark - Fetch Active Rules

- (NSArray *)fetchActivePricingRules {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];

    NSDate *now = [NSDate date];
    request.predicate = [NSPredicate predicateWithFormat:
        @"isActive == YES AND effectiveStart <= %@ AND (effectiveEnd == nil OR effectiveEnd >= %@)",
        now, now];
    request.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"serviceType" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO],
    ];

    NSError *error = nil;
    NSArray *results = [context executeFetchRequest:request error:&error];
    return results ?: @[];
}

#pragma mark - Fetch History

- (NSArray *)fetchPricingRuleHistoryForServiceType:(NSString *)serviceType {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];
    request.predicate = [NSPredicate predicateWithFormat:@"serviceType == %@", serviceType];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO]];

    NSError *error = nil;
    NSArray *results = [context executeFetchRequest:request error:&error];
    return results ?: @[];
}

#pragma mark - Audit Logging

- (void)logAuditAction:(NSString *)action
            resourceID:(NSString *)resourceID
                detail:(NSString *)detail {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;

    [context performBlock:^{
        NSManagedObject *event = [NSEntityDescription insertNewObjectForEntityForName:@"AuditEvent"
                                                               inManagedObjectContext:context];
        [event setValue:[[NSUUID UUID] UUIDString]           forKey:@"uuid"];
        [event setValue:action                               forKey:@"action"];
        [event setValue:@"PricingRule"                       forKey:@"resource"];
        [event setValue:resourceID                           forKey:@"resourceID"];
        [event setValue:detail                               forKey:@"detail"];
        [event setValue:[NSDate date]                        forKey:@"occurredAt"];
        [event setValue:[CPAuthService sharedService].currentUserID       forKey:@"actorID"];
        [event setValue:[CPAuthService sharedService].currentUsername     forKey:@"actorUsername"];

        NSError *err = nil;
        [context save:&err];
        if (err) {
            NSLog(@"[CPPricingService] Audit log save error: %@", err.localizedDescription);
        }
    }];
}

@end
