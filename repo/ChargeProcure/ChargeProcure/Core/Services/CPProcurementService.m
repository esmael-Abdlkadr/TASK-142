#import "CPProcurementService.h"
#import "CPAuditService.h"
#import "CPAuthService.h"
#import "../CoreData/CPCoreDataStack.h"
#import "../Utilities/CPIDGenerator.h"
#import "../CoreData/Entities/CPProcurementCase+CoreDataClass.h"
#import "../CoreData/Entities/CPProcurementCase+CoreDataProperties.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

NSString * const CPProcurementErrorDomain = @"com.chargeprocure.procurement";

NSDecimalNumber * const CPVarianceAmountThreshold  = nil; // Initialised in +load
NSDecimalNumber * const CPVariancePercentThreshold = nil;
NSDecimalNumber * const CPWriteOffMaxAmount        = nil;

// We cannot assign non-literal values to FOUNDATION_EXPORT constants at
// file scope in ObjC; use static constants and expose through a dedicated
// accessor, OR initialise them via +load below.

static NSDecimalNumber *_varianceAmountThreshold;
static NSDecimalNumber *_variancePercentThreshold;
static NSDecimalNumber *_writeOffMaxAmount;

// ---------------------------------------------------------------------------
// Stage name helpers
// ---------------------------------------------------------------------------

static NSString *_stageNameForStage(CPProcurementStage stage) {
    switch (stage) {
        case CPProcurementStageDraft:          return @"Draft";
        case CPProcurementStageRequisition:    return @"Requisition";
        case CPProcurementStageRFQ:            return @"RFQ";
        case CPProcurementStagePO:             return @"PurchaseOrder";
        case CPProcurementStageReceipt:        return @"Receipt";
        case CPProcurementStageInvoice:        return @"Invoice";
        case CPProcurementStageReconciliation: return @"Reconciliation";
        case CPProcurementStagePayment:        return @"Payment";
        case CPProcurementStageClosed:         return @"Closed";
    }
    return @"Unknown";
}

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface CPProcurementService ()
- (NSError *)errorWithCode:(CPProcurementError)code description:(NSString *)desc;
- (nullable NSManagedObject *)_fetchEntityNamed:(NSString *)entityName
                                           uuid:(NSString *)uuid
                                      inContext:(NSManagedObjectContext *)ctx;
- (nullable CPProcurementCase *)_fetchCaseWithUUID:(NSString *)uuid
                                         inContext:(NSManagedObjectContext *)ctx;
@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation CPProcurementService

#pragma mark - Class initialisation

+ (void)load {
    _varianceAmountThreshold  = [NSDecimalNumber decimalNumberWithString:@"25.00"];
    _variancePercentThreshold = [NSDecimalNumber decimalNumberWithString:@"2.0"];
    _writeOffMaxAmount        = [NSDecimalNumber decimalNumberWithString:@"250.00"];
}

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPProcurementService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPProcurementService alloc] init];
    });
    return _shared;
}

#pragma mark - Requisition

- (nullable NSString *)createRequisitionWithTitle:(NSString *)title
                                      description:(NSString *)description
                                    justification:(NSString *)justification
                                  estimatedAmount:(NSDecimalNumber *)amount
                                            error:(NSError **)error {
    NSParameterAssert(title.length > 0);
    NSParameterAssert(amount != nil);

    // RBAC: require Procurement.create permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.create"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.create is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:@""
                                           detail:@"createRequisition denied: insufficient role"];
        return nil;
    }

    if ([amount compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidAmount
                                    description:@"Estimated amount must be non-negative."];
        return nil;
    }

    __block NSString *caseUUID = nil;
    __block NSError *opError   = nil;
    dispatch_semaphore_t sem   = dispatch_semaphore_create(0);
    NSString *requestorID      = [CPAuthService sharedService].currentUserID;

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        // Create ProcurementCase
        CPProcurementCase *procCase = [CPProcurementCase insertInContext:ctx];
        procCase.title           = title;
        procCase.caseDescription = description;
        procCase.estimatedAmount = amount;
        procCase.requestorID     = requestorID;
        procCase.stageValue      = @(CPProcurementStageRequisition);
        procCase.caseNumber      = [[CPIDGenerator sharedGenerator] generateRequisitionID];

        caseUUID = procCase.uuid;

        // Create Requisition entity
        NSManagedObject *req = [NSEntityDescription insertNewObjectForEntityForName:@"Requisition"
                                                             inManagedObjectContext:ctx];
        [req setValue:[CPIDGenerator generateUUID] forKey:@"uuid"];
        [req setValue:caseUUID                     forKey:@"caseID"];
        [req setValue:requestorID                  forKey:@"requestedBy"];
        [req setValue:description                  forKey:@"description"];
        [req setValue:justification                forKey:@"justification"];
        [req setValue:amount                       forKey:@"estimatedAmount"];
        [req setValue:@"Pending"                   forKey:@"status"];
        [req setValue:[NSDate date]                forKey:@"createdAt"];
        [req setValue:procCase                     forKey:@"procurementCase"];

        NSError *saveErr = nil;
        if (![ctx save:&saveErr]) {
            opError = saveErr;
            caseUUID = nil;
        } else {
            [[CPAuditService sharedService] logAction:@"requisition_created"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"Title=%@ Amount=%@", title, amount]];
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return caseUUID;
}

- (BOOL)approveRequisition:(NSString *)caseUUID
              approverUUID:(NSString *)approverUUID
                     error:(NSError **)error {
    NSParameterAssert(caseUUID.length > 0);

    // RBAC: require Procurement.update permission to approve
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required to approve."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"approveRequisition denied: insufficient role"];
        return NO;
    }

    if (!approverUUID.length) {
        if (error) *error = [self errorWithCode:CPProcurementErrorMissingApprover
                                    description:@"Approver UUID is required."];
        return NO;
    }

    __block BOOL success  = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (!procCase) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:@"Procurement case not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        if (procCase.procurementStage != CPProcurementStageRequisition) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:[NSString stringWithFormat:
                                           @"Cannot approve: case is not in Requisition stage (current: %@).",
                                           _stageNameForStage(procCase.procurementStage)]];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Update the linked Requisition record
        NSFetchRequest *reqFetch = [NSFetchRequest fetchRequestWithEntityName:@"Requisition"];
        reqFetch.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", caseUUID];
        reqFetch.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSArray *reqs = [ctx executeFetchRequest:reqFetch error:&fetchErr];
        NSManagedObject *requisition = reqs.firstObject;
        if (requisition) {
            [requisition setValue:@"Approved"    forKey:@"status"];
            [requisition setValue:[NSDate date]  forKey:@"approvedAt"];
            [requisition setValue:approverUUID   forKey:@"approvedByUserID"];
        }

        // Advance case to RFQ stage
        [procCase advanceStage];
        procCase.assigneeID = approverUUID;

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"requisition_approved"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"ApprovedBy=%@", approverUUID]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - RFQ

- (BOOL)issueRFQForCase:(NSString *)caseUUID
                dueDate:(NSDate *)dueDate
                  error:(NSError **)error {
    NSParameterAssert(caseUUID.length > 0);
    NSParameterAssert(dueDate != nil);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"issueRFQ denied: insufficient role"];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (!procCase) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Case not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        if (procCase.procurementStage != CPProcurementStageRFQ) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:[NSString stringWithFormat:
                                           @"Cannot issue RFQ: case is not in RFQ stage (current: %@).",
                                           _stageNameForStage(procCase.procurementStage)]];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Create RFQ entity
        NSManagedObject *rfq = [NSEntityDescription insertNewObjectForEntityForName:@"RFQ"
                                                             inManagedObjectContext:ctx];
        [rfq setValue:[CPIDGenerator generateUUID] forKey:@"uuid"];
        [rfq setValue:caseUUID                     forKey:@"caseID"];
        [rfq setValue:[NSDate date]                forKey:@"issuedAt"];
        [rfq setValue:dueDate                      forKey:@"dueDate"];
        [rfq setValue:@"Open"                      forKey:@"status"];
        [rfq setValue:procCase                     forKey:@"procurementCase"];

        procCase.updatedAt = [NSDate date];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"rfq_issued"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"DueDate=%@", dueDate]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)addRFQBidForCase:(NSString *)caseUUID
               vendorUUID:(NSString *)vendorUUID
               vendorName:(NSString *)vendorName
               unitPrice:(NSDecimalNumber *)unitPrice
             totalPrice:(NSDecimalNumber *)totalPrice
              taxAmount:(NSDecimalNumber *)taxAmount
                  notes:(nullable NSString *)notes
                  error:(NSError **)error {
    NSParameterAssert(caseUUID.length > 0);
    NSParameterAssert(vendorName.length > 0);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"addRFQBid denied: insufficient role"];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (!procCase) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Case not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Fetch RFQ for this case
        NSFetchRequest *rfqFetch = [NSFetchRequest fetchRequestWithEntityName:@"RFQ"];
        rfqFetch.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", caseUUID];
        rfqFetch.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSArray *rfqs = [ctx executeFetchRequest:rfqFetch error:&fetchErr];
        NSManagedObject *rfq = rfqs.firstObject;

        if (!rfq) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:@"No RFQ found for this case."];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSManagedObject *bid = [NSEntityDescription insertNewObjectForEntityForName:@"RFQBid"
                                                             inManagedObjectContext:ctx];
        [bid setValue:[CPIDGenerator generateUUID]         forKey:@"uuid"];
        [bid setValue:[rfq valueForKey:@"uuid"]            forKey:@"rfqID"];
        [bid setValue:vendorUUID                           forKey:@"vendorID"];
        [bid setValue:vendorName                           forKey:@"vendorName"];
        [bid setValue:unitPrice  ?: [NSDecimalNumber zero] forKey:@"unitPrice"];
        [bid setValue:totalPrice ?: [NSDecimalNumber zero] forKey:@"totalPrice"];
        [bid setValue:taxAmount  ?: [NSDecimalNumber zero] forKey:@"taxAmount"];
        [bid setValue:[NSDate date]                        forKey:@"submittedAt"];
        [bid setValue:@NO                                  forKey:@"isSelected"];
        [bid setValue:notes                                forKey:@"notes"];
        [bid setValue:rfq                                  forKey:@"rfq"];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"rfq_bid_added"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"Vendor=%@ Total=%@",
                                                       vendorName, totalPrice]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)selectRFQBid:(NSString *)bidUUID
             forCase:(NSString *)caseUUID
               error:(NSError **)error {
    NSParameterAssert(bidUUID.length > 0);
    NSParameterAssert(caseUUID.length > 0);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"selectRFQBid denied: insufficient role"];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (!procCase) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Case not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Fetch the bid
        NSFetchRequest *bidFetch = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        bidFetch.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", bidUUID];
        bidFetch.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSArray *bids = [ctx executeFetchRequest:bidFetch error:&fetchErr];
        NSManagedObject *selectedBid = bids.firstObject;

        if (!selectedBid) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:@"Bid not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Mark this bid as selected, others as not selected
        NSString *rfqID = [selectedBid valueForKey:@"rfqID"];
        NSFetchRequest *allBids = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        allBids.predicate = [NSPredicate predicateWithFormat:@"rfqID == %@", rfqID];
        NSArray *allBidsArr = [ctx executeFetchRequest:allBids error:nil];
        for (NSManagedObject *bid in allBidsArr) {
            [bid setValue:@NO forKey:@"isSelected"];
        }
        [selectedBid setValue:@YES forKey:@"isSelected"];

        // Advance case to PO stage
        [procCase advanceStage];

        // Store vendor info on the case
        procCase.vendorName = [selectedBid valueForKey:@"vendorName"];
        procCase.estimatedAmount = [selectedBid valueForKey:@"totalPrice"] ?: procCase.estimatedAmount;

        // Update RFQ status to Closed
        NSFetchRequest *rfqFetch = [NSFetchRequest fetchRequestWithEntityName:@"RFQ"];
        rfqFetch.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", rfqID];
        rfqFetch.fetchLimit = 1;
        NSArray *rfqs = [ctx executeFetchRequest:rfqFetch error:nil];
        [[rfqs firstObject] setValue:@"Closed" forKey:@"status"];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"rfq_bid_selected"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"BidUUID=%@ Vendor=%@",
                                                       bidUUID, procCase.vendorName]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Purchase Order

- (BOOL)createPurchaseOrderForCase:(NSString *)caseUUID
                   expectedDelivery:(NSDate *)expectedDelivery
                             notes:(nullable NSString *)notes
                              error:(NSError **)error {
    NSParameterAssert(caseUUID.length > 0);
    NSParameterAssert(expectedDelivery != nil);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"createPurchaseOrder denied: insufficient role"];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (!procCase) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Case not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        if (procCase.procurementStage != CPProcurementStagePO) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:[NSString stringWithFormat:
                                           @"Cannot create PO: case is not in PO stage (current: %@).",
                                           _stageNameForStage(procCase.procurementStage)]];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSString *poNumber = [[CPIDGenerator sharedGenerator] generatePurchaseOrderID];

        NSManagedObject *po = [NSEntityDescription insertNewObjectForEntityForName:@"PurchaseOrder"
                                                            inManagedObjectContext:ctx];
        [po setValue:[CPIDGenerator generateUUID]        forKey:@"uuid"];
        [po setValue:caseUUID                            forKey:@"caseID"];
        [po setValue:poNumber                            forKey:@"poNumber"];
        [po setValue:[NSDate date]                       forKey:@"issuedAt"];
        [po setValue:expectedDelivery                    forKey:@"expectedDelivery"];
        [po setValue:@"Open"                             forKey:@"status"];
        [po setValue:procCase.estimatedAmount            forKey:@"totalAmount"];
        [po setValue:[NSDecimalNumber zero]              forKey:@"taxAmount"];
        [po setValue:notes                               forKey:@"notes"];
        [po setValue:procCase                            forKey:@"procurementCase"];

        procCase.poNumber  = poNumber;
        procCase.updatedAt = [NSDate date];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"purchase_order_created"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"PONumber=%@", poNumber]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)addPOLineItem:(NSDictionary *)lineItemData
                 toPO:(NSString *)poUUID
                error:(NSError **)error {
    NSParameterAssert(lineItemData != nil);
    NSParameterAssert(poUUID.length > 0);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"PurchaseOrder"
                                       resourceID:poUUID
                                           detail:@"addPOLineItem denied: insufficient role"];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSFetchRequest *poFetch = [NSFetchRequest fetchRequestWithEntityName:@"PurchaseOrder"];
        poFetch.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", poUUID];
        poFetch.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSArray *pos = [ctx executeFetchRequest:poFetch error:&fetchErr];
        NSManagedObject *po = pos.firstObject;

        if (!po) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:@"Purchase order not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSDecimalNumber *qty        = lineItemData[@"quantity"]  ?: [NSDecimalNumber zero];
        NSDecimalNumber *unitPrice  = lineItemData[@"unitPrice"]  ?: [NSDecimalNumber zero];
        NSDecimalNumber *totalPrice = lineItemData[@"totalPrice"] ?: [qty decimalNumberByMultiplyingBy:unitPrice];
        NSDecimalNumber *taxRate    = lineItemData[@"taxRate"]    ?: [NSDecimalNumber zero];

        NSManagedObject *lineItem = [NSEntityDescription insertNewObjectForEntityForName:@"POLineItem"
                                                                  inManagedObjectContext:ctx];
        [lineItem setValue:[CPIDGenerator generateUUID] forKey:@"uuid"];
        [lineItem setValue:poUUID                       forKey:@"poID"];
        [lineItem setValue:lineItemData[@"description"] forKey:@"description"];
        [lineItem setValue:qty                          forKey:@"quantity"];
        [lineItem setValue:unitPrice                    forKey:@"unitPrice"];
        [lineItem setValue:totalPrice                   forKey:@"totalPrice"];
        [lineItem setValue:taxRate                      forKey:@"taxRate"];
        [lineItem setValue:[NSDecimalNumber zero]       forKey:@"receivedQty"];
        [lineItem setValue:po                           forKey:@"purchaseOrder"];

        // Recalculate PO total
        NSDecimalNumber *currentTotal = [po valueForKey:@"totalAmount"] ?: [NSDecimalNumber zero];
        [po setValue:[currentTotal decimalNumberByAdding:totalPrice] forKey:@"totalAmount"];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Receipt

- (nullable NSString *)createReceiptForCase:(NSString *)caseUUID
                               receivedItems:(NSArray<NSDictionary *> *)receivedItems
                                   isPartial:(BOOL)isPartial
                                       notes:(nullable NSString *)notes
                                       error:(NSError **)error {
    NSParameterAssert(caseUUID.length > 0);
    NSParameterAssert(receivedItems.count > 0);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"createReceipt denied: insufficient role"];
        return nil;
    }

    __block NSString *receiptUUID = nil;
    __block NSError *opError      = nil;
    dispatch_semaphore_t sem      = dispatch_semaphore_create(0);
    NSString *receiverID          = [CPAuthService sharedService].currentUserID;

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (!procCase) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Case not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Accept both PO stage (pre-receipt) and Receipt stage (partially received).
        // Auto-advance from PO to Receipt when first receipt is created.
        if (procCase.procurementStage != CPProcurementStageReceipt &&
            procCase.procurementStage != CPProcurementStagePO) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:[NSString stringWithFormat:
                                           @"Cannot create receipt: case must be in PO or Receipt stage (current: %@).",
                                           _stageNameForStage(procCase.procurementStage)]];
            dispatch_semaphore_signal(sem);
            return;
        }
        if (procCase.procurementStage == CPProcurementStagePO) {
            [procCase advanceStage]; // PO(3) → Receipt(4)
        }

        // Fetch linked PO
        NSFetchRequest *poFetch = [NSFetchRequest fetchRequestWithEntityName:@"PurchaseOrder"];
        poFetch.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", caseUUID];
        poFetch.fetchLimit = 1;
        NSArray *pos = [ctx executeFetchRequest:poFetch error:nil];
        NSManagedObject *po = pos.firstObject;
        NSString *poUUID = po ? [po valueForKey:@"uuid"] : nil;

        // Create Receipt
        receiptUUID = [CPIDGenerator generateUUID];
        NSString *receiptNumber = [[CPIDGenerator sharedGenerator] generateReceiptID];

        NSManagedObject *receipt = [NSEntityDescription insertNewObjectForEntityForName:@"Receipt"
                                                                 inManagedObjectContext:ctx];
        [receipt setValue:receiptUUID    forKey:@"uuid"];
        [receipt setValue:caseUUID       forKey:@"caseID"];
        [receipt setValue:poUUID         forKey:@"poID"];
        [receipt setValue:receiptNumber  forKey:@"receiptNumber"];
        [receipt setValue:[NSDate date]  forKey:@"receivedAt"];
        [receipt setValue:receiverID     forKey:@"receivedByUserID"];
        [receipt setValue:@(isPartial)   forKey:@"isPartial"];
        [receipt setValue:notes          forKey:@"notes"];
        [receipt setValue:procCase       forKey:@"procurementCase"];

        // Update received quantities on PO line items
        for (NSDictionary *item in receivedItems) {
            NSString *lineItemUUID = item[@"lineItemUUID"];
            NSDecimalNumber *receivedQty = item[@"receivedQty"];
            if (!lineItemUUID || !receivedQty) continue;

            NSFetchRequest *liFetch = [NSFetchRequest fetchRequestWithEntityName:@"POLineItem"];
            liFetch.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", lineItemUUID];
            liFetch.fetchLimit = 1;
            NSArray *lis = [ctx executeFetchRequest:liFetch error:nil];
            NSManagedObject *lineItem = lis.firstObject;
            if (lineItem) {
                NSDecimalNumber *existing = [lineItem valueForKey:@"receivedQty"] ?: [NSDecimalNumber zero];
                NSDecimalNumber *newQty   = [existing decimalNumberByAdding:receivedQty];
                [lineItem setValue:newQty forKey:@"receivedQty"];
            }
        }

        // Advance stage to Invoice if not partial, otherwise stay at Receipt
        if (!isPartial) {
            [procCase advanceStage]; // → Invoice
        }
        procCase.updatedAt = [NSDate date];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            [[CPAuditService sharedService] logAction:@"receipt_created"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"ReceiptNumber=%@ Partial=%@",
                                                       receiptNumber, isPartial ? @"YES" : @"NO"]];
        } else {
            opError = saveErr;
            receiptUUID = nil;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return receiptUUID;
}

#pragma mark - Return

- (nullable NSString *)createReturnForCase:(NSString *)caseUUID
                                receiptUUID:(NSString *)receiptUUID
                                     reason:(NSString *)reason
                                     amount:(NSDecimalNumber *)amount
                                      error:(NSError **)error {
    NSParameterAssert(caseUUID.length > 0);
    NSParameterAssert(receiptUUID.length > 0);
    NSParameterAssert(reason.length > 0);
    NSParameterAssert(amount != nil);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"createReturn denied: insufficient role"];
        return nil;
    }

    __block NSString *returnUUID = nil;
    __block NSError *opError     = nil;
    dispatch_semaphore_t sem     = dispatch_semaphore_create(0);
    NSString *returnerID         = [CPAuthService sharedService].currentUserID;

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSString *returnNumber = [[CPIDGenerator sharedGenerator] generateReturnID];
        returnUUID = [CPIDGenerator generateUUID];

        NSManagedObject *ret = [NSEntityDescription insertNewObjectForEntityForName:@"Return"
                                                             inManagedObjectContext:ctx];
        [ret setValue:returnUUID     forKey:@"uuid"];
        [ret setValue:caseUUID       forKey:@"caseID"];
        [ret setValue:receiptUUID    forKey:@"receiptID"];
        [ret setValue:returnNumber   forKey:@"returnNumber"];
        [ret setValue:reason         forKey:@"reason"];
        [ret setValue:[NSDate date]  forKey:@"returnedAt"];
        [ret setValue:returnerID     forKey:@"returnedByUserID"];
        [ret setValue:amount         forKey:@"amount"];
        [ret setValue:@"Pending"     forKey:@"status"];

        // Associate with procurement case
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (procCase) {
            [ret setValue:procCase forKey:@"procurementCase"];
        }

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            [[CPAuditService sharedService] logAction:@"return_created"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:[NSString stringWithFormat:@"ReturnNumber=%@ Amount=%@ Reason=%@",
                                                       returnNumber, amount, reason]];
        } else {
            opError = saveErr;
            returnUUID = nil;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return returnUUID;
}

#pragma mark - Invoice

- (nullable NSString *)createInvoiceForCase:(NSString *)caseUUID
                              invoiceNumber:(NSString *)invoiceNumber
                       vendorInvoiceNumber:(NSString *)vendorInvoiceNumber
                                totalAmount:(NSDecimalNumber *)totalAmount
                                 taxAmount:(NSDecimalNumber *)taxAmount
                                  dueDate:(NSDate *)dueDate
                               lineItems:(NSArray<NSDictionary *> *)lineItems
                                     error:(NSError **)error {
    NSParameterAssert(caseUUID.length > 0);
    NSParameterAssert(invoiceNumber.length > 0);
    NSParameterAssert(totalAmount != nil);
    NSParameterAssert(dueDate != nil);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"ProcurementCase"
                                       resourceID:caseUUID
                                           detail:@"createInvoice denied: insufficient role"];
        return nil;
    }

    __block NSString *invoiceUUID = nil;
    __block NSError *opError      = nil;
    dispatch_semaphore_t sem      = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseUUID inContext:ctx];
        if (!procCase) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Case not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Accept Receipt stage (auto-advance to Invoice) or Invoice stage.
        if (procCase.procurementStage != CPProcurementStageInvoice &&
            procCase.procurementStage != CPProcurementStageReceipt) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:[NSString stringWithFormat:
                                           @"Cannot create invoice: case must be in Receipt or Invoice stage (current: %@).",
                                           _stageNameForStage(procCase.procurementStage)]];
            dispatch_semaphore_signal(sem);
            return;
        }
        if (procCase.procurementStage == CPProcurementStageReceipt) {
            [procCase advanceStage]; // Receipt(4) → Invoice(5)
        }

        // Duplicate check by invoiceNumber within this case
        NSFetchRequest *dupCheck = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        dupCheck.predicate = [NSPredicate predicateWithFormat:
                              @"invoiceNumber == %@ AND caseID == %@", invoiceNumber, caseUUID];
        dupCheck.fetchLimit = 1;
        NSArray *dupArr = [ctx executeFetchRequest:dupCheck error:nil];
        if (dupArr.count > 0) {
            opError = [self errorWithCode:CPProcurementErrorDuplicateInvoice
                              description:[NSString stringWithFormat:@"Invoice number '%@' already exists for this case.", invoiceNumber]];
            dispatch_semaphore_signal(sem);
            return;
        }

        // --- Variance calculation ---
        // Fetch linked PO amount
        NSFetchRequest *poFetch = [NSFetchRequest fetchRequestWithEntityName:@"PurchaseOrder"];
        poFetch.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", caseUUID];
        poFetch.fetchLimit = 1;
        NSArray *pos = [ctx executeFetchRequest:poFetch error:nil];
        NSManagedObject *po = pos.firstObject;
        NSDecimalNumber *poAmount = po ? ([po valueForKey:@"totalAmount"] ?: [NSDecimalNumber zero])
                                      : [NSDecimalNumber zero];

        NSDecimalNumber *rawVariance = [totalAmount decimalNumberBySubtracting:poAmount];
        NSDecimalNumber *varianceAmount = ([rawVariance compare:[NSDecimalNumber zero]] == NSOrderedAscending)
            ? [rawVariance decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]]
            : rawVariance;
        NSDecimalNumber *variancePct    = [NSDecimalNumber zero];
        BOOL varianceFlag = NO;

        if ([poAmount compare:[NSDecimalNumber zero]] != NSOrderedSame) {
            variancePct = [[varianceAmount decimalNumberByDividingBy:poAmount]
                           decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"100"]];
        }

        if ([varianceAmount compare:_varianceAmountThreshold] == NSOrderedDescending ||
            [variancePct    compare:_variancePercentThreshold] == NSOrderedDescending) {
            varianceFlag = YES;
        }

        // Create Invoice
        invoiceUUID = [CPIDGenerator generateUUID];
        NSString *generatedInvNumber = [[CPIDGenerator sharedGenerator] generateInvoiceID];

        NSManagedObject *invoice = [NSEntityDescription insertNewObjectForEntityForName:@"Invoice"
                                                                 inManagedObjectContext:ctx];
        [invoice setValue:invoiceUUID                         forKey:@"uuid"];
        [invoice setValue:caseUUID                            forKey:@"caseID"];
        [invoice setValue:invoiceNumber.length > 0 ? invoiceNumber : generatedInvNumber
                                                              forKey:@"invoiceNumber"];
        [invoice setValue:vendorInvoiceNumber                 forKey:@"vendorInvoiceNumber"];
        [invoice setValue:[NSDate date]                       forKey:@"invoicedAt"];
        [invoice setValue:dueDate                             forKey:@"dueDate"];
        [invoice setValue:totalAmount                         forKey:@"totalAmount"];
        [invoice setValue:taxAmount ?: [NSDecimalNumber zero] forKey:@"taxAmount"];
        [invoice setValue:@"Pending"                          forKey:@"status"];
        [invoice setValue:varianceAmount                      forKey:@"varianceAmount"];
        [invoice setValue:variancePct                         forKey:@"variancePercentage"];
        [invoice setValue:@(varianceFlag)                     forKey:@"varianceFlag"];
        [invoice setValue:[NSDecimalNumber zero]              forKey:@"writeOffAmount"];
        [invoice setValue:procCase                            forKey:@"procurementCase"];

        // Create InvoiceLineItems
        for (NSDictionary *liData in lineItems) {
            NSDecimalNumber *liQty        = liData[@"quantity"]    ?: [NSDecimalNumber zero];
            NSDecimalNumber *liUnitPrice  = liData[@"unitPrice"]   ?: [NSDecimalNumber zero];
            NSDecimalNumber *liTotalPrice = liData[@"totalPrice"]  ?: [liQty decimalNumberByMultiplyingBy:liUnitPrice];
            NSDecimalNumber *liTaxRate    = liData[@"taxRate"]     ?: [NSDecimalNumber zero];

            NSManagedObject *li = [NSEntityDescription insertNewObjectForEntityForName:@"InvoiceLineItem"
                                                                inManagedObjectContext:ctx];
            [li setValue:[CPIDGenerator generateUUID] forKey:@"uuid"];
            [li setValue:invoiceUUID                  forKey:@"invoiceID"];
            [li setValue:liData[@"description"]       forKey:@"description"];
            [li setValue:liQty                        forKey:@"quantity"];
            [li setValue:liUnitPrice                  forKey:@"unitPrice"];
            [li setValue:liTotalPrice                 forKey:@"totalPrice"];
            [li setValue:liTaxRate                    forKey:@"taxRate"];
            [li setValue:invoice                      forKey:@"invoice"];
        }

        procCase.invoiceNumber = invoiceNumber;
        procCase.updatedAt     = [NSDate date];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            NSString *detail = [NSString stringWithFormat:
                                @"InvoiceNumber=%@ Amount=%@ VarianceFlag=%@ (Amount=%@ Pct=%.2f%%)",
                                invoiceNumber, totalAmount, varianceFlag ? @"YES" : @"NO",
                                varianceAmount, variancePct.doubleValue];
            [[CPAuditService sharedService] logAction:@"invoice_created"
                                             resource:@"ProcurementCase"
                                           resourceID:caseUUID
                                               detail:detail];
        } else {
            opError = saveErr;
            invoiceUUID = nil;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return invoiceUUID;
}

#pragma mark - Reconciliation

- (BOOL)reconcileInvoice:(NSString *)invoiceUUID
        reconciledByUUID:(NSString *)userUUID
                   error:(NSError **)error {
    NSParameterAssert(invoiceUUID.length > 0);
    NSParameterAssert(userUUID.length > 0);

    // RBAC: require Procurement.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"procurement.update"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Procurement.update is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"Invoice"
                                       resourceID:invoiceUUID
                                           detail:@"reconcileInvoice denied: insufficient role"];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        // Fetch invoice
        NSManagedObject *invoice = [self _fetchEntityNamed:@"Invoice" uuid:invoiceUUID inContext:ctx];
        if (!invoice) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Invoice not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSString *caseID = [invoice valueForKey:@"caseID"];
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseID inContext:ctx];

        // Three-way match: verify a receipt exists
        NSFetchRequest *receiptFetch = [NSFetchRequest fetchRequestWithEntityName:@"Receipt"];
        receiptFetch.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", caseID];
        receiptFetch.fetchLimit = 1;
        NSArray *receipts = [ctx executeFetchRequest:receiptFetch error:nil];
        if (receipts.count == 0) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:@"Three-way match failed: no receipt found for this procurement case."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Verify invoice amount is within variance threshold vs PO
        NSFetchRequest *poFetch = [NSFetchRequest fetchRequestWithEntityName:@"PurchaseOrder"];
        poFetch.predicate  = [NSPredicate predicateWithFormat:@"caseID == %@", caseID];
        poFetch.fetchLimit = 1;
        NSArray *pos = [ctx executeFetchRequest:poFetch error:nil];
        NSManagedObject *po = pos.firstObject;

        if (po) {
            NSDecimalNumber *poAmount  = [po valueForKey:@"totalAmount"]   ?: [NSDecimalNumber zero];
            NSDecimalNumber *invAmount = [invoice valueForKey:@"totalAmount"] ?: [NSDecimalNumber zero];
            NSDecimalNumber *rawV = [invAmount decimalNumberBySubtracting:poAmount];
            NSDecimalNumber *variance = ([rawV compare:[NSDecimalNumber zero]] == NSOrderedAscending)
                ? [rawV decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]]
                : rawV;
            NSDecimalNumber *variancePct = [NSDecimalNumber zero];
            if ([poAmount compare:[NSDecimalNumber zero]] != NSOrderedSame) {
                variancePct = [[variance decimalNumberByDividingBy:poAmount]
                               decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"100"]];
            }

            if ([variance  compare:_varianceAmountThreshold]  == NSOrderedDescending ||
                [variancePct compare:_variancePercentThreshold] == NSOrderedDescending) {
                opError = [self errorWithCode:CPProcurementErrorVarianceExceeded
                                  description:[NSString stringWithFormat:
                                               @"Invoice variance $%@ (%.2f%%) exceeds thresholds ($%@ / %.1f%%).",
                                               variance, variancePct.doubleValue,
                                               _varianceAmountThreshold, _variancePercentThreshold.doubleValue]];
                dispatch_semaphore_signal(sem);
                return;
            }
        }

        [invoice setValue:@"Reconciled" forKey:@"status"];

        // Accept Invoice stage (auto-advance to Reconciliation first) or Reconciliation stage.
        if (procCase) {
            if (procCase.procurementStage == CPProcurementStageInvoice) {
                [procCase advanceStage]; // Invoice(5) → Reconciliation(6)
            }
            if (procCase.procurementStage == CPProcurementStageReconciliation) {
                [procCase advanceStage]; // Reconciliation(6) → Payment(7)
            }
        }
        if (procCase) {
            procCase.updatedAt = [NSDate date];
        }

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"invoice_reconciled"
                                             resource:@"Invoice"
                                           resourceID:invoiceUUID
                                               detail:[NSString stringWithFormat:@"ReconciledBy=%@", userUUID]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Write-Off

- (BOOL)createWriteOffForInvoice:(NSString *)invoiceUUID
                           amount:(NSDecimalNumber *)amount
                           reason:(NSString *)reason
                     approverUUID:(NSString *)approverUUID
                            error:(NSError **)error {
    NSParameterAssert(invoiceUUID.length > 0);
    NSParameterAssert(amount != nil);
    NSParameterAssert(reason.length > 0);

    // RBAC: require WriteOff.approve permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"writeoff.approve"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorMissingApprover
                                    description:@"Permission denied: WriteOff.approve is required."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"Invoice"
                                       resourceID:invoiceUUID
                                           detail:@"createWriteOff denied: insufficient role"];
        return NO;
    }

    if (!approverUUID.length) {
        if (error) *error = [self errorWithCode:CPProcurementErrorMissingApprover
                                    description:@"Approver UUID is required for write-off."];
        return NO;
    }

    if ([amount compare:[NSDecimalNumber zero]] != NSOrderedDescending) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidAmount
                                    description:@"Write-off amount must be greater than zero."];
        return NO;
    }

    __block BOOL success     = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSManagedObject *invoice = [self _fetchEntityNamed:@"Invoice" uuid:invoiceUUID inContext:ctx];
        if (!invoice) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Invoice not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Sum existing write-offs for this invoice
        NSFetchRequest *woFetch = [NSFetchRequest fetchRequestWithEntityName:@"WriteOff"];
        woFetch.predicate = [NSPredicate predicateWithFormat:@"invoiceID == %@", invoiceUUID];
        NSArray *existingWOs = [ctx executeFetchRequest:woFetch error:nil];
        NSDecimalNumber *existingTotal = [NSDecimalNumber zero];
        for (NSManagedObject *wo in existingWOs) {
            NSDecimalNumber *woAmt = [wo valueForKey:@"amount"] ?: [NSDecimalNumber zero];
            existingTotal = [existingTotal decimalNumberByAdding:woAmt];
        }

        NSDecimalNumber *newTotal = [existingTotal decimalNumberByAdding:amount];
        if ([newTotal compare:_writeOffMaxAmount] == NSOrderedDescending) {
            opError = [self errorWithCode:CPProcurementErrorWriteOffExceeded
                              description:[NSString stringWithFormat:
                                           @"Cumulative write-off $%@ exceeds maximum of $%@.",
                                           newTotal, _writeOffMaxAmount]];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSManagedObject *writeOff = [NSEntityDescription insertNewObjectForEntityForName:@"WriteOff"
                                                                  inManagedObjectContext:ctx];
        [writeOff setValue:[CPIDGenerator generateUUID] forKey:@"uuid"];
        [writeOff setValue:invoiceUUID                  forKey:@"invoiceID"];
        [writeOff setValue:amount                       forKey:@"amount"];
        [writeOff setValue:reason                       forKey:@"reason"];
        [writeOff setValue:approverUUID                 forKey:@"approvedByUserID"];
        [writeOff setValue:[NSDate date]                forKey:@"approvedAt"];
        [writeOff setValue:@"Approved"                  forKey:@"status"];
        [writeOff setValue:invoice                      forKey:@"invoice"];

        // Update invoice.writeOffAmount
        [invoice setValue:newTotal forKey:@"writeOffAmount"];

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            success = YES;
            [[CPAuditService sharedService] logAction:@"write_off_created"
                                             resource:@"Invoice"
                                           resourceID:invoiceUUID
                                               detail:[NSString stringWithFormat:
                                                       @"Amount=%@ Reason=%@ ApprovedBy=%@ CumulativeTotal=%@",
                                                       amount, reason, approverUUID, newTotal]];
        } else {
            opError = saveErr;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Payment

- (nullable NSString *)createPaymentForInvoice:(NSString *)invoiceUUID
                                        amount:(NSDecimalNumber *)amount
                                        method:(NSString *)method
                                         notes:(nullable NSString *)notes
                                         error:(NSError **)error {
    NSParameterAssert(invoiceUUID.length > 0);
    NSParameterAssert(amount != nil);
    NSParameterAssert(method.length > 0);

    // RBAC: require Invoice.approve permission to record payment
    if (![[CPAuthService sharedService] currentUserHasPermission:@"invoice.approve"]) {
        if (error) *error = [self errorWithCode:CPProcurementErrorInvalidStage
                                    description:@"Permission denied: Invoice.approve is required to record payment."];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"Invoice"
                                       resourceID:invoiceUUID
                                           detail:@"createPayment denied: insufficient role"];
        return nil;
    }

    __block NSString *paymentUUID = nil;
    __block NSError *opError      = nil;
    dispatch_semaphore_t sem      = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSManagedObject *invoice = [self _fetchEntityNamed:@"Invoice" uuid:invoiceUUID inContext:ctx];
        if (!invoice) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage description:@"Invoice not found."];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSString *caseID = [invoice valueForKey:@"caseID"];
        CPProcurementCase *procCase = [self _fetchCaseWithUUID:caseID inContext:ctx];

        if (procCase && procCase.procurementStage != CPProcurementStagePayment) {
            opError = [self errorWithCode:CPProcurementErrorInvalidStage
                              description:[NSString stringWithFormat:
                                           @"Cannot create payment: case is not in Payment stage (current: %@).",
                                           _stageNameForStage(procCase.procurementStage)]];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSString *paymentNumber = [[CPIDGenerator sharedGenerator] generatePaymentID];
        paymentUUID = [CPIDGenerator generateUUID];

        NSManagedObject *payment = [NSEntityDescription insertNewObjectForEntityForName:@"Payment"
                                                                 inManagedObjectContext:ctx];
        [payment setValue:paymentUUID    forKey:@"uuid"];
        [payment setValue:caseID         forKey:@"caseID"];
        [payment setValue:invoiceUUID    forKey:@"invoiceID"];
        [payment setValue:paymentNumber  forKey:@"paymentNumber"];
        [payment setValue:amount         forKey:@"amount"];
        [payment setValue:[NSDate date]  forKey:@"paidAt"];
        [payment setValue:method         forKey:@"method"];
        [payment setValue:@"Completed"   forKey:@"status"];
        [payment setValue:notes          forKey:@"notes"];
        if (procCase) {
            [payment setValue:procCase forKey:@"procurementCase"];
        }
        [payment setValue:invoice forKey:@"invoice"];

        // Update invoice status
        [invoice setValue:@"Paid" forKey:@"status"];

        // Advance case to Closed
        if (procCase) {
            [procCase advanceStage]; // → Closed
            procCase.actualAmount = amount;
            procCase.updatedAt    = [NSDate date];
        }

        NSError *saveErr = nil;
        if ([ctx save:&saveErr]) {
            [[CPAuditService sharedService] logAction:@"payment_created"
                                             resource:@"Invoice"
                                           resourceID:invoiceUUID
                                               detail:[NSString stringWithFormat:
                                                       @"PaymentNumber=%@ Amount=%@ Method=%@",
                                                       paymentNumber, amount, method]];
        } else {
            opError = saveErr;
            paymentUUID = nil;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    return paymentUUID;
}

#pragma mark - Queries

- (NSArray *)fetchAllCasesWithStage:(nullable NSString *)stage {
    __block NSArray *results = @[];
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
        if (stage.length > 0) {
            // Map stage name to enum value for stageValue integer comparison
            NSDictionary *stageMap = @{
                @"Draft":          @(CPProcurementStageDraft),
                @"Requisition":    @(CPProcurementStageRequisition),
                @"RFQ":            @(CPProcurementStageRFQ),
                @"PurchaseOrder":  @(CPProcurementStagePO),
                @"Receipt":        @(CPProcurementStageReceipt),
                @"Invoice":        @(CPProcurementStageInvoice),
                @"Reconciliation": @(CPProcurementStageReconciliation),
                @"Payment":        @(CPProcurementStagePayment),
                @"Closed":         @(CPProcurementStageClosed),
            };
            NSNumber *stageNum = stageMap[stage];
            if (stageNum) {
                req.predicate = [NSPredicate predicateWithFormat:@"stageValue == %@", stageNum];
            }
        }
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
        NSError *err = nil;
        results = [ctx executeFetchRequest:req error:&err];
        if (err) {
            NSLog(@"[CPProcurementService] fetchAllCasesWithStage error: %@", err.localizedDescription);
        }
    }];
    return results ?: @[];
}

- (nullable id)fetchCaseWithUUID:(NSString *)uuid {
    if (!uuid.length) return nil;
    __block id result = nil;
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        result = [self _fetchCaseWithUUID:uuid inContext:ctx];
    }];
    return result;
}

- (NSArray *)fetchInvoicesWithVarianceFlag {
    __block NSArray *results = @[];
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        req.predicate = [NSPredicate predicateWithFormat:@"varianceFlag == YES"];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"invoicedAt" ascending:NO]];
        NSError *err = nil;
        results = [ctx executeFetchRequest:req error:&err];
        if (err) {
            NSLog(@"[CPProcurementService] fetchInvoicesWithVarianceFlag error: %@", err.localizedDescription);
        }
    }];
    return results ?: @[];
}

- (NSArray *)generateVendorStatementForVendor:(NSString *)vendorUUID
                                         month:(NSDate *)monthDate {
    NSParameterAssert(vendorUUID.length > 0);
    NSParameterAssert(monthDate != nil);

    // Compute start/end of the given month
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *comps = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth)
                                          fromDate:monthDate];
    NSDate *startOfMonth = [calendar dateFromComponents:comps];
    NSDateComponents *oneMonth = [[NSDateComponents alloc] init];
    oneMonth.month = 1;
    NSDate *startOfNextMonth = [calendar dateByAddingComponents:oneMonth
                                                         toDate:startOfMonth
                                                        options:0];

    __block NSArray *results = @[];
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        // Fetch invoices for vendor cases in the given month
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        // Join through procurement case vendor name — since Vendor UUID is stored on ProcurementCase
        // we do a sub-fetch on ProcurementCase first
        NSFetchRequest *caseFetch = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
        // NOTE: vendorUUID stored as vendorName in simplified schema; support both
        caseFetch.predicate = [NSPredicate predicateWithFormat:
                               @"vendorName == %@", vendorUUID];
        NSError *caseFetchErr = nil;
        NSArray *matchingCases = [ctx executeFetchRequest:caseFetch error:&caseFetchErr];
        NSMutableArray *caseIDs = [NSMutableArray array];
        for (CPProcurementCase *c in matchingCases) {
            if (c.uuid) [caseIDs addObject:c.uuid];
        }

        if (caseIDs.count == 0) {
            results = @[];
            return;
        }

        req.predicate = [NSPredicate predicateWithFormat:
                         @"caseID IN %@ AND invoicedAt >= %@ AND invoicedAt < %@",
                         caseIDs, startOfMonth, startOfNextMonth];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"invoicedAt" ascending:YES]];
        NSError *err = nil;
        NSArray *invoices = [ctx executeFetchRequest:req error:&err];

        // Build a summary array of dictionaries
        NSMutableArray *statement = [NSMutableArray array];
        NSDecimalNumber *totalInvoiced = [NSDecimalNumber zero];
        NSDecimalNumber *totalPaid     = [NSDecimalNumber zero];

        for (NSManagedObject *inv in invoices) {
            NSDecimalNumber *invAmount = [inv valueForKey:@"totalAmount"] ?: [NSDecimalNumber zero];
            NSString *status = [inv valueForKey:@"status"] ?: @"Unknown";
            BOOL isPaid = [status isEqualToString:@"Paid"];

            totalInvoiced = [totalInvoiced decimalNumberByAdding:invAmount];
            if (isPaid) {
                totalPaid = [totalPaid decimalNumberByAdding:invAmount];
            }

            NSDictionary *entry = @{
                @"invoiceUUID":        [inv valueForKey:@"uuid"]              ?: @"",
                @"invoiceNumber":      [inv valueForKey:@"invoiceNumber"]     ?: @"",
                @"vendorInvoiceNumber":[inv valueForKey:@"vendorInvoiceNumber"] ?: @"",
                @"invoicedAt":         [inv valueForKey:@"invoicedAt"]        ?: [NSDate date],
                @"dueDate":            [inv valueForKey:@"dueDate"]           ?: [NSDate date],
                @"totalAmount":        invAmount,
                @"status":             status,
                @"varianceFlag":       [inv valueForKey:@"varianceFlag"]      ?: @NO,
                @"writeOffAmount":     [inv valueForKey:@"writeOffAmount"]    ?: [NSDecimalNumber zero],
            };
            [statement addObject:entry];
        }

        // Append summary row
        [statement addObject:@{
            @"summary":          @YES,
            @"totalInvoiced":    totalInvoiced,
            @"totalPaid":        totalPaid,
            @"totalOutstanding": [totalInvoiced decimalNumberBySubtracting:totalPaid],
            @"invoiceCount":     @(invoices.count),
        }];

        results = [statement copy];
    }];
    return results ?: @[];
}

#pragma mark - Private Helpers

- (nullable NSManagedObject *)_fetchEntityNamed:(NSString *)entityName
                                           uuid:(NSString *)uuid
                                      inContext:(NSManagedObjectContext *)ctx {
    if (!uuid.length) return nil;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:entityName];
    req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
    req.fetchLimit = 1;
    NSError *err = nil;
    NSArray *arr = [ctx executeFetchRequest:req error:&err];
    return arr.firstObject;
}

- (nullable CPProcurementCase *)_fetchCaseWithUUID:(NSString *)uuid
                                         inContext:(NSManagedObjectContext *)ctx {
    if (!uuid.length) return nil;
    NSFetchRequest *req = [CPProcurementCase fetchRequest];
    req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
    req.fetchLimit = 1;
    NSError *err = nil;
    NSArray *arr = [ctx executeFetchRequest:req error:&err];
    return (CPProcurementCase *)arr.firstObject;
}

- (NSError *)errorWithCode:(CPProcurementError)code description:(NSString *)desc {
    return [NSError errorWithDomain:CPProcurementErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: desc}];
}

@end
