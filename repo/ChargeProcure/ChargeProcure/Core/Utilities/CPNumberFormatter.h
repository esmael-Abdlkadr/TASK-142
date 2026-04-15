#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPNumberFormatter : NSObject

+ (instancetype)sharedFormatter;

/// Currency string: "$1,234.56"
- (NSString *)currencyStringFromDecimal:(NSDecimalNumber *)amount;

/// Percentage string: "2.50%"
- (NSString *)percentageStringFromDouble:(double)value;

/// Compact number: "1.2K", "3.4M"
- (NSString *)compactStringFromInteger:(NSInteger)value;

/// Parse currency string to NSDecimalNumber. Returns nil if invalid.
- (nullable NSDecimalNumber *)decimalFromCurrencyString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
