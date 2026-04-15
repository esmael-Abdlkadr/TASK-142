#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/// Factory methods for test data creation
@interface CPTestDataFactory : NSObject

/// Create a test user with given username, password hash (sha256 of "Test1234Pass"+salt), role
+ (id)createUserWithUsername:(NSString *)username
                    roleNamed:(NSString *)roleName
                  inContext:(NSManagedObjectContext *)context;

/// Create a test charger with given status
+ (id)createChargerWithStatus:(NSString *)status
                    inContext:(NSManagedObjectContext *)context;

/// Create a test procurement case at given stage
+ (id)createProcurementCaseAtStage:(NSString *)stage
                          inContext:(NSManagedObjectContext *)context;

/// Create a test vendor
+ (id)createVendorWithName:(NSString *)name
                 inContext:(NSManagedObjectContext *)context;

/// Create a test bulletin with given status
+ (id)createBulletinWithStatus:(NSString *)status
                      inContext:(NSManagedObjectContext *)context;

/// Create a test invoice with given total amount
+ (id)createInvoiceWithTotal:(NSDecimalNumber *)total
                 forCaseUUID:(NSString *)caseUUID
                   inContext:(NSManagedObjectContext *)context;

/// Create a test pricing rule
+ (id)createPricingRuleWithServiceType:(NSString *)serviceType
                             basePrice:(NSDecimalNumber *)basePrice
                             inContext:(NSManagedObjectContext *)context;

@end

NS_ASSUME_NONNULL_END
