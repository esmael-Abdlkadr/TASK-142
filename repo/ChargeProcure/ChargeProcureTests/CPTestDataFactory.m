#import "CPTestDataFactory.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation CPTestDataFactory

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// SHA-256( salt + password ) returned as lowercase hex string.
+ (NSString *)hashPassword:(NSString *)password withSalt:(NSString *)salt {
    NSString *combined = [salt stringByAppendingString:password];
    NSData *data = [combined dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex copy];
}

/// Fetch-or-create a Role entity by name.
+ (NSManagedObject *)roleNamed:(NSString *)roleName
                     inContext:(NSManagedObjectContext *)context {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Role"];
    req.predicate = [NSPredicate predicateWithFormat:@"name == %@", roleName];
    req.fetchLimit = 1;
    NSError *err = nil;
    NSArray *results = [context executeFetchRequest:req error:&err];
    if (results.firstObject) {
        return results.firstObject;
    }
    NSManagedObject *role = [NSEntityDescription insertNewObjectForEntityForName:@"Role"
                                                          inManagedObjectContext:context];
    [role setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [role setValue:roleName                   forKey:@"name"];
    [role setValue:[NSDate date]              forKey:@"createdAt"];
    return role;
}

// ---------------------------------------------------------------------------
// User
// ---------------------------------------------------------------------------

+ (id)createUserWithUsername:(NSString *)username
                    roleNamed:(NSString *)roleName
                  inContext:(NSManagedObjectContext *)context {
    NSManagedObject *role = [self roleNamed:roleName inContext:context];

    NSString *salt = @"testSalt0123456789abcdef";
    NSString *hash = [self hashPassword:@"Test1234Pass" withSalt:salt];

    NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                          inManagedObjectContext:context];
    [user setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [user setValue:username                   forKey:@"username"];
    [user setValue:hash                       forKey:@"passwordHash"];
    [user setValue:salt                       forKey:@"salt"];
    [user setValue:@(0)                       forKey:@"failedAttempts"];
    [user setValue:@(YES)                     forKey:@"isActive"];
    [user setValue:@(NO)                      forKey:@"biometricEnabled"];
    [user setValue:[NSDate date]              forKey:@"createdAt"];
    [user setValue:role                       forKey:@"role"];

    NSError *err = nil;
    [context save:&err];
    return user;
}

// ---------------------------------------------------------------------------
// Charger
// ---------------------------------------------------------------------------

+ (id)createChargerWithStatus:(NSString *)status
                    inContext:(NSManagedObjectContext *)context {
    NSManagedObject *charger = [NSEntityDescription insertNewObjectForEntityForName:@"Charger"
                                                              inManagedObjectContext:context];
    [charger setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [charger setValue:status                     forKey:@"status"];
    [charger setValue:@"SN-TEST-001"             forKey:@"serialNumber"];
    [charger setValue:@"TestModel"               forKey:@"model"];
    [charger setValue:@"Site A"                  forKey:@"location"];
    [charger setValue:[NSDate date]              forKey:@"lastSeenAt"];

    NSError *err = nil;
    [context save:&err];
    return charger;
}

// ---------------------------------------------------------------------------
// ProcurementCase
// ---------------------------------------------------------------------------

+ (id)createProcurementCaseAtStage:(NSString *)stage
                          inContext:(NSManagedObjectContext *)context {
    // Map stage name to integer value matching CPProcurementStage enum
    NSDictionary *stageMap = @{
        @"Draft":          @(0),
        @"Requisition":    @(1),
        @"RFQ":            @(2),
        @"PurchaseOrder":  @(3),
        @"Receipt":        @(4),
        @"Invoice":        @(5),
        @"Reconciliation": @(6),
        @"Payment":        @(7),
        @"Closed":         @(8),
    };
    NSNumber *stageValue = stageMap[stage] ?: @(0);

    NSManagedObject *procCase = [NSEntityDescription insertNewObjectForEntityForName:@"ProcurementCase"
                                                               inManagedObjectContext:context];
    [procCase setValue:[[NSUUID UUID] UUIDString]          forKey:@"uuid"];
    [procCase setValue:@"Test Procurement Case"             forKey:@"title"];
    [procCase setValue:@"Test description"                  forKey:@"caseDescription"];
    [procCase setValue:stageValue                           forKey:@"stageValue"];
    [procCase setValue:[NSDecimalNumber decimalNumberWithString:@"1000.00"]
                                                           forKey:@"estimatedAmount"];
    [procCase setValue:@"USD"                              forKey:@"currencyCode"];
    [procCase setValue:[NSString stringWithFormat:@"PC-TEST-%@", [[NSUUID UUID].UUIDString substringToIndex:8]]
                                                           forKey:@"caseNumber"];
    [procCase setValue:[NSDate date]                       forKey:@"createdAt"];
    [procCase setValue:[NSDate date]                       forKey:@"updatedAt"];

    NSError *err = nil;
    [context save:&err];
    return procCase;
}

// ---------------------------------------------------------------------------
// Vendor
// ---------------------------------------------------------------------------

+ (id)createVendorWithName:(NSString *)name
                 inContext:(NSManagedObjectContext *)context {
    NSManagedObject *vendor = [NSEntityDescription insertNewObjectForEntityForName:@"Vendor"
                                                             inManagedObjectContext:context];
    [vendor setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [vendor setValue:name                       forKey:@"name"];
    [vendor setValue:@"test@vendor.example.com" forKey:@"contactEmail"];
    [vendor setValue:@(YES)                     forKey:@"isActive"];
    [vendor setValue:[NSDate date]              forKey:@"createdAt"];

    NSError *err = nil;
    [context save:&err];
    return vendor;
}

// ---------------------------------------------------------------------------
// Bulletin
// ---------------------------------------------------------------------------

+ (id)createBulletinWithStatus:(NSString *)status
                      inContext:(NSManagedObjectContext *)context {
    // Map status string to integer (CPBulletinStatus: 0=Draft, 1=Published, 2=Scheduled, 3=Archived)
    NSDictionary *statusMap = @{
        @"Draft":     @(0),
        @"Published": @(1),
        @"Scheduled": @(2),
        @"Archived":  @(3),
    };
    NSNumber *statusValue = statusMap[status] ?: @(0);

    NSManagedObject *bulletin = [NSEntityDescription insertNewObjectForEntityForName:@"Bulletin"
                                                               inManagedObjectContext:context];
    [bulletin setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [bulletin setValue:@"Test Bulletin Title"     forKey:@"title"];
    [bulletin setValue:@"Test bulletin body."     forKey:@"body"];
    [bulletin setValue:statusValue                forKey:@"statusValue"];
    [bulletin setValue:@(0)                       forKey:@"editorModeValue"];
    [bulletin setValue:@(NO)                      forKey:@"isPinned"];
    [bulletin setValue:[NSDate date]              forKey:@"createdAt"];
    [bulletin setValue:[NSDate date]              forKey:@"updatedAt"];

    NSError *err = nil;
    [context save:&err];
    return bulletin;
}

// ---------------------------------------------------------------------------
// Invoice
// ---------------------------------------------------------------------------

+ (id)createInvoiceWithTotal:(NSDecimalNumber *)total
                 forCaseUUID:(NSString *)caseUUID
                   inContext:(NSManagedObjectContext *)context {
    NSManagedObject *invoice = [NSEntityDescription insertNewObjectForEntityForName:@"Invoice"
                                                              inManagedObjectContext:context];
    [invoice setValue:[[NSUUID UUID] UUIDString]                  forKey:@"uuid"];
    [invoice setValue:caseUUID                                     forKey:@"caseID"];
    [invoice setValue:[NSString stringWithFormat:@"INV-%@", [[NSUUID UUID].UUIDString substringToIndex:8]]
                                                                   forKey:@"invoiceNumber"];
    [invoice setValue:[NSString stringWithFormat:@"VND-%@", [[NSUUID UUID].UUIDString substringToIndex:8]]
                                                                   forKey:@"vendorInvoiceNumber"];
    [invoice setValue:total                                        forKey:@"totalAmount"];
    [invoice setValue:[NSDecimalNumber zero]                       forKey:@"taxAmount"];
    [invoice setValue:[NSDecimalNumber zero]                       forKey:@"varianceAmount"];
    [invoice setValue:[NSDecimalNumber zero]                       forKey:@"variancePercentage"];
    [invoice setValue:[NSDecimalNumber zero]                       forKey:@"writeOffAmount"];
    [invoice setValue:@"Pending"                                   forKey:@"status"];
    [invoice setValue:@(NO)                                        forKey:@"varianceFlag"];
    [invoice setValue:[NSDate date]                                forKey:@"invoicedAt"];
    [invoice setValue:[NSDate dateWithTimeIntervalSinceNow:30 * 86400]
                                                                   forKey:@"dueDate"];

    NSError *err = nil;
    [context save:&err];
    return invoice;
}

// ---------------------------------------------------------------------------
// PricingRule
// ---------------------------------------------------------------------------

+ (id)createPricingRuleWithServiceType:(NSString *)serviceType
                             basePrice:(NSDecimalNumber *)basePrice
                             inContext:(NSManagedObjectContext *)context {
    NSManagedObject *rule = [NSEntityDescription insertNewObjectForEntityForName:@"PricingRule"
                                                           inManagedObjectContext:context];
    [rule setValue:[[NSUUID UUID] UUIDString]              forKey:@"uuid"];
    [rule setValue:serviceType                              forKey:@"serviceType"];
    [rule setValue:basePrice                               forKey:@"basePrice"];
    [rule setValue:@(1)                                    forKey:@"version"];
    [rule setValue:@(YES)                                  forKey:@"isActive"];
    [rule setValue:[NSDate dateWithTimeIntervalSinceNow:-3600] forKey:@"effectiveStart"]; // 1 hr ago
    [rule setValue:nil                                     forKey:@"effectiveEnd"];       // open-ended
    [rule setValue:[NSDate date]                           forKey:@"createdAt"];

    NSError *err = nil;
    [context save:&err];
    return rule;
}

@end
