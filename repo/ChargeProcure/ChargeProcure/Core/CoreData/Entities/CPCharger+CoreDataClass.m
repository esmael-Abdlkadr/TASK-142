#import "CPCharger+CoreDataClass.h"
#import "CPCharger+CoreDataProperties.h"

// Status string constants matching OCPP / backend conventions
static NSString * const CPChargerStatusStringOffline  = @"Offline";
static NSString * const CPChargerStatusStringOnline   = @"Online";
static NSString * const CPChargerStatusStringCharging = @"Charging";
static NSString * const CPChargerStatusStringIdle     = @"Idle";
static NSString * const CPChargerStatusStringFault    = @"Fault";

@implementation CPCharger

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPCharger *charger = [NSEntityDescription insertNewObjectForEntityForName:@"Charger"
                                                       inManagedObjectContext:context];
    charger.uuid = [[NSUUID UUID] UUIDString];
    charger.status = CPChargerStatusStringOffline;
    charger.lastSeenAt = [NSDate date];
    return charger;
}

#pragma mark - Status Parsing

- (CPChargerStatus)chargerStatus {
    NSString *rawStatus = self.status;
    if (!rawStatus || rawStatus.length == 0) {
        return CPChargerStatusUnknown;
    }

    // Case-insensitive comparison for robustness
    NSString *trimmed = [rawStatus stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([trimmed caseInsensitiveCompare:CPChargerStatusStringOffline] == NSOrderedSame) {
        return CPChargerStatusOffline;
    } else if ([trimmed caseInsensitiveCompare:CPChargerStatusStringOnline] == NSOrderedSame) {
        return CPChargerStatusOnline;
    } else if ([trimmed caseInsensitiveCompare:CPChargerStatusStringCharging] == NSOrderedSame) {
        return CPChargerStatusCharging;
    } else if ([trimmed caseInsensitiveCompare:CPChargerStatusStringIdle] == NSOrderedSame) {
        return CPChargerStatusIdle;
    } else if ([trimmed caseInsensitiveCompare:CPChargerStatusStringFault] == NSOrderedSame) {
        return CPChargerStatusFault;
    }

    return CPChargerStatusUnknown;
}

#pragma mark - Parameters JSON Encoding / Decoding

- (NSDictionary *)parsedParameters {
    NSString *json = self.parameters;
    if (!json || json.length == 0) {
        return @{};
    }

    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        NSLog(@"[CPCharger] parsedParameters: failed to encode parameters string to data.");
        return @{};
    }

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![parsed isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[CPCharger] parsedParameters: JSON parse error: %@", error.localizedDescription);
        return @{};
    }

    return (NSDictionary *)parsed;
}

- (void)setParametersFromDictionary:(NSDictionary *)dict {
    if (!dict || dict.count == 0) {
        self.parameters = nil;
        return;
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict
                                                   options:NSJSONWritingSortedKeys
                                                     error:&error];
    if (error || !data) {
        NSLog(@"[CPCharger] setParametersFromDictionary: JSON serialization error: %@", error.localizedDescription);
        return;
    }

    self.parameters = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
