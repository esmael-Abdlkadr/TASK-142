#import "CPInvoice+CoreDataClass.h"
#import "CPInvoice+CoreDataProperties.h"
#import "CPWriteOff+CoreDataClass.h"
#import "CPWriteOff+CoreDataProperties.h"

@implementation CPInvoice

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPInvoice *invoice = [NSEntityDescription insertNewObjectForEntityForName:@"Invoice"
                                                       inManagedObjectContext:context];
    invoice.uuid          = [[NSUUID UUID] UUIDString];
    invoice.invoicedAt    = [NSDate date];
    invoice.varianceFlag  = @NO;
    invoice.varianceAmount     = [NSDecimalNumber zero];
    invoice.variancePercentage = [NSDecimalNumber zero];
    invoice.writeOffAmount     = [NSDecimalNumber zero];
    return invoice;
}

#pragma mark - Variance

- (void)calculateVarianceAgainstPOTotal:(NSDecimalNumber *)poTotal {
    NSParameterAssert(poTotal);

    NSDecimalNumber *invoiceTotal = self.totalAmount ?: [NSDecimalNumber zero];

    // |invoiceTotal - poTotal|
    NSDecimalNumber *diff      = [invoiceTotal decimalNumberBySubtracting:poTotal];
    NSDecimalNumber *absAmount = ([diff compare:[NSDecimalNumber zero]] == NSOrderedAscending)
                                    ? [[NSDecimalNumber zero] decimalNumberBySubtracting:diff]
                                    : diff;
    self.varianceAmount = absAmount;

    // percentage = (absAmount / poTotal) * 100, guard divide-by-zero
    NSDecimalNumber *percentage = [NSDecimalNumber zero];
    if ([poTotal compare:[NSDecimalNumber zero]] != NSOrderedSame) {
        NSDecimalNumber *hundred = [NSDecimalNumber decimalNumberWithString:@"100"];
        percentage = [[absAmount decimalNumberByDividingBy:poTotal]
                          decimalNumberByMultiplyingBy:hundred];
    }
    self.variancePercentage = percentage;

    // Flag: amount > $25 OR percentage > 2.0%
    NSDecimalNumber *thresholdAmount  = [NSDecimalNumber decimalNumberWithString:@"25.00"];
    NSDecimalNumber *thresholdPercent = [NSDecimalNumber decimalNumberWithString:@"2.0"];

    BOOL flagged = ([absAmount compare:thresholdAmount]  == NSOrderedDescending)
                || ([percentage compare:thresholdPercent] == NSOrderedDescending);
    self.varianceFlag = @(flagged);
}

- (BOOL)hasSignificantVariance {
    return self.varianceFlag.boolValue;
}

#pragma mark - Write-Off Helpers

- (NSDecimalNumber *)totalWriteOffAmount {
    NSDecimalNumber *total = [NSDecimalNumber zero];
    for (CPWriteOff *writeOff in self.writeOffs) {
        NSDecimalNumber *amount = writeOff.amount ?: [NSDecimalNumber zero];
        total = [total decimalNumberByAdding:amount];
    }
    return total;
}

- (NSDecimalNumber *)remainingWriteOffCapacity {
    NSDecimalNumber *cap       = [NSDecimalNumber decimalNumberWithString:@"250.00"];
    NSDecimalNumber *remaining = [cap decimalNumberBySubtracting:[self totalWriteOffAmount]];
    // Never return a negative value
    if ([remaining compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
        return [NSDecimalNumber zero];
    }
    return remaining;
}

@end
