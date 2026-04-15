#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
@class CPInvoiceLineItem, CPPayment, CPWriteOff, CPAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface CPInvoice : NSManagedObject

+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

/// Calculate variance from purchase order total.
/// Sets varianceAmount, variancePercentage, and varianceFlag on the receiver.
- (void)calculateVarianceAgainstPOTotal:(NSDecimalNumber *)poTotal;

/// Returns YES if variance exceeds $25.00 OR 2.0%.
- (BOOL)hasSignificantVariance;

/// Sum of all write-offs for this invoice.
- (NSDecimalNumber *)totalWriteOffAmount;

/// Remaining write-off capacity ($250 - totalWriteOffAmount), never negative.
- (NSDecimalNumber *)remainingWriteOffCapacity;

@end

NS_ASSUME_NONNULL_END

#import "CPInvoice+CoreDataProperties.h"
