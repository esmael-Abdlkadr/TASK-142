#import "CPNumberFormatter.h"

@interface CPNumberFormatter ()

@property (nonatomic, strong) NSNumberFormatter *currencyFormatter;
@property (nonatomic, strong) NSNumberFormatter *percentageFormatter;
@property (nonatomic, strong) NSNumberFormatter *currencyParseFormatter;

@end

@implementation CPNumberFormatter

+ (instancetype)sharedFormatter {
    static CPNumberFormatter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPNumberFormatter alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _initFormatters];
    }
    return self;
}

- (void)_initFormatters {
    NSLocale *enUS = [NSLocale localeWithLocaleIdentifier:@"en_US"];

    // Currency formatter — outputs "$1,234.56"
    _currencyFormatter = [[NSNumberFormatter alloc] init];
    _currencyFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
    _currencyFormatter.locale = enUS;
    _currencyFormatter.minimumFractionDigits = 2;
    _currencyFormatter.maximumFractionDigits = 2;

    // Percentage formatter — outputs "2.50%"
    _percentageFormatter = [[NSNumberFormatter alloc] init];
    _percentageFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    _percentageFormatter.locale = enUS;
    _percentageFormatter.minimumFractionDigits = 2;
    _percentageFormatter.maximumFractionDigits = 2;
    _percentageFormatter.positiveSuffix = @"%";
    _percentageFormatter.negativeSuffix = @"%";

    // Currency parse formatter — strips "$" and "," to parse back to decimal
    _currencyParseFormatter = [[NSNumberFormatter alloc] init];
    _currencyParseFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
    _currencyParseFormatter.locale = enUS;
    _currencyParseFormatter.generatesDecimalNumbers = YES;
}

#pragma mark - Public API

- (NSString *)currencyStringFromDecimal:(NSDecimalNumber *)amount {
    if (amount == nil) {
        return @"$0.00";
    }
    NSString *result = [self.currencyFormatter stringFromNumber:amount];
    return result ?: @"$0.00";
}

- (NSString *)percentageStringFromDouble:(double)value {
    NSString *result = [self.percentageFormatter stringFromNumber:@(value)];
    return result ?: [NSString stringWithFormat:@"%.2f%%", value];
}

- (NSString *)compactStringFromInteger:(NSInteger)value {
    double absValue = (double)llabs((long long)value);
    NSString *sign = value < 0 ? @"-" : @"";

    if (absValue >= 1000000.0) {
        double millions = absValue / 1000000.0;
        // Show one decimal place, strip trailing ".0"
        if (fmod(millions * 10, 10) == 0) {
            return [NSString stringWithFormat:@"%@%.0fM", sign, millions];
        }
        return [NSString stringWithFormat:@"%@%.1fM", sign, millions];
    }

    if (absValue >= 1000.0) {
        double thousands = absValue / 1000.0;
        if (fmod(thousands * 10, 10) == 0) {
            return [NSString stringWithFormat:@"%@%.0fK", sign, thousands];
        }
        return [NSString stringWithFormat:@"%@%.1fK", sign, thousands];
    }

    return [NSString stringWithFormat:@"%ld", (long)value];
}

- (nullable NSDecimalNumber *)decimalFromCurrencyString:(NSString *)string {
    if (string.length == 0) {
        return nil;
    }

    // Use NSNumberFormatter with generatesDecimalNumbers to parse
    NSDecimalNumber *result = (NSDecimalNumber *)[self.currencyParseFormatter numberFromString:string];

    if (result == nil) {
        // Fallback: strip common currency symbols/commas and try again
        NSMutableString *stripped = [string mutableCopy];
        NSCharacterSet *unwanted = [NSCharacterSet characterSetWithCharactersInString:@"$,€£¥ "];
        NSArray<NSString *> *parts = [stripped componentsSeparatedByCharactersInSet:unwanted];
        NSString *joined = [parts componentsJoinedByString:@""];
        if (joined.length == 0) {
            return nil;
        }
        result = [NSDecimalNumber decimalNumberWithString:joined];
        if ([result isEqualToNumber:[NSDecimalNumber notANumber]]) {
            return nil;
        }
    }

    return result;
}

@end
