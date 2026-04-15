#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPProcurementErrorDomain;
FOUNDATION_EXPORT NSDecimalNumber * const CPVarianceAmountThreshold;   // $25.00
FOUNDATION_EXPORT NSDecimalNumber * const CPVariancePercentThreshold;  // 2.0%
FOUNDATION_EXPORT NSDecimalNumber * const CPWriteOffMaxAmount;          // $250.00

typedef NS_ENUM(NSInteger, CPProcurementError) {
    CPProcurementErrorInvalidStage = 2001,
    CPProcurementErrorVarianceExceeded = 2002,
    CPProcurementErrorWriteOffExceeded = 2003,
    CPProcurementErrorMissingApprover = 2004,
    CPProcurementErrorInvalidAmount = 2005,
    CPProcurementErrorDuplicateInvoice = 2006,
};

@interface CPProcurementService : NSObject

+ (instancetype)sharedService;

// --- Requisition ---
- (nullable NSString *)createRequisitionWithTitle:(NSString *)title
                                      description:(NSString *)description
                                    justification:(NSString *)justification
                                  estimatedAmount:(NSDecimalNumber *)amount
                                            error:(NSError **)error;

- (BOOL)approveRequisition:(NSString *)caseUUID
              approverUUID:(NSString *)approverUUID
                     error:(NSError **)error;

// --- RFQ ---
- (BOOL)issueRFQForCase:(NSString *)caseUUID dueDate:(NSDate *)dueDate error:(NSError **)error;

- (BOOL)addRFQBidForCase:(NSString *)caseUUID
               vendorUUID:(NSString *)vendorUUID
               vendorName:(NSString *)vendorName
               unitPrice:(NSDecimalNumber *)unitPrice
             totalPrice:(NSDecimalNumber *)totalPrice
              taxAmount:(NSDecimalNumber *)taxAmount
                  notes:(nullable NSString *)notes
                  error:(NSError **)error;

- (BOOL)selectRFQBid:(NSString *)bidUUID forCase:(NSString *)caseUUID error:(NSError **)error;

// --- Purchase Order ---
- (BOOL)createPurchaseOrderForCase:(NSString *)caseUUID
                     expectedDelivery:(NSDate *)expectedDelivery
                               notes:(nullable NSString *)notes
                                error:(NSError **)error;

- (BOOL)addPOLineItem:(NSDictionary *)lineItemData toPO:(NSString *)poUUID error:(NSError **)error;

// --- Receipt ---
/// Supports partial receiving: receivedItems is array of {lineItemUUID, receivedQty, description}
- (nullable NSString *)createReceiptForCase:(NSString *)caseUUID
                               receivedItems:(NSArray<NSDictionary *> *)receivedItems
                                    isPartial:(BOOL)isPartial
                                        notes:(nullable NSString *)notes
                                        error:(NSError **)error;

// --- Return ---
- (nullable NSString *)createReturnForCase:(NSString *)caseUUID
                                receiptUUID:(NSString *)receiptUUID
                                     reason:(NSString *)reason
                                     amount:(NSDecimalNumber *)amount
                                      error:(NSError **)error;

// --- Invoice ---
/// Supports partial invoicing. Flags variance if amount vs PO differs by >$25 or >2%.
- (nullable NSString *)createInvoiceForCase:(NSString *)caseUUID
                              invoiceNumber:(NSString *)invoiceNumber
                       vendorInvoiceNumber:(NSString *)vendorInvoiceNumber
                                totalAmount:(NSDecimalNumber *)totalAmount
                                 taxAmount:(NSDecimalNumber *)taxAmount
                                  dueDate:(NSDate *)dueDate
                               lineItems:(NSArray<NSDictionary *> *)lineItems
                                     error:(NSError **)error;

// --- Reconciliation ---
- (BOOL)reconcileInvoice:(NSString *)invoiceUUID
           reconciledByUUID:(NSString *)userUUID
                      error:(NSError **)error;

// --- Write-Off ---
/// Amount must be <= $250.00 cumulative per invoice. Requires approver and note.
- (BOOL)createWriteOffForInvoice:(NSString *)invoiceUUID
                           amount:(NSDecimalNumber *)amount
                           reason:(NSString *)reason
                     approverUUID:(NSString *)approverUUID
                            error:(NSError **)error;

// --- Payment ---
- (nullable NSString *)createPaymentForInvoice:(NSString *)invoiceUUID
                                        amount:(NSDecimalNumber *)amount
                                        method:(NSString *)method
                                         notes:(nullable NSString *)notes
                                         error:(NSError **)error;

// --- Queries ---
- (NSArray *)fetchAllCasesWithStage:(nullable NSString *)stage;
- (nullable id)fetchCaseWithUUID:(NSString *)uuid;
- (NSArray *)fetchInvoicesWithVarianceFlag;
- (NSArray *)generateVendorStatementForVendor:(NSString *)vendorUUID month:(NSDate *)monthDate;

@end

NS_ASSUME_NONNULL_END
