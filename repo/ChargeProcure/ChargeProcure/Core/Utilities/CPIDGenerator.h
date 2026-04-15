#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPIDGenerator : NSObject

+ (instancetype)sharedGenerator;

/// Generate UUID string (lowercase hyphenated)
+ (NSString *)generateUUID;

/// Requisition ID: REQ-YYYYMMDD-XXXX (4-digit random)
- (NSString *)generateRequisitionID;

/// Purchase Order ID: PO-YYYYMMDD-XXXX
- (NSString *)generatePurchaseOrderID;

/// Invoice ID: INV-YYYYMMDD-XXXX
- (NSString *)generateInvoiceID;

/// Receipt ID: REC-YYYYMMDD-XXXX
- (NSString *)generateReceiptID;

/// Return ID: RET-YYYYMMDD-XXXX
- (NSString *)generateReturnID;

/// Payment ID: PAY-YYYYMMDD-XXXX
- (NSString *)generatePaymentID;

/// Command ID: CMD-YYYYMMDD-XXXX
- (NSString *)generateCommandID;

@end

NS_ASSUME_NONNULL_END
