# Business Logic Questions Log

1. **Lockout Counter Reset After Expiry**
   - **Question:** After a 15-minute lockout expires, does the `failedAttempts` counter reset to 0 immediately upon lockout expiry, or only upon the next *successful* login?
   - **My Understanding:** The counter resets to 0 at the moment the lockout expires (i.e., when `lockoutUntil < now`), so a failed attempt immediately after expiry starts a fresh 5-attempt sequence — not a 1-attempt-remaining sequence.
   - **Solution:** In `CPAuthService -loginWithUsername:password:completion:`, after confirming `lockoutUntil < now`, reset `failedAttempts = 0` and `lockoutUntil = nil` before evaluating the password, regardless of whether the new login attempt succeeds or fails.

2. **Simultaneous Pinned Bulletin Limit**
   - **Question:** The prompt states bulletins can be pinned for "high-priority" display but does not specify a maximum number of simultaneously pinned bulletins. Is there any cap?
   - **My Understanding:** The prompt does not impose a numeric limit; pinning is unrestricted. Pinned bulletins sort above non-pinned items by the `isPinned` flag.
   - **Solution:** Implement no maximum cap on pinned bulletins. Sort: `isPinned DESC`, then `recommendationWeight DESC`, then `publishedAt DESC`.

3. **Variance Flag Boundary: Strictly Greater Than or Greater Than or Equal**
   - **Question:** The prompt says "flag variances over $25.00 or over 2.0%." Does "over" mean strictly greater than (`> $25.00`) or greater than or equal (`≥ $25.00`)?
   - **My Understanding:** "Over $25.00" means strictly greater than — a difference of exactly $25.00 does NOT trigger a flag.
   - **Solution:** Use `absDiff > 25.0` and `pctDiff > 0.02` (strictly greater than) in `CPInvoiceService -detectVariancesForLine:againstPOLine:`.

4. **Partial Payment on a Reconciled Invoice**
   - **Question:** The prompt states partial payment is supported and the invoice remains "Reconciled with open balance until fully paid." Does the invoice status remain `reconciled` throughout partial payments, or does it transition to a separate `partiallyPaid` state?
   - **My Understanding:** The invoice stays in `reconciled` status until `openBalance == 0`, at which point it transitions to `paid`. There is no separate `partiallyPaid` status.
   - **Solution:** Invoice status: `reconciled` while `openBalance > 0`; transitions to `paid` when `openBalance == 0` after a payment is recorded.

5. **Command Immutability vs. Status Updates**
   - **Question:** The prompt says `Command` entities are immutable after creation, yet commands have a `status` field that must change (Pending → Acknowledged / PendingReview). How is immutability reconciled with status transitions?
   - **My Understanding:** "Immutable" in context means no structural modifications (no changing chargerId, commandType, initiatedByUserId, sentAt, or resultCode after creation). The `status` and `ackedAt` fields are allowable updates because they represent the known outcome of the command, not a revision of its intent.
   - **Solution:** The `Command` entity permits updates to `status`, `ackedAt`, and `retryCount` only. All other fields are set at creation and never changed. `CPAuditEvent` records each status transition separately to preserve the full audit trail.

6. **BGTaskScheduler for Command Retry When App Is Foregrounded**
   - **Question:** The prompt says command retries run via `BGTaskScheduler`. If the app is already in the foreground when a retry is due, does it use `BGTaskScheduler` or a direct in-process timer?
   - **My Understanding:** When the app is foregrounded, an in-process `NSTimer` (or `dispatch_after`) handles the retry delay directly. `BGProcessingTask` is used only when the app has been backgrounded or terminated between retries.
   - **Solution:** `CPCommandRetryQueue` checks `UIApplication.sharedApplication.applicationState`; if `.active` or `.inactive`, schedule retry via `dispatch_after`; if `.background`, submit `BGProcessingTask`.

7. **"Statement Generation by Vendor and Month" — Calendar Month vs. Rolling 30 Days**
   - **Question:** The prompt says "statement generation by vendor and month." Does "month" mean a strict calendar month (e.g., March 1–31) or a rolling 30-day window from the selected end date?
   - **My Understanding:** "Month" means calendar month (e.g., January = Jan 1 00:00:00 to Jan 31 23:59:59 of a given year).
   - **Solution:** `CPStatementService` accepts integer `month` (1–12) and `year` parameters; constructs `NSDateComponents`-based start and end dates for the full calendar month.

8. **Anomaly Detection Execution Timing**
   - **Question:** The prompt says anomaly flags are computed from "stored events and procurements." It also mentions overnight `BGProcessingTask` for reports. Are anomaly flags computed live on-demand when the user opens the analytics screen, or only during the overnight background task?
   - **My Understanding:** Anomaly flags are computed during the overnight `BGProcessingTask` and cached in the `ReportExport` or equivalent transient storage. The analytics screen reads the cached results. On-demand recomputation is also available via a "Refresh" action.
   - **Solution:** `CPAnomalyDetector` is called both (a) from `BGProcessingTask` overnight (results cached in Core Data `ReportExport` entity) and (b) on-demand from `CPAnomalyAlertViewController` via a "Refresh" button, which runs the detector on a background NSOperationQueue and updates the cached results.

9. **RFQ Bid Validity — Expired Bids**
   - **Question:** The prompt specifies `validUntil` on RFQ bids. If a bid's `validUntil` date passes before a bid is selected, should the bid be automatically disqualified, or just flagged?
   - **My Understanding:** Expired bids are flagged (grayed out in the comparison view) but not automatically deleted. The "Select Bid" button is disabled for expired bids, preventing selection.
   - **Solution:** In `CPRFQService -selectBid:forRFQ:`, validate that `bid.validUntil >= [NSDate date]`; return `CPErrorBidExpired` if not. In the RFQ comparison UI, disable the "Select Bid" button and show an "Expired" badge for bids past `validUntil`.

10. **Deposit/Pre-Authorization Status Scope**
    - **Question:** The prompt says deposit and pre-authorization rules have a local status of `none/pending/captured/released`. Is this status tracked per pricing rule instance, per transaction, or per vehicle/rental?
    - **My Understanding:** The status is tracked per individual transaction (i.e., per procurement case or per charger session that invokes the rule), not per rule definition. The rule definition is static; each application of the rule to a specific transaction carries its own status.
    - **Solution:** A separate `DepositTransaction` entity (or status field on `ProcurementCase`) tracks `depositStatus` (none/pending/captured/released) per transaction. `DepositRule` entities remain immutable definitions; their status fields are not mutated.
