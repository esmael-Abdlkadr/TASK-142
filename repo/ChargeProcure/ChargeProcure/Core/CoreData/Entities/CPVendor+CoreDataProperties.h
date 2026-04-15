#import "CPVendor+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPProcurementCase, CPPricingRule;

NS_ASSUME_NONNULL_BEGIN

@interface CPVendor (CoreDataProperties)
+ (NSFetchRequest<CPVendor *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this vendor record.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Display name of the vendor/supplier.
@property (nullable, nonatomic, copy) NSString *name;

/// Name of the primary contact person at the vendor.
@property (nullable, nonatomic, copy) NSString *contactName;

/// Email address of the primary contact.
@property (nullable, nonatomic, copy) NSString *contactEmail;

/// Phone number of the primary contact.
@property (nullable, nonatomic, copy) NSString *contactPhone;

/// Physical or mailing address of the vendor.
@property (nullable, nonatomic, copy) NSString *address;

/// Whether this vendor is currently active and available for selection.
@property (nullable, nonatomic, strong) NSNumber *isActive;

/// When this vendor record was created.
@property (nullable, nonatomic, strong) NSDate *createdAt;

// MARK: - Relationships

/// Procurement cases associated with this vendor.
@property (nullable, nonatomic, retain) NSSet<CPProcurementCase *> *procurementCases;

/// Pricing rules configured for this vendor.
@property (nullable, nonatomic, retain) NSSet<CPPricingRule *> *pricingRules;

@end

@interface CPVendor (CoreDataGeneratedAccessors)
- (void)addProcurementCasesObject:(CPProcurementCase *)value;
- (void)removeProcurementCasesObject:(CPProcurementCase *)value;
- (void)addProcurementCases:(NSSet<CPProcurementCase *> *)values;
- (void)removeProcurementCases:(NSSet<CPProcurementCase *> *)values;

- (void)addPricingRulesObject:(CPPricingRule *)value;
- (void)removePricingRulesObject:(CPPricingRule *)value;
- (void)addPricingRules:(NSSet<CPPricingRule *> *)values;
- (void)removePricingRules:(NSSet<CPPricingRule *> *)values;
@end

NS_ASSUME_NONNULL_END
