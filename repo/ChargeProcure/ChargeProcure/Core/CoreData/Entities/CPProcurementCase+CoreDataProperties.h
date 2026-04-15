#import "CPProcurementCase+CoreDataClass.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPProcurementCase (CoreDataProperties)
+ (NSFetchRequest<CPProcurementCase *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this procurement case.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Human-readable case reference number (e.g. "PC-2026-00042").
@property (nullable, nonatomic, copy) NSString *caseNumber;

/// Short description / title of what is being procured.
@property (nullable, nonatomic, copy) NSString *title;

/// Longer narrative description of the procurement requirement.
@property (nullable, nonatomic, copy) NSString *caseDescription;

/// Serialised CPProcurementStage integer stored as NSNumber.
@property (nullable, nonatomic, strong) NSNumber *stageValue;

/// Total estimated or committed budget for this case.
@property (nullable, nonatomic, strong) NSDecimalNumber *estimatedAmount;

/// Actual invoiced/paid amount (populated as the case progresses).
@property (nullable, nonatomic, strong) NSDecimalNumber *actualAmount;

/// ISO 4217 currency code (e.g. "USD", "EUR").
@property (nullable, nonatomic, copy) NSString *currencyCode;

/// User ID of the person who raised the case.
@property (nullable, nonatomic, copy) NSString *requestorID;

/// User ID of the assigned approver / buyer.
@property (nullable, nonatomic, copy) NSString *assigneeID;

/// Vendor / supplier name or identifier.
@property (nullable, nonatomic, copy) NSString *vendorName;

/// Purchase order number issued to the vendor.
@property (nullable, nonatomic, copy) NSString *poNumber;

/// Invoice reference number from the vendor.
@property (nullable, nonatomic, copy) NSString *invoiceNumber;

/// When the case record was created.
@property (nullable, nonatomic, strong) NSDate *createdAt;

/// When the case was last modified.
@property (nullable, nonatomic, strong) NSDate *updatedAt;

/// Target/required delivery or completion date.
@property (nullable, nonatomic, strong) NSDate *requiredByDate;

/// Date the case was closed (payment confirmed / cancelled).
@property (nullable, nonatomic, strong) NSDate *closedAt;

/// Optional JSON blob for storing flexible per-stage metadata.
@property (nullable, nonatomic, copy) NSString *metadata;

/// Priority level: 0 = Normal, 1 = High, 2 = Urgent.
@property (nullable, nonatomic, strong) NSNumber *priority;

/// Whether the case has been flagged for compliance review.
@property (nullable, nonatomic, strong) NSNumber *requiresComplianceReview;

@end

NS_ASSUME_NONNULL_END
