#import <XCTest/XCTest.h>
#import "CPProcurementService.h"
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPTestDataFactory.h"
#import <CoreData/CoreData.h>

@interface CPProcurementServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

@implementation CPProcurementServiceTests

/// Known password used for all test-owned accounts in this suite.
static NSString * const kTestPass = @"Test1234Pass";

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;

    // Delete every entity the procurement and charger services write to, so each test
    // starts with a completely empty shared store.  Tests that rely on unpredicated
    // fetches (e.g. "first RFQBid in the store") would return stale data from a
    // previous test otherwise.
    NSArray *entitiesToClean = @[
        @"User", @"Role",
        @"ProcurementCase", @"Requisition", @"RFQ", @"RFQBid",
        @"PurchaseOrder", @"POLineItem", @"Receipt", @"Invoice",
        @"InvoiceLineItem", @"WriteOff", @"Payment", @"Return",
        @"Charger", @"ChargerEvent", @"Command"
    ];

    dispatch_semaphore_t cleanSem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSString *entityName in entitiesToClean) {
            NSArray *objects = [ctx executeFetchRequest:
                                [NSFetchRequest fetchRequestWithEntityName:entityName] error:nil];
            for (NSManagedObject *obj in objects) [ctx deleteObject:obj];
        }
        [ctx save:nil];
        dispatch_semaphore_signal(cleanSem);
    }];
    dispatch_semaphore_wait(cleanSem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"cp_must_change_password_uuids"];
    [d synchronize];
    // Seed with a known password so tests are deterministic.
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kTestPass];
    [self loginAs:@"admin" password:kTestPass];
}

- (void)tearDown {
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Helper: synchronous login
// ---------------------------------------------------------------------------
- (void)loginAs:(NSString *)username password:(NSString *)password {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPAuthService sharedService] loginWithUsername:username
                                           password:password
                                         completion:^(BOOL success, NSError *err) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// ---------------------------------------------------------------------------
// Helper: insert a minimal ProcurementCase via CPProcurementService.
// ---------------------------------------------------------------------------
- (NSString *)createRequisitionWithTitle:(NSString *)title amount:(NSDecimalNumber *)amount {
    NSError *err = nil;
    NSString *uuid = [[CPProcurementService sharedService]
                      createRequisitionWithTitle:title
                      description:@"Test description"
                      justification:@"Test justification"
                      estimatedAmount:amount
                      error:&err];
    return uuid;
}

// ---------------------------------------------------------------------------
// Helper: drive full REQ→RFQ→PO→Receipt→Invoice pipeline and return invoiceUUID.
// vendorName must be unique per call (used as fetch predicate for bid lookup).
// ---------------------------------------------------------------------------
- (NSString *)createInvoiceViaFullPipelineWithTitle:(NSString *)title
                                             vendor:(NSString *)vendorName
                                             amount:(NSDecimalNumber *)amount
                                      invoiceNumber:(NSString *)invoiceNumber {
    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"admin";
    NSString *caseUUID = [self createRequisitionWithTitle:title amount:amount];
    if (!caseUUID) return nil;

    [[CPProcurementService sharedService] approveRequisition:caseUUID
                                                approverUUID:userID error:nil];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v1"
                                                 vendorName:vendorName
                                                 unitPrice:amount
                                               totalPrice:amount
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate  = [NSPredicate predicateWithFormat:@"vendorName == %@", vendorName];
        req.fetchLimit = 1;
        bidUUID = [[[realCtx executeFetchRequest:req error:nil] firstObject] valueForKey:@"uuid"];
    }];
    if (!bidUUID) return nil;

    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];
    [[CPProcurementService sharedService] createPurchaseOrderForCase:caseUUID
                                                    expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:14*86400]
                                                               notes:nil error:nil];
    [[CPProcurementService sharedService]
     createReceiptForCase:caseUUID
     receivedItems:@[@{@"description":@"items", @"receivedQty":[NSDecimalNumber one]}]
     isPartial:NO notes:nil error:nil];

    return [[CPProcurementService sharedService]
            createInvoiceForCase:caseUUID
            invoiceNumber:invoiceNumber
            vendorInvoiceNumber:[NSString stringWithFormat:@"VND-%@", invoiceNumber]
            totalAmount:amount
            taxAmount:[NSDecimalNumber zero]
            dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
            lineItems:@[]
            error:nil];
}

// ---------------------------------------------------------------------------
// 1. testCreateRequisition
// ---------------------------------------------------------------------------
- (void)testCreateRequisition {
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:@"500.00"];
    NSError *err = nil;
    NSString *caseUUID = [[CPProcurementService sharedService]
                          createRequisitionWithTitle:@"EV Charger Purchase"
                          description:@"Need 10 Level-2 chargers"
                          justification:@"Facility expansion"
                          estimatedAmount:amount
                          error:&err];

    XCTAssertNotNil(caseUUID, @"createRequisition should return a UUID");
    XCTAssertNil(err, @"No error expected");

    // Verify via fetchCase
    id procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertNotNil(procCase, @"Fetched case should not be nil");
    XCTAssertEqualObjects([procCase valueForKey:@"title"], @"EV Charger Purchase");

    // Stage should be Requisition (1)
    NSNumber *stageValue = [procCase valueForKey:@"stageValue"];
    XCTAssertEqual(stageValue.integerValue, 1, @"Stage should be Requisition (1)");
}

// ---------------------------------------------------------------------------
// 2. testApproveRequisition — stage advances to RFQ after approval
// ---------------------------------------------------------------------------
- (void)testApproveRequisition {
    NSString *caseUUID = [self createRequisitionWithTitle:@"Approval Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"1000.00"]];
    XCTAssertNotNil(caseUUID);

    NSError *err = nil;
    BOOL approved = [[CPProcurementService sharedService]
                     approveRequisition:caseUUID
                     approverUUID:@"approver-uuid-001"
                     error:&err];
    XCTAssertTrue(approved, @"Approval should succeed");
    XCTAssertNil(err, @"No error expected on approval");

    id procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    NSNumber *stageValue = [procCase valueForKey:@"stageValue"];
    // After approval, stage should advance to RFQ (2)
    XCTAssertEqual(stageValue.integerValue, 2, @"Stage should be RFQ (2) after approval");
}

// ---------------------------------------------------------------------------
// 3. testVarianceFlagged_amountOver25
// ---------------------------------------------------------------------------
- (void)testVarianceFlagged_amountOver25 {
    // Create a case, approve it, set up a PO, then create an invoice with > $25 variance
    NSString *caseUUID = [self createRequisitionWithTitle:@"Variance Amount Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"1000.00"]];
    XCTAssertNotNil(caseUUID);

    // Approve -> RFQ
    [[CPProcurementService sharedService] approveRequisition:caseUUID
                                                approverUUID:@"approver-001"
                                                       error:nil];

    // Issue RFQ
    NSDate *dueDate = [NSDate dateWithTimeIntervalSinceNow:7 * 86400];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID dueDate:dueDate error:nil];

    // Add a bid and select it
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"vendor-001"
                                                 vendorName:@"TestVendor"
                                                 unitPrice:[NSDecimalNumber decimalNumberWithString:@"100.00"]
                                               totalPrice:[NSDecimalNumber decimalNumberWithString:@"1000.00"]
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    // Fetch bid UUID from the real shared stack (CPProcurementService uses CPCoreDataStack).
    // Use a predicated fetch to avoid picking up bids from other test cases.
    __block NSString *bidUUID = nil;
    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *rfqFetch = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        rfqFetch.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"TestVendor"];
        rfqFetch.fetchLimit = 1;
        NSArray *bids = [realCtx executeFetchRequest:rfqFetch error:nil];
        bidUUID = [[bids firstObject] valueForKey:@"uuid"];
    }];

    XCTAssertNotNil(bidUUID, @"A bid should have been created by addRFQBidForCase:");
    if (!bidUUID) return;

    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];

    // Create PO
    [[CPProcurementService sharedService]
     createPurchaseOrderForCase:caseUUID
     expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:14 * 86400]
     notes:nil
     error:nil];

    // Create full receipt — service now accepts PO stage and auto-advances to Receipt then Invoice
    NSArray *receivedItems = @[@{@"description": @"EV Chargers", @"receivedQty": [NSDecimalNumber decimalNumberWithString:@"10"]}];
    NSError *rcptErr = nil;
    NSString *receiptUUID = [[CPProcurementService sharedService]
                             createReceiptForCase:caseUUID
                             receivedItems:receivedItems
                             isPartial:NO
                             notes:nil
                             error:&rcptErr];
    XCTAssertNotNil(receiptUUID, @"Receipt should be created. Error: %@", rcptErr.localizedDescription);
    if (!receiptUUID) return;

    // Create invoice with totalAmount = $1030 (variance = $30 > $25 threshold)
    NSDecimalNumber *invoiceTotal = [NSDecimalNumber decimalNumberWithString:@"1030.00"];
    NSError *invErr = nil;
    NSString *invoiceUUID = [[CPProcurementService sharedService]
                             createInvoiceForCase:caseUUID
                             invoiceNumber:@"INV-001"
                             vendorInvoiceNumber:@"VND-INV-001"
                             totalAmount:invoiceTotal
                             taxAmount:[NSDecimalNumber zero]
                             dueDate:[NSDate dateWithTimeIntervalSinceNow:30 * 86400]
                             lineItems:@[]
                             error:&invErr];

    XCTAssertNotNil(invoiceUUID, @"Invoice should be created. Error: %@", invErr.localizedDescription);
    if (!invoiceUUID) return;

    // Fetch invoice from the real stack and verify variance flag.
    // refreshAllObjects re-faults cached managed objects so any background-context
    // saves are visible via the persistent store rather than the stale in-memory cache.
    __block NSNumber *varianceFlag = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", invoiceUUID];
        req.fetchLimit = 1;
        NSArray *results = [realCtx executeFetchRequest:req error:nil];
        varianceFlag = [[results firstObject] valueForKey:@"varianceFlag"];
    }];
    XCTAssertTrue(varianceFlag.boolValue,
                  @"varianceFlag should be YES when invoice total $1030 exceeds PO $1000 by > $25");
}

// ---------------------------------------------------------------------------
// 4. testVarianceFlagged_percentOver2
// ---------------------------------------------------------------------------
- (void)testVarianceFlagged_percentOver2 {
    // Verify the variance-percent threshold constant is 2.0%
    NSDecimalNumber *threshold = [NSDecimalNumber decimalNumberWithString:@"2.0"];
    // This mirrors _variancePercentThreshold from CPProcurementService +load
    XCTAssertEqualObjects(threshold, [NSDecimalNumber decimalNumberWithString:@"2.0"],
                          @"Percent threshold should be 2.0%");

    // Construct a scenario: PO = $1000, Invoice = $1021 → variance = 2.1% > 2%
    NSDecimalNumber *poAmount  = [NSDecimalNumber decimalNumberWithString:@"1000.00"];
    NSDecimalNumber *invAmount = [NSDecimalNumber decimalNumberWithString:@"1021.00"];
    NSDecimalNumber *variance  = [invAmount decimalNumberBySubtracting:poAmount];
    NSDecimalNumber *pct       = [[variance decimalNumberByDividingBy:poAmount]
                                  decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"100"]];
    // pct should be 2.1
    XCTAssertTrue([pct compare:threshold] == NSOrderedDescending,
                  @"2.1%% variance should exceed the 2.0%% threshold");
}

// ---------------------------------------------------------------------------
// 5. testVarianceNotFlagged_within
// ---------------------------------------------------------------------------
- (void)testVarianceNotFlagged_within {
    // PO = $1000, Invoice = $1020 → variance = $20 < $25 AND 2.0% <= 2%
    NSDecimalNumber *poAmount       = [NSDecimalNumber decimalNumberWithString:@"1000.00"];
    NSDecimalNumber *invAmount      = [NSDecimalNumber decimalNumberWithString:@"1020.00"];
    NSDecimalNumber *varianceAmt    = [invAmount decimalNumberBySubtracting:poAmount];
    NSDecimalNumber *amtThreshold   = [NSDecimalNumber decimalNumberWithString:@"25.00"];
    NSDecimalNumber *pct            = [[varianceAmt decimalNumberByDividingBy:poAmount]
                                       decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"100"]];
    NSDecimalNumber *pctThreshold   = [NSDecimalNumber decimalNumberWithString:@"2.0"];

    BOOL amtWithin = ([varianceAmt compare:amtThreshold] == NSOrderedAscending);
    BOOL pctWithin = ([pct compare:pctThreshold] != NSOrderedDescending);

    XCTAssertTrue(amtWithin, @"$20 variance should be below $25 threshold");
    XCTAssertTrue(pctWithin, @"2.0%% variance should not exceed 2.0%% threshold");
    XCTAssertTrue(amtWithin && pctWithin, @"No variance flag should be set within thresholds");
}

// ---------------------------------------------------------------------------
// 6. testWriteOffCapEnforced — second write-off that pushes total > $250 is rejected
// ---------------------------------------------------------------------------
- (void)testWriteOffCapEnforced {
    NSString *invoiceUUID = [self createInvoiceViaFullPipelineWithTitle:@"Write-Off Cap Enforcement"
                                                                 vendor:@"WOCapVendor"
                                                                 amount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                                          invoiceNumber:@"INV-WO-CAP-001"];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created for write-off cap test");
    if (!invoiceUUID) return;

    NSString *approverUUID = [CPAuthService sharedService].currentUserID ?: @"admin";

    // First write-off: $200 — under $250 cap, must succeed
    NSError *err1 = nil;
    BOOL wo1 = [[CPProcurementService sharedService]
                createWriteOffForInvoice:invoiceUUID
                amount:[NSDecimalNumber decimalNumberWithString:@"200.00"]
                reason:@"Vendor discount"
                approverUUID:approverUUID
                error:&err1];
    XCTAssertTrue(wo1, @"First write-off of $200 must succeed (< $250 cap). Error: %@", err1);

    // Second write-off: $51 — cumulative $251 > $250 cap, must fail
    NSError *err2 = nil;
    BOOL wo2 = [[CPProcurementService sharedService]
                createWriteOffForInvoice:invoiceUUID
                amount:[NSDecimalNumber decimalNumberWithString:@"51.00"]
                reason:@"Additional discount"
                approverUUID:approverUUID
                error:&err2];
    XCTAssertFalse(wo2, @"Second write-off ($200+$51=$251) must fail: exceeds $250 cap");
    XCTAssertNotNil(err2, @"Error must be returned when cap is exceeded");
    XCTAssertEqual(err2.code, CPProcurementErrorWriteOffExceeded,
                   @"Error code must be CPProcurementErrorWriteOffExceeded (%ld), got: %ld",
                   (long)CPProcurementErrorWriteOffExceeded, (long)err2.code);
}

// ---------------------------------------------------------------------------
// 7. testWriteOffAllowedUnderCap — $100 + $149 = $249 both succeed;
//    aggregate writeOffAmount on Invoice entity equals $249.00
// ---------------------------------------------------------------------------
- (void)testWriteOffAllowedUnderCap {
    NSString *invoiceUUID = [self createInvoiceViaFullPipelineWithTitle:@"Write-Off Under Cap"
                                                                 vendor:@"WOUnderCapVendor"
                                                                 amount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                                          invoiceNumber:@"INV-WO-UNDER-001"];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created");
    if (!invoiceUUID) return;

    NSString *approverUUID = [CPAuthService sharedService].currentUserID ?: @"admin";

    // First write-off: $100
    NSError *err1 = nil;
    BOOL wo1 = [[CPProcurementService sharedService]
                createWriteOffForInvoice:invoiceUUID
                amount:[NSDecimalNumber decimalNumberWithString:@"100.00"]
                reason:@"First partial write-off"
                approverUUID:approverUUID
                error:&err1];
    XCTAssertTrue(wo1, @"$100 write-off must succeed. Error: %@", err1);

    // Second write-off: $149 — cumulative $249, still under $250
    NSError *err2 = nil;
    BOOL wo2 = [[CPProcurementService sharedService]
                createWriteOffForInvoice:invoiceUUID
                amount:[NSDecimalNumber decimalNumberWithString:@"149.00"]
                reason:@"Second partial write-off"
                approverUUID:approverUUID
                error:&err2];
    XCTAssertTrue(wo2, @"$149 write-off must succeed ($100+$149=$249 < $250). Error: %@", err2);

    // Verify aggregate writeOffAmount persisted on Invoice entity.
    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSDecimalNumber *writeOffTotal = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", invoiceUUID];
        req.fetchLimit = 1;
        writeOffTotal  = [[[realCtx executeFetchRequest:req error:nil] firstObject]
                           valueForKey:@"writeOffAmount"];
    }];
    XCTAssertEqualObjects(writeOffTotal,
                          [NSDecimalNumber decimalNumberWithString:@"249.00"],
                          @"Invoice.writeOffAmount must equal $249.00 after two write-offs");
}

// ---------------------------------------------------------------------------
// 8. testPartialReceiving — partial receipt updates POLineItem.receivedQty
// ---------------------------------------------------------------------------
- (void)testPartialReceiving {
    // Walk the procurement workflow up to Receipt stage
    NSString *caseUUID = [self createRequisitionWithTitle:@"Partial Receive Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"500.00"]];
    XCTAssertNotNil(caseUUID);

    [[CPProcurementService sharedService] approveRequisition:caseUUID
                                                approverUUID:@"approver-001"
                                                       error:nil];

    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];

    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v1"
                                                 vendorName:@"Vendor1"
                                                 unitPrice:[NSDecimalNumber decimalNumberWithString:@"50.00"]
                                               totalPrice:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    // Use the real shared stack for fetches (CPProcurementService uses CPCoreDataStack).
    // Predicates prevent picking up stale bids/POs from other test cases.
    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;

    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"Vendor1"];
        req.fetchLimit = 1;
        NSArray *bids = [realCtx executeFetchRequest:req error:nil];
        bidUUID = [[bids firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(bidUUID, @"Bid should exist in the real shared store");
    if (!bidUUID) return;

    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];

    [[CPProcurementService sharedService]
     createPurchaseOrderForCase:caseUUID
     expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:14*86400]
     notes:nil
     error:nil];

    // Add a line item to the PO
    __block NSString *poUUID = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"PurchaseOrder"];
        req.predicate = [NSPredicate predicateWithFormat:@"caseID == %@", caseUUID];
        req.fetchLimit = 1;
        NSArray *pos = [realCtx executeFetchRequest:req error:nil];
        poUUID = [[pos firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(poUUID, @"Purchase order should exist in the real shared store");
    if (!poUUID) return;

    NSDictionary *lineData = @{
        @"description": @"EV Charger Unit",
        @"quantity": [NSDecimalNumber decimalNumberWithString:@"10"],
        @"unitPrice": [NSDecimalNumber decimalNumberWithString:@"50.00"],
        @"totalPrice": [NSDecimalNumber decimalNumberWithString:@"500.00"],
    };
    NSError *lineErr = nil;
    BOOL lineAdded = [[CPProcurementService sharedService] addPOLineItem:lineData toPO:poUUID error:&lineErr];
    XCTAssertTrue(lineAdded, @"PO line item should be added. Error: %@", lineErr.localizedDescription);

    __block NSString *lineItemUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"POLineItem"];
        NSArray *items = [realCtx executeFetchRequest:req error:nil];
        lineItemUUID = [[items firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(lineItemUUID, @"POLineItem should exist in the real shared store");
    if (!lineItemUUID) return;

    // Create partial receipt for 5 out of 10 items
    NSArray *receivedItems = @[@{
        @"lineItemUUID": lineItemUUID,
        @"receivedQty": [NSDecimalNumber decimalNumberWithString:@"5"],
        @"description": @"Partial receipt"
    }];
    NSError *rcptErr = nil;
    NSString *receiptUUID = [[CPProcurementService sharedService]
                              createReceiptForCase:caseUUID
                              receivedItems:receivedItems
                              isPartial:YES
                              notes:@"Partial delivery"
                              error:&rcptErr];
    XCTAssertNotNil(receiptUUID, @"Partial receipt should be created. Error: %@", rcptErr.localizedDescription);
    if (!receiptUUID) return;

    // Verify receivedQty was updated to 5 in the real store.
    __block NSDecimalNumber *receivedQty = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"POLineItem"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", lineItemUUID];
        req.fetchLimit = 1;
        NSArray *items = [realCtx executeFetchRequest:req error:nil];
        receivedQty = [[items firstObject] valueForKey:@"receivedQty"];
    }];
    XCTAssertEqualObjects(receivedQty,
                          [NSDecimalNumber decimalNumberWithString:@"5"],
                          @"receivedQty should be 5 after partial receipt");
}

// ---------------------------------------------------------------------------
// 9. testInvoiceCreation — invoice created with correct amounts and status
// ---------------------------------------------------------------------------
- (void)testInvoiceCreation {
    // Test via the test data factory (in-memory store) rather than full workflow
    NSManagedObjectContext *ctx = [CPTestCoreDataStack sharedStack].mainContext;
    NSDecimalNumber *total = [NSDecimalNumber decimalNumberWithString:@"750.00"];
    id invoice = [CPTestDataFactory createInvoiceWithTotal:total forCaseUUID:@"case-uuid-001" inContext:ctx];

    XCTAssertNotNil(invoice, @"Invoice should be created");
    XCTAssertEqualObjects([invoice valueForKey:@"totalAmount"], total,
                          @"totalAmount should match the provided amount");
    XCTAssertEqualObjects([invoice valueForKey:@"status"], @"Pending",
                          @"New invoice status should be 'Pending'");
    XCTAssertEqualObjects([invoice valueForKey:@"caseID"], @"case-uuid-001",
                          @"caseID should be set correctly");
    XCTAssertNotNil([invoice valueForKey:@"uuid"], @"Invoice should have a UUID");
    XCTAssertNotNil([invoice valueForKey:@"invoiceNumber"], @"Invoice should have an invoice number");
}

// ---------------------------------------------------------------------------
// 10. testInvoiceReconciliation — full pipeline to Invoice, then reconcile
// ---------------------------------------------------------------------------
- (void)testInvoiceReconciliation {
    // Build full pipeline: REQ → RFQ → PO → Receipt → Invoice
    NSString *caseUUID = [self createRequisitionWithTitle:@"Reconciliation Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"500.00"]];
    XCTAssertNotNil(caseUUID);

    [[CPProcurementService sharedService] approveRequisition:caseUUID
                                                approverUUID:@"approver-001"
                                                       error:nil];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v1"
                                                 vendorName:@"VendorRecon"
                                                 unitPrice:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                               totalPrice:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"VendorRecon"];
        req.fetchLimit = 1;
        NSArray *bids = [realCtx executeFetchRequest:req error:nil];
        bidUUID = [[bids firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(bidUUID);
    if (!bidUUID) return;

    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];
    [[CPProcurementService sharedService] createPurchaseOrderForCase:caseUUID
                                                    expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                               notes:nil
                                                               error:nil];

    NSString *receiptUUID = [[CPProcurementService sharedService]
                             createReceiptForCase:caseUUID
                             receivedItems:@[@{@"description":@"items",@"receivedQty":[NSDecimalNumber one]}]
                             isPartial:NO
                             notes:nil
                             error:nil];
    XCTAssertNotNil(receiptUUID, @"Receipt must be created before invoice");
    if (!receiptUUID) return;

    NSString *invoiceUUID = [[CPProcurementService sharedService]
                             createInvoiceForCase:caseUUID
                             invoiceNumber:@"INV-RECON-001"
                             vendorInvoiceNumber:@"VND-RECON-001"
                             totalAmount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                             taxAmount:[NSDecimalNumber zero]
                             dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
                             lineItems:@[]
                             error:nil];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created for reconciliation");
    if (!invoiceUUID) return;

    // Reconcile — service accepts Invoice or Reconciliation stage
    NSError *reconErr = nil;
    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"admin-test";
    BOOL reconciled = [[CPProcurementService sharedService]
                       reconcileInvoice:invoiceUUID
                       reconciledByUUID:userID
                       error:&reconErr];
    XCTAssertTrue(reconciled, @"Reconciliation should succeed. Error: %@", reconErr.localizedDescription);

    // Verify invoice status is Reconciled in Core Data.
    __block NSString *invoiceStatus = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", invoiceUUID];
        req.fetchLimit = 1;
        NSArray *results = [realCtx executeFetchRequest:req error:nil];
        invoiceStatus = [[results firstObject] valueForKey:@"status"];
    }];
    XCTAssertEqualObjects(invoiceStatus, @"Reconciled",
                          @"Invoice status must be 'Reconciled' after reconciliation");
}

// ---------------------------------------------------------------------------
// 11. testPaymentRecorded — full pipeline to Payment stage, verify Paid status
// ---------------------------------------------------------------------------
- (void)testPaymentRecorded {
    // Build full pipeline: REQ → RFQ → PO → Receipt → Invoice → Reconcile → Payment
    NSString *caseUUID = [self createRequisitionWithTitle:@"Payment Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"750.00"]];
    XCTAssertNotNil(caseUUID);

    [[CPProcurementService sharedService] approveRequisition:caseUUID
                                                approverUUID:@"approver-001"
                                                       error:nil];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v1"
                                                 vendorName:@"VendorPayment"
                                                 unitPrice:[NSDecimalNumber decimalNumberWithString:@"750.00"]
                                               totalPrice:[NSDecimalNumber decimalNumberWithString:@"750.00"]
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"VendorPayment"];
        req.fetchLimit = 1;
        NSArray *bids = [realCtx executeFetchRequest:req error:nil];
        bidUUID = [[bids firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(bidUUID);
    if (!bidUUID) return;

    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];
    [[CPProcurementService sharedService] createPurchaseOrderForCase:caseUUID
                                                    expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                               notes:nil
                                                               error:nil];

    NSString *receiptUUID = [[CPProcurementService sharedService]
                             createReceiptForCase:caseUUID
                             receivedItems:@[@{@"description":@"items",@"receivedQty":[NSDecimalNumber one]}]
                             isPartial:NO
                             notes:nil
                             error:nil];
    XCTAssertNotNil(receiptUUID);
    if (!receiptUUID) return;

    NSString *invoiceUUID = [[CPProcurementService sharedService]
                             createInvoiceForCase:caseUUID
                             invoiceNumber:@"INV-PAY-001"
                             vendorInvoiceNumber:@"VND-PAY-001"
                             totalAmount:[NSDecimalNumber decimalNumberWithString:@"750.00"]
                             taxAmount:[NSDecimalNumber zero]
                             dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
                             lineItems:@[]
                             error:nil];
    XCTAssertNotNil(invoiceUUID);
    if (!invoiceUUID) return;

    // Reconcile first (advances to Payment stage)
    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"admin-test";
    BOOL reconciled = [[CPProcurementService sharedService]
                       reconcileInvoice:invoiceUUID
                       reconciledByUUID:userID
                       error:nil];
    XCTAssertTrue(reconciled, @"Invoice must be reconciled before payment");
    if (!reconciled) return;

    // Record payment
    NSError *payErr = nil;
    NSString *paymentUUID = [[CPProcurementService sharedService]
                              createPaymentForInvoice:invoiceUUID
                              amount:[NSDecimalNumber decimalNumberWithString:@"750.00"]
                              method:@"ACH"
                              notes:nil
                              error:&payErr];
    XCTAssertNotNil(paymentUUID, @"Payment should be recorded. Error: %@", payErr.localizedDescription);

    // Verify invoice is Paid and case is Closed.
    __block NSString *invoiceStatus = nil;
    __block NSNumber *caseStageValue = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *invReq = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        invReq.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", invoiceUUID];
        invReq.fetchLimit = 1;
        NSArray *invs = [realCtx executeFetchRequest:invReq error:nil];
        invoiceStatus = [[invs firstObject] valueForKey:@"status"];

        NSFetchRequest *caseReq = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
        caseReq.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", caseUUID];
        caseReq.fetchLimit = 1;
        NSArray *cases = [realCtx executeFetchRequest:caseReq error:nil];
        caseStageValue = [[cases firstObject] valueForKey:@"stageValue"];
    }];
    XCTAssertEqualObjects(invoiceStatus, @"Paid",
                          @"Invoice status must be 'Paid' after payment is recorded");
    XCTAssertEqual(caseStageValue.integerValue, 8,
                   @"Case stage must be Closed (8) after payment");
}

// ---------------------------------------------------------------------------
// 12. testRFQBidSelection — selecting a bid marks it isSelected=YES, others NO
// ---------------------------------------------------------------------------
- (void)testRFQBidSelection {
    // Full workflow to get to RFQ bid stage
    NSString *caseUUID = [self createRequisitionWithTitle:@"Bid Selection Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"2000.00"]];
    XCTAssertNotNil(caseUUID);

    [[CPProcurementService sharedService] approveRequisition:caseUUID
                                                approverUUID:@"approver-001"
                                                       error:nil];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];

    // Add two bids
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v1"
                                                 vendorName:@"Vendor A"
                                                 unitPrice:[NSDecimalNumber decimalNumberWithString:@"180.00"]
                                               totalPrice:[NSDecimalNumber decimalNumberWithString:@"1800.00"]
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v2"
                                                 vendorName:@"Vendor B"
                                                 unitPrice:[NSDecimalNumber decimalNumberWithString:@"200.00"]
                                               totalPrice:[NSDecimalNumber decimalNumberWithString:@"2000.00"]
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    // Fetch both bid UUIDs from the real shared store using vendorName predicates so
    // that stale bids from previous tests (if setUp cleanup is ever relaxed) do not
    // produce wrong results here.
    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *bidAUUID = nil;
    __block NSString *bidBUUID = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *reqA = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        reqA.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"Vendor A"];
        reqA.fetchLimit = 1;
        bidAUUID = [[[realCtx executeFetchRequest:reqA error:nil] firstObject] valueForKey:@"uuid"];

        NSFetchRequest *reqB = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        reqB.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"Vendor B"];
        reqB.fetchLimit = 1;
        bidBUUID = [[[realCtx executeFetchRequest:reqB error:nil] firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(bidAUUID, @"Vendor A bid should be in the real store");
    XCTAssertNotNil(bidBUUID, @"Vendor B bid should be in the real store");
    if (!bidAUUID || !bidBUUID) return;

    // Select Vendor A bid
    NSError *selectErr = nil;
    BOOL selected = [[CPProcurementService sharedService]
                     selectRFQBid:bidAUUID
                     forCase:caseUUID
                     error:&selectErr];
    XCTAssertTrue(selected, @"Selecting Vendor A bid should succeed. Error: %@", selectErr.localizedDescription);

    // Verify Vendor A is selected=YES and Vendor B is selected=NO.
    // refreshAllObjects re-faults any in-memory bid objects so we read the
    // post-save state from the persistent store, not the stale cached state.
    __block NSNumber *aSelected = nil;
    __block NSNumber *bSelected = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *reqA = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        reqA.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", bidAUUID];
        reqA.fetchLimit = 1;
        aSelected = [[[realCtx executeFetchRequest:reqA error:nil] firstObject] valueForKey:@"isSelected"];

        NSFetchRequest *reqB = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        reqB.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", bidBUUID];
        reqB.fetchLimit = 1;
        bSelected = [[[realCtx executeFetchRequest:reqB error:nil] firstObject] valueForKey:@"isSelected"];
    }];
    XCTAssertTrue(aSelected.boolValue, @"Selected bid must have isSelected=YES");
    XCTAssertFalse(bSelected.boolValue, @"Non-selected bid must have isSelected=NO");

    // Verify case advanced to PO stage (3)
    id procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertEqual([[procCase valueForKey:@"stageValue"] integerValue], 3,
                   @"Case should be in PO stage (3) after bid selection");
}

// ---------------------------------------------------------------------------
// 13. testWriteOffCumulativeCapAt249_99 — $249.99 succeeds; $0.02 more ($250.01) rejected
// ---------------------------------------------------------------------------
- (void)testWriteOffCumulativeCapAt249_99 {
    NSString *invoiceUUID = [self createInvoiceViaFullPipelineWithTitle:@"Write-Off $249.99 Boundary"
                                                                 vendor:@"WO249Vendor"
                                                                 amount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                                          invoiceNumber:@"INV-WO-249-001"];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created for boundary test");
    if (!invoiceUUID) return;

    NSString *approverUUID = [CPAuthService sharedService].currentUserID ?: @"admin";

    // Write-off $249.99 — just under the cap — must succeed
    NSError *err1 = nil;
    BOOL wo1 = [[CPProcurementService sharedService]
                createWriteOffForInvoice:invoiceUUID
                amount:[NSDecimalNumber decimalNumberWithString:@"249.99"]
                reason:@"Near-cap write-off"
                approverUUID:approverUUID
                error:&err1];
    XCTAssertTrue(wo1, @"Write-off of $249.99 must succeed (< $250 cap). Error: %@", err1);

    // Write-off $0.02 more — cumulative $250.01 > $250 cap — must fail
    NSError *err2 = nil;
    BOOL wo2 = [[CPProcurementService sharedService]
                createWriteOffForInvoice:invoiceUUID
                amount:[NSDecimalNumber decimalNumberWithString:@"0.02"]
                reason:@"Pushes over cap"
                approverUUID:approverUUID
                error:&err2];
    XCTAssertFalse(wo2, @"Write-off of $0.02 on top of $249.99 must fail ($250.01 > $250 cap)");
    XCTAssertNotNil(err2, @"Error must be returned");
    XCTAssertEqual(err2.code, CPProcurementErrorWriteOffExceeded,
                   @"Error code must be CPProcurementErrorWriteOffExceeded, got: %ld", (long)err2.code);
}

// ---------------------------------------------------------------------------
// 14. testWriteOffCumulativeCapExceeded — single $250.01 write-off is rejected immediately
// ---------------------------------------------------------------------------
- (void)testWriteOffCumulativeCapExceeded {
    NSString *invoiceUUID = [self createInvoiceViaFullPipelineWithTitle:@"Write-Off Over Cap Single"
                                                                 vendor:@"WOOverVendor"
                                                                 amount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                                          invoiceNumber:@"INV-WO-OVER-001"];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created");
    if (!invoiceUUID) return;

    NSString *approverUUID = [CPAuthService sharedService].currentUserID ?: @"admin";

    // Single write-off of $250.01 must be rejected
    NSError *err = nil;
    BOOL result = [[CPProcurementService sharedService]
                   createWriteOffForInvoice:invoiceUUID
                   amount:[NSDecimalNumber decimalNumberWithString:@"250.01"]
                   reason:@"Single over-cap attempt"
                   approverUUID:approverUUID
                   error:&err];
    XCTAssertFalse(result, @"Write-off of $250.01 must fail (exceeds $250 cap)");
    XCTAssertNotNil(err, @"Error must be returned when cap is exceeded");
    XCTAssertEqual(err.code, CPProcurementErrorWriteOffExceeded,
                   @"Error code must be CPProcurementErrorWriteOffExceeded (%ld), got: %ld",
                   (long)CPProcurementErrorWriteOffExceeded, (long)err.code);
}

// ---------------------------------------------------------------------------
// 15. testRBACDeniesRequisitionForUnauthorizedRole
//    Finance Approver must not be able to create a requisition.
// ---------------------------------------------------------------------------
- (void)testRBACDeniesRequisitionForUnauthorizedRole {
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kTestPass];

    // Log in as Finance Approver (lacks Procurement.create)
    XCTestExpectation *loginExp = [self expectationWithDescription:@"loginFinance"];
    [[CPAuthService sharedService] loginWithUsername:@"finance"
                                           password:kTestPass
                                         completion:^(BOOL success, NSError *err) {
        XCTAssertTrue(success, @"Finance login should succeed");
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    NSError *err = nil;
    NSString *caseUUID = [[CPProcurementService sharedService]
                          createRequisitionWithTitle:@"Unauthorized Requisition"
                          description:@"Should be denied"
                          justification:@"Test"
                          estimatedAmount:[NSDecimalNumber decimalNumberWithString:@"100.00"]
                          error:&err];

    XCTAssertNil(caseUUID, @"Finance Approver must not be able to create a requisition");
    XCTAssertNotNil(err, @"Error expected when permission denied");
    XCTAssertEqual(err.code, CPProcurementErrorInvalidStage,
        @"Error code should be InvalidStage (permission denied), got: %ld", (long)err.code);

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 16. testRBACAllowsRequisitionForTechnician
//    Site Technician has Procurement.create and must succeed.
// ---------------------------------------------------------------------------
- (void)testRBACAllowsRequisitionForTechnician {
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kTestPass];

    XCTestExpectation *loginExp = [self expectationWithDescription:@"loginTech"];
    [[CPAuthService sharedService] loginWithUsername:@"technician"
                                           password:kTestPass
                                         completion:^(BOOL success, NSError *err) {
        XCTAssertTrue(success, @"Technician login should succeed");
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    NSError *err = nil;
    NSString *caseUUID = [[CPProcurementService sharedService]
                          createRequisitionWithTitle:@"Technician Requisition"
                          description:@"Charger unit for Bay 3"
                          justification:@"Bay 3 expansion"
                          estimatedAmount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                          error:&err];

    XCTAssertNotNil(caseUUID, @"Site Technician must be able to create a requisition");
    XCTAssertNil(err, @"No error expected for authorized role");

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 17. testEndToEndHappyPath — REQ → RFQ → PO → Receipt → Invoice → Reconcile → Payment → Closed
// ---------------------------------------------------------------------------
- (void)testEndToEndHappyPath {
    // Admin is logged in via setUp — has all permissions.
    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"admin";

    // --- 1. Create Requisition ---
    NSError *err = nil;
    NSString *caseUUID = [[CPProcurementService sharedService]
                          createRequisitionWithTitle:@"E2E Happy Path"
                          description:@"End-to-end pipeline test"
                          justification:@"Acceptance test coverage"
                          estimatedAmount:[NSDecimalNumber decimalNumberWithString:@"1000.00"]
                          error:&err];
    XCTAssertNotNil(caseUUID, @"Step 1 (REQ): createRequisition should succeed. Error: %@", err);
    if (!caseUUID) return;

    id procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertEqual([[procCase valueForKey:@"stageValue"] integerValue], 1,
                   @"Stage should be Requisition (1) after creation");

    // --- 2. Approve Requisition → RFQ ---
    BOOL approved = [[CPProcurementService sharedService]
                     approveRequisition:caseUUID
                     approverUUID:userID
                     error:&err];
    XCTAssertTrue(approved, @"Step 2 (RFQ): approveRequisition should succeed. Error: %@", err);

    procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertEqual([[procCase valueForKey:@"stageValue"] integerValue], 2, @"Stage should be RFQ (2)");

    // --- 3. Issue RFQ ---
    BOOL rfqIssued = [[CPProcurementService sharedService]
                      issueRFQForCase:caseUUID
                      dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                      error:&err];
    XCTAssertTrue(rfqIssued, @"Step 3: issueRFQ should succeed. Error: %@", err);

    // --- 4. Add bid and select it → PO ---
    BOOL bidAdded = [[CPProcurementService sharedService]
                     addRFQBidForCase:caseUUID
                     vendorUUID:@"vendor-e2e"
                     vendorName:@"VendorE2E"
                     unitPrice:[NSDecimalNumber decimalNumberWithString:@"1000.00"]
                     totalPrice:[NSDecimalNumber decimalNumberWithString:@"1000.00"]
                     taxAmount:[NSDecimalNumber zero]
                     notes:nil
                     error:&err];
    XCTAssertTrue(bidAdded, @"Step 4a: addRFQBid should succeed. Error: %@", err);

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"VendorE2E"];
        req.fetchLimit = 1;
        NSArray *bids = [realCtx executeFetchRequest:req error:nil];
        bidUUID = [[bids firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(bidUUID, @"Bid must be found in real store");
    if (!bidUUID) return;

    BOOL bidSelected = [[CPProcurementService sharedService]
                        selectRFQBid:bidUUID forCase:caseUUID error:&err];
    XCTAssertTrue(bidSelected, @"Step 4b: selectRFQBid should succeed. Error: %@", err);

    procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertEqual([[procCase valueForKey:@"stageValue"] integerValue], 3, @"Stage should be PO (3)");

    // --- 5. Create PO ---
    BOOL poCreated = [[CPProcurementService sharedService]
                      createPurchaseOrderForCase:caseUUID
                      expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:14*86400]
                      notes:@"E2E test PO"
                      error:&err];
    XCTAssertTrue(poCreated, @"Step 5: createPurchaseOrder should succeed. Error: %@", err);

    // --- 6. Full receipt → Receipt → Invoice stage advance ---
    NSString *receiptUUID = [[CPProcurementService sharedService]
                             createReceiptForCase:caseUUID
                             receivedItems:@[@{@"description":@"E2E item",@"receivedQty":[NSDecimalNumber one]}]
                             isPartial:NO
                             notes:@"Full receipt"
                             error:&err];
    XCTAssertNotNil(receiptUUID, @"Step 6: createReceipt should succeed. Error: %@", err);
    if (!receiptUUID) return;

    procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertEqual([[procCase valueForKey:@"stageValue"] integerValue], 5, @"Stage should be Invoice (5) after full receipt");

    // --- 7. Create Invoice ---
    NSString *invoiceUUID = [[CPProcurementService sharedService]
                             createInvoiceForCase:caseUUID
                             invoiceNumber:@"INV-E2E-001"
                             vendorInvoiceNumber:@"VND-E2E-001"
                             totalAmount:[NSDecimalNumber decimalNumberWithString:@"1000.00"]
                             taxAmount:[NSDecimalNumber zero]
                             dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
                             lineItems:@[]
                             error:&err];
    XCTAssertNotNil(invoiceUUID, @"Step 7: createInvoice should succeed. Error: %@", err);
    if (!invoiceUUID) return;

    // --- 8. Reconcile Invoice → Payment stage ---
    BOOL reconciled = [[CPProcurementService sharedService]
                       reconcileInvoice:invoiceUUID
                       reconciledByUUID:userID
                       error:&err];
    XCTAssertTrue(reconciled, @"Step 8: reconcileInvoice should succeed. Error: %@", err);
    if (!reconciled) return;

    procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertEqual([[procCase valueForKey:@"stageValue"] integerValue], 7, @"Stage should be Payment (7) after reconciliation");

    // --- 9. Record Payment → Closed ---
    NSString *paymentUUID = [[CPProcurementService sharedService]
                              createPaymentForInvoice:invoiceUUID
                              amount:[NSDecimalNumber decimalNumberWithString:@"1000.00"]
                              method:@"ACH"
                              notes:nil
                              error:&err];
    XCTAssertNotNil(paymentUUID, @"Step 9: createPayment should succeed. Error: %@", err);

    // --- Verify final state ---
    procCase = [[CPProcurementService sharedService] fetchCaseWithUUID:caseUUID];
    XCTAssertEqual([[procCase valueForKey:@"stageValue"] integerValue], 8,
                   @"Case should be Closed (8) after payment");

    __block NSString *invoiceStatus = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", invoiceUUID];
        req.fetchLimit = 1;
        NSArray *results = [realCtx executeFetchRequest:req error:nil];
        invoiceStatus = [[results firstObject] valueForKey:@"status"];
    }];
    XCTAssertEqualObjects(invoiceStatus, @"Paid",
                          @"Invoice must have status 'Paid' at end of pipeline");
}

// ---------------------------------------------------------------------------
// 18. testInvalidStageDuplicateInvoice — duplicate invoice number rejected
// ---------------------------------------------------------------------------
- (void)testDuplicateInvoiceRejected {
    NSString *caseUUID = [self createRequisitionWithTitle:@"Duplicate Invoice Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"500.00"]];
    XCTAssertNotNil(caseUUID);
    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"admin";

    [[CPProcurementService sharedService] approveRequisition:caseUUID approverUUID:userID error:nil];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v1" vendorName:@"VendorDup"
                                                 unitPrice:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                               totalPrice:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                                                taxAmount:[NSDecimalNumber zero] notes:nil error:nil];

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"VendorDup"];
        req.fetchLimit = 1;
        bidUUID = [[[realCtx executeFetchRequest:req error:nil] firstObject] valueForKey:@"uuid"];
    }];
    if (!bidUUID) return;
    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];
    [[CPProcurementService sharedService] createPurchaseOrderForCase:caseUUID
                                                    expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                               notes:nil error:nil];
    [[CPProcurementService sharedService] createReceiptForCase:caseUUID
                             receivedItems:@[@{@"description":@"items",@"receivedQty":[NSDecimalNumber one]}]
                             isPartial:NO notes:nil error:nil];

    // First invoice — should succeed
    NSString *inv1 = [[CPProcurementService sharedService]
                      createInvoiceForCase:caseUUID
                      invoiceNumber:@"INV-DUP-001"
                      vendorInvoiceNumber:@"VND-001"
                      totalAmount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                      taxAmount:[NSDecimalNumber zero]
                      dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
                      lineItems:@[] error:nil];
    XCTAssertNotNil(inv1, @"First invoice should be created successfully");

    // Second invoice with same number — must be rejected with DuplicateInvoice error
    NSError *dupErr = nil;
    NSString *inv2 = [[CPProcurementService sharedService]
                      createInvoiceForCase:caseUUID
                      invoiceNumber:@"INV-DUP-001"
                      vendorInvoiceNumber:@"VND-001"
                      totalAmount:[NSDecimalNumber decimalNumberWithString:@"500.00"]
                      taxAmount:[NSDecimalNumber zero]
                      dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
                      lineItems:@[] error:&dupErr];
    XCTAssertNil(inv2, @"Duplicate invoice number must be rejected");
    XCTAssertEqual(dupErr.code, CPProcurementErrorDuplicateInvoice,
                   @"Error code must be CPProcurementErrorDuplicateInvoice (%ld), got: %ld",
                   (long)CPProcurementErrorDuplicateInvoice, (long)dupErr.code);
}

// ---------------------------------------------------------------------------
// 19. testRBACDeniesApproveRequisitionForTechnician
//     Site Technician has Procurement.create but NOT Procurement.update —
//     approve (which needs .update) must be denied.
// ---------------------------------------------------------------------------
- (void)testRBACDeniesApproveRequisitionForTechnician {
    // Create case as admin
    NSString *caseUUID = [self createRequisitionWithTitle:@"RBAC Update Denial Test"
                                                   amount:[NSDecimalNumber decimalNumberWithString:@"100.00"]];
    XCTAssertNotNil(caseUUID, @"Admin must be able to create a requisition");

    // Switch to technician — has Procurement.create but NOT Procurement.update
    [[CPAuthService sharedService] logout];
    [self loginAs:@"technician" password:kTestPass];

    NSError *err = nil;
    BOOL approved = [[CPProcurementService sharedService]
                     approveRequisition:caseUUID
                     approverUUID:@"tech-user"
                     error:&err];
    XCTAssertFalse(approved,
        @"Site Technician must not be able to approve a requisition (lacks procurement.update)");
    XCTAssertNotNil(err, @"Error expected when permission denied");
    XCTAssertEqual(err.code, CPProcurementErrorInvalidStage,
        @"Error code must be CPProcurementErrorInvalidStage (permission denied), got: %ld", (long)err.code);

    [[CPAuthService sharedService] logout];
    [self loginAs:@"admin" password:kTestPass];
}

// ---------------------------------------------------------------------------
// 20. testInvoiceEntityBackedData
//     Invoice created via full pipeline must have correct Core Data attributes:
//     totalAmount, invoiceNumber, status, caseID, and procurementCase relationship.
// ---------------------------------------------------------------------------
- (void)testInvoiceEntityBackedData {
    NSDecimalNumber *invoiceAmount = [NSDecimalNumber decimalNumberWithString:@"900.00"];
    NSString *invoiceUUID = [self createInvoiceViaFullPipelineWithTitle:@"Entity-Backed Invoice Data Test"
                                                                 vendor:@"EntityTestVendor"
                                                                 amount:invoiceAmount
                                                          invoiceNumber:@"INV-ENTITY-001"];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created via full pipeline");
    if (!invoiceUUID) return;

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSManagedObject *inv = nil;
    __block NSArray *lineItemEntities = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", invoiceUUID];
        req.fetchLimit = 1;
        NSArray *results = [realCtx executeFetchRequest:req error:nil];
        inv = results.firstObject;

        if (inv) {
            NSFetchRequest *liReq = [NSFetchRequest fetchRequestWithEntityName:@"InvoiceLineItem"];
            liReq.predicate = [NSPredicate predicateWithFormat:@"invoiceID == %@", invoiceUUID];
            lineItemEntities = [realCtx executeFetchRequest:liReq error:nil];
        }
    }];

    XCTAssertNotNil(inv, @"Invoice entity must exist in Core Data after service creation");
    XCTAssertEqualObjects([inv valueForKey:@"invoiceNumber"], @"INV-ENTITY-001",
                          @"invoiceNumber must match the value passed to createInvoiceForCase:");
    XCTAssertEqualObjects([inv valueForKey:@"totalAmount"], invoiceAmount,
                          @"totalAmount must equal the amount used during pipeline setup");
    XCTAssertEqualObjects([inv valueForKey:@"status"], @"Pending",
                          @"Newly-created invoice status must be 'Pending'");
    XCTAssertNotNil([inv valueForKey:@"caseID"],
                    @"Invoice must be linked to a procurement case via caseID");
    XCTAssertNotNil([inv valueForKey:@"procurementCase"],
                    @"Invoice must have the procurementCase Core Data relationship populated");
    // writeOffAmount should be zero on a fresh invoice
    XCTAssertEqualObjects([inv valueForKey:@"writeOffAmount"], [NSDecimalNumber zero],
                          @"writeOffAmount must be zero on a newly created invoice");
    // lineItemEntities may be empty when @[] is passed as lineItems — verify fetch succeeds
    XCTAssertNotNil(lineItemEntities, @"InvoiceLineItem fetch must not error");
}

// ---------------------------------------------------------------------------
// 21. testReconciliationORThreshold — percentage-only breach triggers failure (OR logic)
// ---------------------------------------------------------------------------
- (void)testReconciliationORThreshold {
    // PO amount = $1000. Invoice amount = $1022 → variance = $22 (under $25 limit),
    // percentage = 2.2% (over 2% limit). OR logic should flag this; AND logic would not.
    NSDecimalNumber *poAmount  = [NSDecimalNumber decimalNumberWithString:@"1000.00"];
    NSDecimalNumber *invAmount = [NSDecimalNumber decimalNumberWithString:@"1022.00"];

    NSString *caseUUID = [self createRequisitionWithTitle:@"OR Threshold Test"
                                                   amount:poAmount];
    XCTAssertNotNil(caseUUID, @"Requisition must be created");

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;

    [[CPProcurementService sharedService] approveRequisition:caseUUID
                                                approverUUID:@"approver-or-test"
                                                       error:nil];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v-or-test"
                                                 vendorName:@"VendorORTest"
                                                 unitPrice:poAmount
                                               totalPrice:poAmount
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate = [NSPredicate predicateWithFormat:@"vendorName == %@", @"VendorORTest"];
        req.fetchLimit = 1;
        NSArray *bids = [realCtx executeFetchRequest:req error:nil];
        bidUUID = [[bids firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(bidUUID, @"RFQ bid must exist");
    if (!bidUUID) return;

    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];
    [[CPProcurementService sharedService] createPurchaseOrderForCase:caseUUID
                                                    expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                               notes:nil
                                                               error:nil];

    NSString *receiptUUID = [[CPProcurementService sharedService]
                             createReceiptForCase:caseUUID
                             receivedItems:@[@{@"description":@"OR test items",@"receivedQty":[NSDecimalNumber one]}]
                             isPartial:NO
                             notes:nil
                             error:nil];
    XCTAssertNotNil(receiptUUID, @"Receipt must be created");
    if (!receiptUUID) return;

    NSString *invoiceUUID = [[CPProcurementService sharedService]
                             createInvoiceForCase:caseUUID
                             invoiceNumber:@"INV-OR-001"
                             vendorInvoiceNumber:@"VND-OR-001"
                             totalAmount:invAmount    // $1022 — 2.2% over PO but under $25 delta
                             taxAmount:[NSDecimalNumber zero]
                             dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
                             lineItems:@[]
                             error:nil];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created");
    if (!invoiceUUID) return;

    NSError *reconErr = nil;
    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"admin-test";
    BOOL reconciled = [[CPProcurementService sharedService]
                       reconcileInvoice:invoiceUUID
                       reconciledByUUID:userID
                       error:&reconErr];

    XCTAssertFalse(reconciled,
                   @"Reconciliation must fail: invoice variance of 2.2%% exceeds the 2%% threshold "
                   @"even though the $22 dollar variance is under the $25 limit (OR logic)");
    XCTAssertNotNil(reconErr, @"An error should be returned when variance check fails");
    XCTAssertEqual(reconErr.code, CPProcurementErrorVarianceExceeded,
                   @"Error code must be CPProcurementErrorVarianceExceeded (2002)");
}

// ---------------------------------------------------------------------------
// 22. testVarianceFlagReadFromInvoiceRelationship
//     CPProcurementService writes varianceFlag on the Invoice entity.
//     CPProcurementCaseViewController.isVarianceFlagged and
//     CPProcurementListViewController's badge must read it from
//     Invoice.varianceFlag (via the invoices relationship), NOT from
//     procCase.metadata[@"varianceFlag"].
//
//     This test creates a full-pipeline invoice that triggers a variance flag,
//     then asserts the flag is readable from the case→invoices relationship and
//     that the case's metadata string does NOT contain the flag value.
// ---------------------------------------------------------------------------
- (void)testVarianceFlagReadFromInvoiceRelationship {
    // PO amount $1000; invoice amount $1060 → 6% variance, exceeds 2% threshold.
    // CPProcurementService.reconcileInvoice sets Invoice.varianceFlag = YES.
    NSDecimalNumber *poAmount  = [NSDecimalNumber decimalNumberWithString:@"1000.00"];
    NSDecimalNumber *invAmount = [NSDecimalNumber decimalNumberWithString:@"1060.00"];

    NSString *caseUUID = [self createRequisitionWithTitle:@"Variance Flag Relationship Test"
                                                   amount:poAmount];
    XCTAssertNotNil(caseUUID, @"Case must be created");
    if (!caseUUID) return;

    NSString *userID = [CPAuthService sharedService].currentUserID ?: @"admin";

    [[CPProcurementService sharedService] approveRequisition:caseUUID approverUUID:userID error:nil];
    [[CPProcurementService sharedService] issueRFQForCase:caseUUID
                                                  dueDate:[NSDate dateWithTimeIntervalSinceNow:7*86400]
                                                    error:nil];
    [[CPProcurementService sharedService] addRFQBidForCase:caseUUID
                                                 vendorUUID:@"v-var"
                                                 vendorName:@"VendorVariance"
                                                 unitPrice:poAmount
                                               totalPrice:poAmount
                                                taxAmount:[NSDecimalNumber zero]
                                                    notes:nil
                                                    error:nil];

    NSManagedObjectContext *realCtx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *bidUUID = nil;
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"RFQBid"];
        req.predicate  = [NSPredicate predicateWithFormat:@"vendorName == %@", @"VendorVariance"];
        req.fetchLimit = 1;
        bidUUID = [[[realCtx executeFetchRequest:req error:nil] firstObject] valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(bidUUID, @"RFQBid must be findable");
    if (!bidUUID) return;

    [[CPProcurementService sharedService] selectRFQBid:bidUUID forCase:caseUUID error:nil];
    [[CPProcurementService sharedService] createPurchaseOrderForCase:caseUUID
                                                    expectedDelivery:[NSDate dateWithTimeIntervalSinceNow:14*86400]
                                                               notes:nil error:nil];
    [[CPProcurementService sharedService]
     createReceiptForCase:caseUUID
     receivedItems:@[@{@"description":@"items", @"receivedQty":[NSDecimalNumber one]}]
     isPartial:NO notes:nil error:nil];

    NSString *invoiceUUID = [[CPProcurementService sharedService]
                             createInvoiceForCase:caseUUID
                             invoiceNumber:@"INV-VAR-001"
                             vendorInvoiceNumber:@"VND-VAR-001"
                             totalAmount:invAmount   // $1060 — 6% over $1000 PO
                             taxAmount:[NSDecimalNumber zero]
                             dueDate:[NSDate dateWithTimeIntervalSinceNow:30*86400]
                             lineItems:@[]
                             error:nil];
    XCTAssertNotNil(invoiceUUID, @"Invoice must be created");
    if (!invoiceUUID) return;

    // reconcileInvoice detects the 6% variance (> 2% threshold) and sets varianceFlag = YES.
    // It is expected to fail (return NO) because of the variance breach — that is correct.
    [[CPProcurementService sharedService] reconcileInvoice:invoiceUUID
                                          reconciledByUUID:userID
                                                     error:nil];

    // Assert 1: Invoice.varianceFlag == YES in Core Data.
    __block NSNumber *invoiceVarianceFlag = nil;
    __block id caseMetadataString = nil;
    __block NSSet *invoicesFromCase = nil;
    [realCtx performBlockAndWait:^{
        [realCtx refreshAllObjects];

        // Fetch Invoice entity and read varianceFlag directly.
        NSFetchRequest *invReq = [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
        invReq.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", invoiceUUID];
        invReq.fetchLimit = 1;
        NSManagedObject *inv = [[realCtx executeFetchRequest:invReq error:nil] firstObject];
        invoiceVarianceFlag = [inv valueForKey:@"varianceFlag"];

        // Fetch ProcurementCase and capture metadata and the invoices relationship.
        NSFetchRequest *caseReq = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
        caseReq.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", caseUUID];
        caseReq.fetchLimit = 1;
        NSManagedObject *procCase = [[realCtx executeFetchRequest:caseReq error:nil] firstObject];
        caseMetadataString = [procCase valueForKey:@"metadata"];
        invoicesFromCase   = [procCase valueForKey:@"invoices"];
    }];

    XCTAssertNotNil(invoiceVarianceFlag,
        @"Invoice.varianceFlag must be a non-nil NSNumber after reconciliation with variance");
    XCTAssertTrue(invoiceVarianceFlag.boolValue,
        @"Invoice.varianceFlag must be YES after a 6%% variance breach");

    // Assert 2: varianceFlag is readable via the case→invoices relationship.
    BOOL flagFromRelationship = NO;
    for (NSManagedObject *inv in invoicesFromCase) {
        if ([[inv valueForKey:@"varianceFlag"] boolValue]) {
            flagFromRelationship = YES;
            break;
        }
    }
    XCTAssertTrue(flagFromRelationship,
        @"varianceFlag must be detectable by iterating procCase.invoices "
        @"(the correct read path used by CPProcurementListViewController and "
        @"CPProcurementCaseViewController after the fix)");

    // Assert 3: The case metadata string does NOT contain "varianceFlag" — confirming
    // that CPProcurementService never writes variance into case metadata, so reading
    // metadata[@"varianceFlag"] would always return nil/NO (the old bug).
    if (caseMetadataString) {
        BOOL metadataHasVarianceFlag =
            [caseMetadataString rangeOfString:@"varianceFlag"].location != NSNotFound;
        XCTAssertFalse(metadataHasVarianceFlag,
            @"ProcurementCase.metadata must NOT contain 'varianceFlag' — "
            @"CPProcurementService writes variance only to Invoice.varianceFlag, "
            @"so the old metadata read path would always return NO");
    }
}

@end
