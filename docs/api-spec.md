# ChargeProcure Field Operations — Internal Service Layer API Specification

> **Important:** ChargeProcure Field Operations has no network API, no HTTP endpoints, and no remote server. This document specifies the **on-device service layer API** — Objective-C method signatures, data transfer objects (DTOs), behavioral contracts, and error codes governing communication between UIKit view controllers and the on-device service layer.

---

## 1. Conventions

### 1.1 Async Write Pattern
All mutation methods follow this signature convention:
```objc
- (void)<verb><Entity>:(DTO *)dto
              completion:(void(^)(ResultType _Nullable result, NSError * _Nullable error))completion;
```
Completion blocks are always called on the **main queue**.

### 1.2 Sync Read Pattern
Read-only queries return `NSFetchRequest *` for `NSFetchedResultsController` binding, or return domain objects directly if called on the view context.

### 1.3 Error Domain
```objc
extern NSString *const CPErrorDomain; // "com.chargeprocure.error"
```

### 1.4 Common DTO Pattern
All input DTOs are plain Objective-C objects with `@property` fields. They carry no Core Data managed objects; service layer converts DTOs to/from entities.

---

## 2. Authentication Service (CPAuthService)

### 2.1 Methods

#### Register User
```objc
- (void)registerWithUsername:(NSString *)username
                    password:(NSString *)password
                        role:(CPRoleType)role
                  completion:(void(^)(CPUserDTO * _Nullable user,
                                      NSError * _Nullable error))completion;
```
- Validates password (≥10 chars, ≥1 digit); returns `CPErrorPasswordTooShort` or `CPErrorPasswordNoDigit` on failure.
- Generates 16-byte salt; stores SHA-256(salt || password) hash.
- Writes `AuditEvent(eventType=userCreated)`.

#### Login
```objc
- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(void(^)(CPUserDTO * _Nullable user,
                                   NSError * _Nullable error))completion;
```
- Returns `CPErrorLockoutActive` (userInfo key `CPRemainingLockoutSecondsKey`) if locked.
- Returns `CPErrorInvalidCredentials` on hash mismatch; increments `failedAttempts`.
- On 5th failure: sets `lockoutUntil = now + 900s`.
- On success: resets `failedAttempts = 0`; writes `AuditEvent(loginSuccess)`.

#### Logout
```objc
- (void)logoutWithCompletion:(void(^)(NSError * _Nullable error))completion;
```
- Clears in-memory session; writes `AuditEvent(logout)`.

#### Change Password
```objc
- (void)changePasswordForUserId:(NSUUID *)userId
                    oldPassword:(NSString *)oldPassword
                    newPassword:(NSString *)newPassword
                     completion:(void(^)(NSError * _Nullable error))completion;
```
- Validates old password matches; validates new password policy.

#### Validate Password Policy
```objc
- (BOOL)validatePassword:(NSString *)password error:(NSError **)error;
```
- Synchronous; returns YES if valid.

---

## 3. Biometric Service (CPBiometricService)

### 3.1 Methods

#### Check Availability
```objc
- (BOOL)isBiometricAvailable;
- (CPBiometricType)biometricType; // CPBiometricTypeFaceID / CPBiometricTypeTouchID / CPBiometricTypeNone
```

#### Authenticate
```objc
- (void)authenticateWithReason:(NSString *)reason
                    completion:(void(^)(BOOL success, NSError * _Nullable error))completion;
```
- Uses `LAContext` with `LAPolicyDeviceOwnerAuthenticationWithBiometrics`.
- Writes `AuditEvent(biometricSuccess/biometricFail)`.
- Does NOT increment password fail counter.

---

## 4. RBAC Service (CPRBACService)

### 4.1 Methods

#### Permission Check
```objc
- (BOOL)userWithId:(NSUUID *)userId
   canPerformAction:(CPPermissionAction)action
        onResource:(CPPermissionResource)resource;
```
- Synchronous (uses in-memory permission cache).
- Cache invalidated by `CPPermissionChangedNotification`.

#### Grant Permission
```objc
- (void)grantAction:(CPPermissionAction)action
         onResource:(CPPermissionResource)resource
             toRole:(NSUUID *)roleId
        requestedBy:(NSUUID *)actorUserId
         completion:(void(^)(NSError * _Nullable error))completion;
```
- Creates/updates `Permission` entity.
- Writes `AuditEvent(permissionChange, oldValue=denied, newValue=granted)`.
- Posts `CPPermissionChangedNotification`.

#### Revoke Permission
```objc
- (void)revokeAction:(CPPermissionAction)action
          onResource:(CPPermissionResource)resource
              fromRole:(NSUUID *)roleId
         requestedBy:(NSUUID *)actorUserId
          completion:(void(^)(NSError * _Nullable error))completion;
```

### 4.2 Enums

```objc
typedef NS_ENUM(NSInteger, CPPermissionAction) {
    CPActionCreate,
    CPActionRead,
    CPActionUpdate,
    CPActionDelete,
    CPActionApprove,
    CPActionCommand
};

typedef NS_ENUM(NSInteger, CPPermissionResource) {
    CPResourceCharger,
    CPResourceBulletin,
    CPResourceRequisition,
    CPResourceRFQ,
    CPResourcePurchaseOrder,
    CPResourceReceipt,
    CPResourceReturn,
    CPResourceInvoice,
    CPResourcePayment,
    CPResourceWriteOff,
    CPResourcePricingRule,
    CPResourceAuditLog,
    CPResourceUser,
    CPResourceRole
};
```

---

## 5. Procurement Services

### 5.1 CPRequisitionService

#### Create Requisition
```objc
- (void)createRequisition:(CPRequisitionCreateDTO *)dto
               completion:(void(^)(CPRequisitionDTO * _Nullable result,
                                   NSError * _Nullable error))completion;
```

**CPRequisitionCreateDTO:**
```objc
@property NSString *title;              // required
@property NSString *description;        // optional
@property NSUUID   *vendorId;           // optional at creation
@property NSDecimalNumber *estimatedAmount; // optional
@property CPPriority priority;          // required: low/medium/high/urgent
@property NSDate   *requestedByDate;    // optional
@property NSArray<NSUUID *> *attachmentIds; // pre-uploaded attachments
```

#### Submit Requisition
```objc
- (void)submitRequisitionWithId:(NSUUID *)requisitionId
                    requestedBy:(NSUUID *)userId
                     completion:(void(^)(NSError *))completion;
```
- Transitions Draft → Submitted.
- Returns `CPErrorPermissionDenied` if user lacks `CPActionCreate` on `CPResourceRequisition`.

#### Approve / Reject
```objc
- (void)approveRequisitionWithId:(NSUUID *)requisitionId
                     approvedBy:(NSUUID *)userId
                      completion:(void(^)(NSError *))completion;

- (void)rejectRequisitionWithId:(NSUUID *)requisitionId
                         reason:(NSString *)reason
                     rejectedBy:(NSUUID *)userId
                      completion:(void(^)(NSError *))completion;
```

---

### 5.2 CPRFQService

#### Create RFQ
```objc
- (void)createRFQForRequisitionId:(NSUUID *)requisitionId
                       completion:(void(^)(CPRFQDTO *, NSError *))completion;
```

#### Add Bid
```objc
- (void)addBid:(CPRFQBidCreateDTO *)dto
         toRFQ:(NSUUID *)rfqId
     completion:(void(^)(CPRFQBidDTO *, NSError *))completion;
```

**CPRFQBidCreateDTO:**
```objc
@property NSUUID   *vendorId;
@property NSDecimalNumber *totalBidAmount;
@property NSDate   *validUntil;
@property NSString *notes;
@property NSArray<CPRFQBidLineItemDTO *> *lineItems;
```

#### Select Bid
```objc
- (void)selectBid:(NSUUID *)bidId
          forRFQ:(NSUUID *)rfqId
       selectedBy:(NSUUID *)userId
       completion:(void(^)(NSError *))completion;
```
- Transitions RFQ status to `selected`; populates PO draft fields from bid.

---

### 5.3 CPPurchaseOrderService

#### Create PO from RFQ
```objc
- (void)createPurchaseOrderFromRFQBid:(NSUUID *)bidId
                          createdBy:(NSUUID *)userId
                          completion:(void(^)(CPPurchaseOrderDTO *, NSError *))completion;
```

#### Issue PO
```objc
- (void)issuePurchaseOrderWithId:(NSUUID *)poId
                       issuedBy:(NSUUID *)userId
                      completion:(void(^)(NSError *))completion;
```

#### Fetch PO with Totals
```objc
- (CPPurchaseOrderDTO *)purchaseOrderById:(NSUUID *)poId; // sync, viewContext
```

**CPPurchaseOrderDTO:**
```objc
@property NSUUID   *poId;
@property NSString *poNumber;
@property NSString *status;
@property NSArray<CPPOLineItemDTO *> *lineItems;
@property NSDecimalNumber *subtotal;      // computed
@property NSDecimalNumber *taxTotal;      // computed
@property NSDecimalNumber *grandTotal;    // computed
```

---

### 5.4 CPReceiptService

#### Log Receipt
```objc
- (void)logReceipt:(CPReceiptCreateDTO *)dto
        completion:(void(^)(CPReceiptDTO *, NSError *))completion;
```

**CPReceiptCreateDTO:**
```objc
@property NSUUID   *poLineId;
@property NSDecimalNumber *quantityReceived;  // must be > 0 and ≤ remaining qty
@property NSDate   *receivedAt;
@property NSUUID   *receivedByUserId;
@property NSString *conditionNotes;
```

#### Log Return
```objc
- (void)logReturn:(CPReturnCreateDTO *)dto
       completion:(void(^)(CPReturnDTO *, NSError *))completion;
```

#### Running Totals
```objc
- (NSDecimalNumber *)totalReceivedForPOLine:(NSUUID *)poLineId; // sync
- (NSDecimalNumber *)totalReturnedForPOLine:(NSUUID *)poLineId; // sync
```

---

### 5.5 CPInvoiceService

#### Create Invoice
```objc
- (void)createInvoice:(CPInvoiceCreateDTO *)dto
           completion:(void(^)(CPInvoiceDTO *, NSError *))completion;
```

**CPInvoiceCreateDTO:**
```objc
@property NSUUID   *procurementCaseId;
@property NSUUID   *vendorId;
@property NSString *invoiceNumber;       // unique per vendor; service validates
@property NSDate   *invoiceDate;
@property NSDate   *dueDate;
@property NSArray<CPInvoiceLineItemDTO *> *lineItems;
@property NSArray<NSUUID *> *attachmentIds;
```

#### Detect Variances
```objc
- (NSArray<CPVarianceFlag *> *)detectVariancesForInvoice:(NSUUID *)invoiceId
                                                  againstPO:(NSUUID *)poId;
```
- Called internally after invoice creation.
- Flag threshold: |diff| > $25.00 OR |diff|/POAmount > 0.02.

#### Sign Off Variance
```objc
- (void)signOffVarianceForInvoice:(NSUUID *)invoiceId
                          comment:(NSString *)comment
                       signedOffBy:(NSUUID *)userId
                        completion:(void(^)(NSError *))completion;
```
- Requires `CPActionApprove` on `CPResourceInvoice`.
- Transitions status: Flagged → Approved (ready for reconciliation).

#### Submit Write-Off
```objc
- (void)submitWriteOff:(CPWriteOffCreateDTO *)dto
            completion:(void(^)(NSError *))completion;
```

**CPWriteOffCreateDTO:**
```objc
@property NSUUID   *invoiceId;
@property NSDecimalNumber *amount;    // validated ≤ 250.00
@property NSString *note;            // validated ≥ 20 chars
@property NSUUID   *approverUserId;  // re-auth must occur before calling
```

---

### 5.6 CPReconciliationService

#### Reconcile Invoice
```objc
- (void)reconcileInvoice:(NSUUID *)invoiceId
              completion:(void(^)(CPReconciliationReportDTO *, NSError *))completion;
```

**CPReconciliationReportDTO:**
```objc
@property NSArray<CPReconciliationLineDTO *> *lines;
@property BOOL allLinesMatched;
@property BOOL hasUnresolvedVariances;
```

**CPReconciliationLineDTO:**
```objc
@property NSString *itemDescription;
@property NSDecimalNumber *poQuantity;
@property NSDecimalNumber *receivedQuantity;
@property NSDecimalNumber *invoicedQuantity;
@property NSDecimalNumber *priceVarianceAmount;
@property NSDecimalNumber *taxVarianceAmount;
@property CPReconciliationStatus lineStatus; // matched/partial/overInvoiced/underReceived/varianceFlagged
```

---

### 5.7 CPPaymentService

#### Record Payment
```objc
- (void)recordPayment:(CPPaymentCreateDTO *)dto
           completion:(void(^)(CPPaymentDTO *, NSError *))completion;
```

**CPPaymentCreateDTO:**
```objc
@property NSUUID   *invoiceId;
@property NSDate   *paymentDate;
@property CPPaymentMethod paymentMethod; // check/ACH/wire/other
@property NSString *referenceNumber;
@property NSDecimalNumber *amountPaid;  // validated > 0 and ≤ openBalance
@property NSUUID   *recordedByUserId;
```

---

### 5.8 CPStatementService

#### Generate Vendor Statement
```objc
- (void)generateStatementForVendorId:(NSUUID *)vendorId
                               month:(NSInteger)month
                                year:(NSInteger)year
                           completion:(void(^)(CPVendorStatementDTO *, NSError *))completion;
```

**CPVendorStatementDTO:**
```objc
@property CPVendorDTO *vendor;
@property NSInteger month;
@property NSInteger year;
@property NSArray<CPInvoiceDTO *> *invoices;
@property NSArray<CPPaymentDTO *> *payments;
@property NSDecimalNumber *openBalance;
```

#### Export Statement
```objc
- (void)exportStatement:(CPVendorStatementDTO *)statement
                 format:(CPExportFormat)format // CPExportFormatCSV / CPExportFormatPDF
             completion:(void(^)(NSURL * _Nullable fileURL, NSError *))completion;
```

---

## 6. Charger Services

### 6.1 CPChargerService

#### Start / Stop Polling
```objc
- (void)startPollingChargerId:(NSString *)chargerId;
- (void)stopPollingChargerId:(NSString *)chargerId;
- (void)stopAllPolling;
```

#### Force Status Refresh
```objc
- (void)refreshStatusForChargerId:(NSString *)chargerId
                       completion:(void(^)(CPChargerStatus status, NSError *))completion;
```

#### Fetch Request (for NSFetchedResultsController)
```objc
- (NSFetchRequest *)fetchRequestForAllChargersSortedByStatus;
```

---

### 6.2 CPCommandService

#### Send Command
```objc
- (void)sendCommand:(CPCommandType)commandType
          toCharger:(NSString *)chargerId
       initiatedBy:(NSUUID *)userId
         parameters:(NSDictionary * _Nullable)parameters
         completion:(void(^)(CPCommandDTO * _Nullable result, NSError *))completion;
```

**CPCommandType:**
```objc
typedef NS_ENUM(NSInteger, CPCommandType) {
    CPCommandRemoteStart,
    CPCommandRemoteStop,
    CPCommandSoftReset,
    CPCommandParameterPush
};
```

**Behavioral contract:**
- Creates `Command` entity (status=Pending) synchronously before calling vendor SDK.
- Starts 8-second `NSTimer`; if timer fires before SDK completion: status=PendingReview.
- On SDK success: status=Acknowledged, ackedAt=now.
- On SDK error (before 8s): status=Failed; enqueues retry if retryCount < 3.

#### Retry Queue
```objc
- (void)enqueueRetryForCommandId:(NSUUID *)commandId;
```
- Increments retryCount; schedules `BGProcessingTask` with delay 8^retryCount seconds.
- If retryCount ≥ 3: sets status=PendingReview, fires local notification, writes AuditEvent.

---

## 7. Bulletin Service (CPBulletinService)

### 7.1 Methods

#### Create Draft
```objc
- (void)createDraftBulletin:(CPBulletinCreateDTO *)dto
                 completion:(void(^)(CPBulletinDTO *, NSError *))completion;
```

#### Schedule Autosave
```objc
- (void)scheduleAutosaveForBulletinId:(NSUUID *)bulletinId
                                draft:(CPBulletinDraftDTO *)draft;
```
- Debounced: cancels previous timer, schedules new 10-second timer.
- On fire: writes to Core Data background context, posts `CPBulletinAutosaveDidCompleteNotification`.

#### Save Draft (Immediate)
```objc
- (void)saveDraftBulletinId:(NSUUID *)bulletinId
                      draft:(CPBulletinDraftDTO *)draft
                 completion:(void(^)(NSError *))completion;
```

#### Publish
```objc
- (void)publishBulletinId:(NSUUID *)bulletinId
              publishedBy:(NSUUID *)userId
               completion:(void(^)(NSError *))completion;
```
- Validates: title non-empty, summary ≤ 280 chars.
- Sets status=published, publishedAt=now.
- Creates `BulletinVersion` snapshot.
- Writes `AuditEvent(bulletinPublished)`.

#### Restore Version
```objc
- (void)restoreVersionId:(NSUUID *)versionId
              asDraftBy:(NSUUID *)userId
             completion:(void(^)(CPBulletinDTO *, NSError *))completion;
```
- Creates new `Bulletin` draft with version data; does not modify existing published bulletin.

**CPBulletinDraftDTO:**
```objc
@property NSString *title;
@property NSString *bodyContent;
@property CPBodyFormat bodyFormat; // CPBodyFormatMarkdown / CPBodyFormatWYSIWYG
@property NSString *summary;       // max 280 chars
@property NSString *coverImagePath; // relative sandbox path
@property NSInteger recommendationWeight; // 0–100
@property NSDate   *scheduledPublishAt;
@property NSDate   *scheduledUnpublishAt;
@property BOOL     isPinned;
```

---

## 8. Pricing Rule Service (CPPricingRuleService)

### 8.1 Methods

#### Create Rule
```objc
- (void)createPricingRule:(CPPricingRuleCreateDTO *)dto
               createdBy:(NSUUID *)userId
               completion:(void(^)(CPPricingRuleDTO *, NSError *))completion;
```

#### Create New Version
```objc
- (void)createNewVersionOfRuleId:(NSUUID *)existingRuleId
                         updates:(CPPricingRuleCreateDTO *)updates
                       createdBy:(NSUUID *)userId
                       completion:(void(^)(CPPricingRuleDTO *, NSError *))completion;
```
- Sets `existingRule.effectiveEnd = now`.
- Creates new rule with `effectiveStart = now`, `effectiveEnd = nil`.
- Links both to same `ruleGroupId`.

#### Active Rule Lookup
```objc
- (CPPricingRuleDTO * _Nullable)activeRuleForServiceType:(CPServiceType)serviceType
                                             vehicleClass:(CPVehicleClass)vehicleClass
                                                  storeId:(NSString * _Nullable)storeId
                                              timeOfDay:(NSDate *)time
                                         rentalDurationHours:(NSInteger)hours;
```
- Synchronous; returns nil if no rule matches.

#### Version History
```objc
- (NSArray<CPPricingRuleDTO *> *)versionHistoryForRuleGroupId:(NSUUID *)ruleGroupId;
```

**CPPricingRuleCreateDTO:**
```objc
@property CPServiceType serviceType;
@property CPVehicleClass vehicleClass;  // nil = all classes
@property NSString *storeId;            // nil = all stores
@property NSString *timeWindowStart;    // HH:mm or nil
@property NSString *timeWindowEnd;      // HH:mm or nil
@property NSInteger rentalDurationMinHours;
@property NSInteger rentalDurationMaxHours;
@property NSDecimalNumber *basePrice;
@property NSDecimalNumber *tierMultiplier; // default 1.0
@property NSDate   *effectiveStart;
@property NSDate   *effectiveEnd;       // nil = open-ended
```

---

## 9. Analytics Services

### 9.1 CPStreakCalculator
```objc
- (NSInteger)consecutiveDayStreakForWorkflowType:(CPWorkflowType)workflowType
                                           userId:(NSUUID * _Nullable)userId;
```

### 9.2 CPTrendService
```objc
- (void)dailyTrendForWorkflowType:(CPWorkflowType)type
                           period:(CPTrendPeriod)period
                       completion:(void(^)(NSArray<CPDataPointDTO *> *, NSError *))completion;
```
- Runs on background NSOperationQueue.

**CPDataPointDTO:**
```objc
@property NSDate *date;
@property double value;
```

### 9.3 CPHeatmapService
```objc
- (void)hourDayHeatmapForChargerEvents:(NSString * _Nullable)chargerId
                            completion:(void(^)(CPHeatmapDataDTO *, NSError *))completion;
```

**CPHeatmapDataDTO:**
```objc
@property NSArray<NSArray<NSNumber *> *> *grid; // [day][hour] = count; day 0=Sunday
@property NSInteger maxValue;
```

### 9.4 CPAnomalyDetector
```objc
- (void)detectAnomaliesForChargerId:(NSString *)chargerId
                         completion:(void(^)(NSArray<CPAnomalyFlagDTO *> *, NSError *))completion;
```

**CPAnomalyFlagDTO:**
```objc
@property CPAnomalyType type;       // CPAnomalyGap / CPAnomalyVolatility
@property NSString *chargerId;
@property NSDate   *detectedAt;
@property double   observedValue;
@property double   threshold;
@property NSString *description;
```

---

## 10. Export Service (CPExportService)

### 10.1 Methods

#### Export to CSV
```objc
- (void)exportToCSVWithColumns:(NSArray<NSString *> *)columns
                          rows:(NSArray<NSArray *> *)rows
                      filename:(NSString *)filename
                    completion:(void(^)(NSURL * _Nullable fileURL, NSError *))completion;
```

#### Export to PDF
```objc
- (void)exportToPDFWithTitle:(NSString *)title
                    sections:(NSArray<CPPDFSectionDTO *> *)sections
                    filename:(NSString *)filename
                  completion:(void(^)(NSURL * _Nullable fileURL, NSError *))completion;
```

#### Present Share Sheet
```objc
- (void)presentShareSheetForFileURL:(NSURL *)fileURL
                 fromViewController:(UIViewController *)presentingVC;
```
- Uses `UIActivityViewController`; no network upload.

---

## 11. Audit Service (CPAuditService)

### 11.1 Methods

#### Create Event (internal use only)
```objc
- (void)createAuditEvent:(CPAuditEventCreateDTO *)dto
              completion:(void(^)(NSError *))completion;
```
- Only callable from service layer; not exposed to view controllers.

#### Fetch Events (paginated)
```objc
- (NSFetchRequest *)fetchRequestForEventsWithUserId:(NSUUID * _Nullable)userId
                                          eventType:(NSString * _Nullable)eventType
                                          startDate:(NSDate * _Nullable)startDate
                                            endDate:(NSDate * _Nullable)endDate
                                           resource:(NSString * _Nullable)resource;
```
- Returns `NSFetchRequest` configured for `NSFetchedResultsController` with `fetchBatchSize=50`.

#### Export Audit Log
```objc
- (void)exportAuditEventsMatchingPredicate:(NSPredicate *)predicate
                                    format:(CPExportFormat)format
                                completion:(void(^)(NSURL *, NSError *))completion;
```

---

## 12. Cleanup Service (CPCleanupService)

```objc
- (void)runWeeklyCleanupWithCompletion:(void(^)(NSInteger deletedCount, NSError *))completion;
```
- Deletes: drafts (status=draft, isPinned=NO, createdAt < now-90d) + orphaned sandbox files.
- Writes `AuditEvent(cleanupCompleted)`.

---

## 13. Error Codes Reference

```objc
typedef NS_ENUM(NSInteger, CPErrorCode) {
    // Authentication (1xxx)
    CPErrorInvalidCredentials       = 1001,
    CPErrorLockoutActive            = 1002,
    CPErrorPasswordTooShort         = 1003,
    CPErrorPasswordNoDigit          = 1004,
    CPErrorUserNotFound             = 1005,

    // File/Attachment (2xxx)
    CPErrorAttachmentTooLarge       = 2001,  // > 25 MB
    CPErrorAttachmentInvalidType    = 2002,  // magic header mismatch

    // Procurement (3xxx)
    CPErrorVarianceFlagged          = 3001,
    CPErrorWriteOffExceedsLimit     = 3002,  // > $250.00
    CPErrorWriteOffNoteRequired     = 3003,  // < 20 chars
    CPErrorInvoiceNumberDuplicate   = 3004,
    CPErrorPaymentExceedsBalance    = 3005,
    CPErrorQuantityExceedsRemaining = 3006,
    CPErrorReconciliationBlocked    = 3007,  // unresolved variances

    // Charger/Commands (4xxx)
    CPErrorCommandTimeout           = 4001,  // 8s without ack
    CPErrorCommandMaxRetries        = 4002,  // 3 retries exhausted

    // Access Control (5xxx)
    CPErrorPermissionDenied         = 5001,

    // Audit (6xxx)
    CPErrorAuditImmutable           = 6001,  // attempt to update AuditEvent

    // Pricing (7xxx)
    CPErrorRuleVersionConflict      = 7001,  // race condition on version create

    // Bulletin (8xxx)
    CPErrorSummaryTooLong           = 8001,  // > 280 chars
    CPErrorBulletinTitleEmpty       = 8002,
};
```

---

## 14. Notification Names Reference

```objc
// Charger
extern NSString *const CPChargerStatusDidChangeNotification;   // userInfo: chargerId, newStatus
extern NSString *const CPCommandAckReceivedNotification;       // userInfo: commandId, status
extern NSString *const CPCommandTimedOutNotification;          // userInfo: commandId

// Bulletin
extern NSString *const CPBulletinAutosaveDidCompleteNotification; // userInfo: bulletinId

// Procurement
extern NSString *const CPProcurementStatusDidChangeNotification;  // userInfo: caseId, newStatus
extern NSString *const CPVarianceFlaggedNotification;             // userInfo: invoiceId

// Analytics
extern NSString *const CPAnomalyDetectedNotification;             // userInfo: anomalyFlag

// RBAC
extern NSString *const CPPermissionChangedNotification;           // userInfo: roleId
```
