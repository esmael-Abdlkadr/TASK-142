#import "CPProcurementCase+CoreDataClass.h"
#import "CPProcurementCase+CoreDataProperties.h"

static NSString *CPStageStorageString(CPProcurementStage stage) {
    switch (stage) {
        case CPProcurementStageDraft:          return @"Draft";
        case CPProcurementStageRequisition:    return @"Requisition";
        case CPProcurementStageRFQ:            return @"RFQ";
        case CPProcurementStagePO:             return @"PO";
        case CPProcurementStageReceipt:        return @"Receipt";
        case CPProcurementStageInvoice:        return @"Invoice";
        case CPProcurementStageReconciliation: return @"Reconciliation";
        case CPProcurementStagePayment:        return @"Payment";
        case CPProcurementStageClosed:         return @"Closed";
    }
    return @"Draft";
}

static CPProcurementStage CPStageEnumFromStorageString(NSString *stageName) {
    if ([stageName isEqualToString:@"Requisition"]) {
        return CPProcurementStageRequisition;
    }
    if ([stageName isEqualToString:@"RFQ"]) {
        return CPProcurementStageRFQ;
    }
    if ([stageName isEqualToString:@"PO"] || [stageName isEqualToString:@"Purchase Order"]) {
        return CPProcurementStagePO;
    }
    if ([stageName isEqualToString:@"Receipt"]) {
        return CPProcurementStageReceipt;
    }
    if ([stageName isEqualToString:@"Invoice"]) {
        return CPProcurementStageInvoice;
    }
    if ([stageName isEqualToString:@"Reconciliation"]) {
        return CPProcurementStageReconciliation;
    }
    if ([stageName isEqualToString:@"Payment"]) {
        return CPProcurementStagePayment;
    }
    if ([stageName isEqualToString:@"Closed"]) {
        return CPProcurementStageClosed;
    }
    return CPProcurementStageDraft;
}

static NSDate *CPPayloadDateValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [NSDate dateWithTimeIntervalSince1970:[(NSNumber *)value doubleValue]];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [NSDate dateWithTimeIntervalSince1970:[(NSString *)value doubleValue]];
    }
    return nil;
}

@implementation CPProcurementCase

- (NSMutableDictionary *)_payloadDictionary {
    [self willAccessValueForKey:@"notes"];
    NSString *raw = [self primitiveValueForKey:@"notes"];
    [self didAccessValueForKey:@"notes"];
    if (raw.length == 0) {
        return [NSMutableDictionary dictionary];
    }

    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        return [json mutableCopy];
    }

    return [NSMutableDictionary dictionary];
}

- (void)_storePayloadDictionary:(NSDictionary *)payload {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload ?: @{} options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
    [self willChangeValueForKey:@"notes"];
    [self setPrimitiveValue:json forKey:@"notes"];
    [self didChangeValueForKey:@"notes"];
}

- (id)_payloadValueForKey:(NSString *)key {
    return [self _payloadDictionary][key];
}

- (void)_setPayloadValue:(id)value forKey:(NSString *)key {
    NSMutableDictionary *payload = [self _payloadDictionary];
    if (value) {
        payload[key] = value;
    } else {
        [payload removeObjectForKey:key];
    }
    [self _storePayloadDictionary:payload];
}

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPProcurementCase *procCase = [NSEntityDescription insertNewObjectForEntityForName:@"ProcurementCase"
                                                                inManagedObjectContext:context];
    procCase.uuid = [[NSUUID UUID] UUIDString];
    procCase.createdAt = [NSDate date];
    procCase.updatedAt = [NSDate date];
    procCase.stageValue = @(CPProcurementStageDraft);
    procCase.priority = @0;
    procCase.requiresComplianceReview = @NO;
    procCase.currencyCode = @"USD";
    procCase.estimatedAmount = [NSDecimalNumber zero];
    procCase.actualAmount = [NSDecimalNumber zero];
    procCase.metadata = @"{}";

    // Generate a human-readable case number using the current year + a UUID fragment
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger year = [calendar component:NSCalendarUnitYear fromDate:procCase.createdAt];
    NSString *fragment = [[[NSUUID UUID] UUIDString] substringToIndex:8].uppercaseString;
    procCase.caseNumber = [NSString stringWithFormat:@"PC-%ld-%@", (long)year, fragment];

    return procCase;
}

#pragma mark - Stage Accessors

- (CPProcurementStage)procurementStage {
    [self willAccessValueForKey:@"stage"];
    NSString *stageName = [self primitiveValueForKey:@"stage"];
    [self didAccessValueForKey:@"stage"];
    return CPStageEnumFromStorageString(stageName);
}

- (BOOL)advanceStage {
    CPProcurementStage current = [self procurementStage];
    if (current == CPProcurementStageClosed) {
        NSLog(@"[CPProcurementCase] Cannot advance: case '%@' is already closed.", self.caseNumber);
        return NO;
    }

    CPProcurementStage next = current + 1;
    self.stageValue = @(next);
    self.updatedAt = [NSDate date];

    if (next == CPProcurementStageClosed) {
        self.closedAt = [NSDate date];
    }

    NSLog(@"[CPProcurementCase] Case '%@' advanced to stage %ld.", self.caseNumber, (long)next);
    return YES;
}

- (BOOL)isClosed {
    return [self procurementStage] == CPProcurementStageClosed;
}

#pragma mark - Accessor Compatibility

- (NSString *)uuid {
    [self willAccessValueForKey:@"uuid"];
    NSString *value = [self primitiveValueForKey:@"uuid"];
    [self didAccessValueForKey:@"uuid"];
    return value;
}

- (void)setUuid:(NSString *)uuid {
    [self willChangeValueForKey:@"uuid"];
    [self setPrimitiveValue:uuid forKey:@"uuid"];
    [self didChangeValueForKey:@"uuid"];
}

- (NSString *)caseNumber {
    [self willAccessValueForKey:@"caseNumber"];
    NSString *value = [self primitiveValueForKey:@"caseNumber"];
    [self didAccessValueForKey:@"caseNumber"];
    return value;
}

- (void)setCaseNumber:(NSString *)caseNumber {
    [self willChangeValueForKey:@"caseNumber"];
    [self setPrimitiveValue:caseNumber forKey:@"caseNumber"];
    [self didChangeValueForKey:@"caseNumber"];
}

- (NSString *)title {
    [self willAccessValueForKey:@"title"];
    NSString *value = [self primitiveValueForKey:@"title"];
    [self didAccessValueForKey:@"title"];
    return value;
}

- (void)setTitle:(NSString *)title {
    [self willChangeValueForKey:@"title"];
    [self setPrimitiveValue:title forKey:@"title"];
    [self didChangeValueForKey:@"title"];
}

- (NSDate *)createdAt {
    [self willAccessValueForKey:@"createdAt"];
    NSDate *value = [self primitiveValueForKey:@"createdAt"];
    [self didAccessValueForKey:@"createdAt"];
    return value;
}

- (void)setCreatedAt:(NSDate *)createdAt {
    [self willChangeValueForKey:@"createdAt"];
    [self setPrimitiveValue:createdAt forKey:@"createdAt"];
    [self didChangeValueForKey:@"createdAt"];
}

- (NSDate *)updatedAt {
    [self willAccessValueForKey:@"updatedAt"];
    NSDate *value = [self primitiveValueForKey:@"updatedAt"];
    [self didAccessValueForKey:@"updatedAt"];
    return value;
}

- (void)setUpdatedAt:(NSDate *)updatedAt {
    [self willChangeValueForKey:@"updatedAt"];
    [self setPrimitiveValue:updatedAt forKey:@"updatedAt"];
    [self didChangeValueForKey:@"updatedAt"];
}

- (NSNumber *)stageValue {
    return @([self procurementStage]);
}

- (void)setStageValue:(NSNumber *)stageValue {
    CPProcurementStage stage = (CPProcurementStage)stageValue.integerValue;
    [self willChangeValueForKey:@"stage"];
    [self setPrimitiveValue:CPStageStorageString(stage) forKey:@"stage"];
    [self didChangeValueForKey:@"stage"];
    [self willChangeValueForKey:@"status"];
    [self setPrimitiveValue:(stage == CPProcurementStageClosed ? @"Closed" : @"Open") forKey:@"status"];
    [self didChangeValueForKey:@"status"];
}

- (NSDecimalNumber *)estimatedAmount {
    [self willAccessValueForKey:@"totalAmount"];
    NSDecimalNumber *amount = [self primitiveValueForKey:@"totalAmount"];
    [self didAccessValueForKey:@"totalAmount"];
    return amount ?: [NSDecimalNumber zero];
}

- (void)setEstimatedAmount:(NSDecimalNumber *)estimatedAmount {
    [self willChangeValueForKey:@"totalAmount"];
    [self setPrimitiveValue:estimatedAmount ?: [NSDecimalNumber zero] forKey:@"totalAmount"];
    [self didChangeValueForKey:@"totalAmount"];
}

- (NSDecimalNumber *)actualAmount {
    id value = [self _payloadValueForKey:@"actualAmount"];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [NSDecimalNumber decimalNumberWithDecimal:[(NSNumber *)value decimalValue]];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [NSDecimalNumber decimalNumberWithString:(NSString *)value];
    }
    return self.estimatedAmount;
}

- (void)setActualAmount:(NSDecimalNumber *)actualAmount {
    [self _setPayloadValue:(actualAmount ?: [NSDecimalNumber zero]).stringValue forKey:@"actualAmount"];
}

- (NSString *)requestorID {
    [self willAccessValueForKey:@"createdByUserID"];
    NSString *value = [self primitiveValueForKey:@"createdByUserID"];
    [self didAccessValueForKey:@"createdByUserID"];
    return value;
}

- (void)setRequestorID:(NSString *)requestorID {
    [self willChangeValueForKey:@"createdByUserID"];
    [self setPrimitiveValue:requestorID forKey:@"createdByUserID"];
    [self didChangeValueForKey:@"createdByUserID"];
}

- (NSString *)assigneeID {
    return [self _payloadValueForKey:@"assigneeID"];
}

- (void)setAssigneeID:(NSString *)assigneeID {
    [self _setPayloadValue:assigneeID forKey:@"assigneeID"];
}

- (NSString *)vendorName {
    [self willAccessValueForKey:@"vendor"];
    id vendor = [self primitiveValueForKey:@"vendor"];
    [self didAccessValueForKey:@"vendor"];
    NSString *name = [vendor valueForKey:@"name"];
    return name ?: [self _payloadValueForKey:@"vendorName"];
}

- (void)setVendorName:(NSString *)vendorName {
    [self _setPayloadValue:vendorName forKey:@"vendorName"];
}

- (NSString *)poNumber {
    return [self _payloadValueForKey:@"poNumber"];
}

- (void)setPoNumber:(NSString *)poNumber {
    [self _setPayloadValue:poNumber forKey:@"poNumber"];
}

- (NSString *)invoiceNumber {
    return [self _payloadValueForKey:@"invoiceNumber"];
}

- (void)setInvoiceNumber:(NSString *)invoiceNumber {
    [self _setPayloadValue:invoiceNumber forKey:@"invoiceNumber"];
}

- (NSString *)caseDescription {
    return [self _payloadValueForKey:@"caseDescription"];
}

- (void)setCaseDescription:(NSString *)caseDescription {
    [self _setPayloadValue:caseDescription forKey:@"caseDescription"];
}

- (NSString *)metadata {
    id metadata = [self _payloadValueForKey:@"metadata"];
    if ([metadata isKindOfClass:[NSDictionary class]]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil];
        return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
    }
    if ([metadata isKindOfClass:[NSString class]]) {
        return metadata;
    }
    return @"{}";
}

- (void)setMetadata:(NSString *)metadata {
    NSData *data = [metadata dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        [self _setPayloadValue:json forKey:@"metadata"];
    } else {
        [self _setPayloadValue:@{} forKey:@"metadata"];
    }
}

- (NSNumber *)priority {
    id value = [self _payloadValueForKey:@"priority"];
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

- (void)setPriority:(NSNumber *)priority {
    [self _setPayloadValue:priority ?: @0 forKey:@"priority"];
}

- (NSNumber *)requiresComplianceReview {
    id value = [self _payloadValueForKey:@"requiresComplianceReview"];
    return [value isKindOfClass:[NSNumber class]] ? value : @NO;
}

- (void)setRequiresComplianceReview:(NSNumber *)requiresComplianceReview {
    [self _setPayloadValue:requiresComplianceReview ?: @NO forKey:@"requiresComplianceReview"];
}

- (NSString *)currencyCode {
    return [self _payloadValueForKey:@"currencyCode"] ?: @"USD";
}

- (void)setCurrencyCode:(NSString *)currencyCode {
    [self _setPayloadValue:(currencyCode ?: @"USD") forKey:@"currencyCode"];
}

- (NSDate *)requiredByDate {
    return CPPayloadDateValue([self _payloadValueForKey:@"requiredByDate"]);
}

- (void)setRequiredByDate:(NSDate *)requiredByDate {
    [self _setPayloadValue:(requiredByDate ? @([requiredByDate timeIntervalSince1970]) : nil) forKey:@"requiredByDate"];
}

- (NSDate *)closedAt {
    return CPPayloadDateValue([self _payloadValueForKey:@"closedAt"]);
}

- (void)setClosedAt:(NSDate *)closedAt {
    [self _setPayloadValue:(closedAt ? @([closedAt timeIntervalSince1970]) : nil) forKey:@"closedAt"];
}

@end
