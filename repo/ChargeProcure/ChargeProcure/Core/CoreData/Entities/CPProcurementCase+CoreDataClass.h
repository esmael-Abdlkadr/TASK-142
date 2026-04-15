#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents the workflow stage a procurement case is currently in.
typedef NS_ENUM(NSInteger, CPProcurementStage) {
    CPProcurementStageDraft          = 0,
    CPProcurementStageRequisition    = 1,
    CPProcurementStageRFQ            = 2,   // Request For Quotation
    CPProcurementStagePO             = 3,   // Purchase Order
    CPProcurementStageReceipt        = 4,   // Goods/Services Receipt
    CPProcurementStageInvoice        = 5,
    CPProcurementStageReconciliation = 6,
    CPProcurementStagePayment        = 7,
    CPProcurementStageClosed         = 8
};

@interface CPProcurementCase : NSManagedObject

+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

/// Returns the typed enum value of the current stage.
- (CPProcurementStage)procurementStage;

/// Advances the case to the next logical stage if permitted.
/// Returns YES if the transition was applied, NO if already at a terminal stage.
- (BOOL)advanceStage;

/// Returns YES if the case is in a terminal (closed) stage.
- (BOOL)isClosed;

@end

NS_ASSUME_NONNULL_END

#import "CPProcurementCase+CoreDataProperties.h"
