#import "CPIDGenerator.h"

@implementation CPIDGenerator

+ (instancetype)sharedGenerator {
    static CPIDGenerator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPIDGenerator alloc] init];
    });
    return instance;
}

+ (NSString *)generateUUID {
    return [[[NSUUID UUID] UUIDString] lowercaseString];
}

// Returns current date formatted as "YYYYMMDD"
- (NSString *)_currentDateString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [formatter stringFromDate:[NSDate date]];
}

// Returns a 4-digit random suffix in range 1000–9999
- (NSUInteger)_randomSuffix {
    return (NSUInteger)(arc4random_uniform(9000) + 1000);
}

- (NSString *)_generateIDWithPrefix:(NSString *)prefix {
    NSString *dateString = [self _currentDateString];
    NSUInteger suffix = [self _randomSuffix];
    return [NSString stringWithFormat:@"%@-%@-%04lu", prefix, dateString, (unsigned long)suffix];
}

- (NSString *)generateRequisitionID {
    return [self _generateIDWithPrefix:@"REQ"];
}

- (NSString *)generatePurchaseOrderID {
    return [self _generateIDWithPrefix:@"PO"];
}

- (NSString *)generateInvoiceID {
    return [self _generateIDWithPrefix:@"INV"];
}

- (NSString *)generateReceiptID {
    return [self _generateIDWithPrefix:@"REC"];
}

- (NSString *)generateReturnID {
    return [self _generateIDWithPrefix:@"RET"];
}

- (NSString *)generatePaymentID {
    return [self _generateIDWithPrefix:@"PAY"];
}

- (NSString *)generateCommandID {
    return [self _generateIDWithPrefix:@"CMD"];
}

@end
