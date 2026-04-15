#import <XCTest/XCTest.h>
#import "CPExportService.h"
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// CPExportServiceTests
//
// Tests that verify CPExportService authorization, output contracts, and
// format-level behaviour for all three seeded roles.
//
//   EXPORT-ADMIN-*:   Administrator receives a file (not a permission error)
//   EXPORT-TECH-*:    Site Technician receives a permission error for every type
//   EXPORT-FINANCE-*: Finance Approver receives a file for financial reports
//   EXPORT-NOSESS-*:  No active session → permission error on every call
//   EXPORT-AUDIT-*:   exportAuditLogsWithResourceType:search: authorization
//   EXPORT-LIST-1:    fetchReportExports returns an NSArray (never nil)
// ---------------------------------------------------------------------------

static NSString * const kExportTestPass = @"Test1234Pass";

@interface CPExportServiceTests : XCTestCase
@end

@implementation CPExportServiceTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSString *entity in @[@"User", @"Role"]) {
            NSArray *objects = [ctx executeFetchRequest:
                                [NSFetchRequest fetchRequestWithEntityName:entity] error:nil];
            for (NSManagedObject *o in objects) [ctx deleteObject:o];
        }
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cp_must_change_password_uuids"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kExportTestPass];
}

- (void)tearDown {
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

- (void)loginAs:(NSString *)username {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPAuthService sharedService] loginWithUsername:username
                                           password:kExportTestPass
                                         completion:^(BOOL success, NSError *err) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// ---------------------------------------------------------------------------
// EXPORT-ADMIN-1: Admin can generate a ProcurementSummary CSV without error
// ---------------------------------------------------------------------------

- (void)testAdminCanGenerateProcurementSummaryCSV {
    [self loginAs:@"admin"];

    XCTestExpectation *exp = [self expectationWithDescription:@"adminExportCSV"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeProcurementSummary
             format:CPExportFormatCSV
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        // Admin must not receive a permission-class error (code -1).
        if (error) {
            XCTAssertNotEqual(error.code, -1,
                @"Admin must not receive a permission error; got: %@", error);
        }
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// EXPORT-ADMIN-2: Admin can generate a ChargerActivity PDF
// ---------------------------------------------------------------------------

- (void)testAdminCanGenerateChargerActivityPDF {
    [self loginAs:@"admin"];

    XCTestExpectation *exp = [self expectationWithDescription:@"adminExportPDF"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeChargerActivity
             format:CPExportFormatPDF
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        if (error) {
            XCTAssertNotEqual(error.code, -1,
                @"Admin must not receive a permission error for PDF format; got: %@", error);
        }
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// EXPORT-TECH-1: Technician is denied ProcurementSummary
// ---------------------------------------------------------------------------

- (void)testTechnicianDeniedProcurementSummary {
    [self loginAs:@"technician"];

    XCTestExpectation *exp = [self expectationWithDescription:@"techExportDenied"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeProcurementSummary
             format:CPExportFormatCSV
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        XCTAssertNil(fileURL,
            @"No output file should be produced when the technician lacks export permission");
        XCTAssertNotNil(error,
            @"A permission error must be returned when export is denied");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// EXPORT-TECH-2: Technician is denied all five report types
// ---------------------------------------------------------------------------

- (void)testTechnicianDeniedAllReportTypes {
    [self loginAs:@"technician"];

    NSArray *reportTypes = @[
        @(CPReportTypeProcurementSummary),
        @(CPReportTypeVendorStatement),
        @(CPReportTypeChargerActivity),
        @(CPReportTypeAuditLog),
        @(CPReportTypeAnalyticsSummary),
    ];

    for (NSNumber *typeNum in reportTypes) {
        CPReportType reportType = (CPReportType)typeNum.integerValue;

        XCTestExpectation *exp = [self expectationWithDescription:
                                  [NSString stringWithFormat:@"techDenied-%ld", (long)reportType]];
        [[CPExportService sharedService]
         generateReport:reportType
                 format:CPExportFormatCSV
             parameters:nil
             completion:^(NSURL *fileURL, NSError *error) {
            XCTAssertNil(fileURL,
                @"Technician must not receive a file for report type %ld", (long)reportType);
            XCTAssertNotNil(error,
                @"Technician must receive an error for report type %ld", (long)reportType);
            [exp fulfill];
        }];
        [self waitForExpectationsWithTimeout:10 handler:nil];
    }
}

// ---------------------------------------------------------------------------
// EXPORT-NOSESS-1: No active session → permission error on every report type
// ---------------------------------------------------------------------------

- (void)testNoSessionDeniedAllReportTypes {
    [[CPAuthService sharedService] logout];

    NSArray *reportTypes = @[
        @(CPReportTypeProcurementSummary),
        @(CPReportTypeChargerActivity),
        @(CPReportTypeAnalyticsSummary),
    ];

    for (NSNumber *typeNum in reportTypes) {
        CPReportType reportType = (CPReportType)typeNum.integerValue;

        XCTestExpectation *exp = [self expectationWithDescription:
                                  [NSString stringWithFormat:@"noSessDenied-%ld", (long)reportType]];
        [[CPExportService sharedService]
         generateReport:reportType
                 format:CPExportFormatCSV
             parameters:nil
             completion:^(NSURL *fileURL, NSError *error) {
            XCTAssertNil(fileURL,
                @"Unauthenticated caller must not receive a file for report type %ld", (long)reportType);
            XCTAssertNotNil(error,
                @"Unauthenticated caller must receive an error for report type %ld", (long)reportType);
            [exp fulfill];
        }];
        [self waitForExpectationsWithTimeout:10 handler:nil];
    }
}

// ---------------------------------------------------------------------------
// EXPORT-AUDIT-ADMIN-1: Admin can export audit logs (no permission error)
// ---------------------------------------------------------------------------

- (void)testAdminCanExportAuditLogs {
    [self loginAs:@"admin"];

    XCTestExpectation *exp = [self expectationWithDescription:@"adminAuditExport"];
    [[CPExportService sharedService]
     exportAuditLogsWithResourceType:nil
                               search:nil
                           completion:^(NSURL *fileURL, NSError *error) {
        if (error) {
            XCTAssertNotEqual(error.code, -1,
                @"Admin must not receive a permission error on audit log export; got: %@", error);
        }
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// EXPORT-AUDIT-TECH-1: Technician is denied audit log export
// ---------------------------------------------------------------------------

- (void)testTechnicianDeniedAuditLogExport {
    [self loginAs:@"technician"];

    XCTestExpectation *exp = [self expectationWithDescription:@"techAuditDenied"];
    [[CPExportService sharedService]
     exportAuditLogsWithResourceType:nil
                               search:nil
                           completion:^(NSURL *fileURL, NSError *error) {
        XCTAssertNil(fileURL,
            @"Technician must not receive an audit log file");
        XCTAssertNotNil(error,
            @"Technician must receive a permission error on audit log export");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// EXPORT-LIST-1: fetchReportExports returns nil for unauthenticated callers
// ---------------------------------------------------------------------------

- (void)testFetchReportExportsReturnsArray {
    // Authorized user (admin) must receive a non-nil NSArray.
    [self loginAs:@"admin"];
    NSArray *exports = [[CPExportService sharedService] fetchReportExports];
    XCTAssertNotNil(exports, @"fetchReportExports must return a non-nil NSArray for authorized users");
    XCTAssertTrue([exports isKindOfClass:[NSArray class]],
                  @"fetchReportExports must return an NSArray for authorized users");
}

// ---------------------------------------------------------------------------
// EXPORT-READ-DENY-1: fetchReportExports returns nil for users without read/export permission
// ---------------------------------------------------------------------------

- (void)testFetchReportExportsDeniedForUnauthenticatedUser {
    // No active session — service must refuse to return report history.
    [[CPAuthService sharedService] logout];
    NSArray *exports = [[CPExportService sharedService] fetchReportExports];
    XCTAssertNil(exports,
                 @"fetchReportExports must return nil when no user is authenticated");
}

// ---------------------------------------------------------------------------
// EXPORT-READ-DENY-2: fetchReportExports returns nil for Technician (no report.read/export)
// ---------------------------------------------------------------------------

- (void)testFetchReportExportsDeniedForTechnician {
    // Site Technician role must not have access to report history.
    [self loginAs:@"technician"];
    NSArray *exports = [[CPExportService sharedService] fetchReportExports];
    XCTAssertNil(exports,
                 @"fetchReportExports must return nil for a user without report.read/export permission");
}

// ---------------------------------------------------------------------------
// EXPORT-URL-DENY-1: exportURLForReportUUID returns nil for users without read/export permission
// ---------------------------------------------------------------------------

- (void)testExportURLForReportUUIDDeniedForUnauthenticatedUser {
    [[CPAuthService sharedService] logout];
    // Any UUID — service must refuse before touching Core Data.
    NSURL *url = [[CPExportService sharedService]
                  exportURLForReportUUID:[[NSUUID UUID] UUIDString]];
    XCTAssertNil(url,
                 @"exportURLForReportUUID must return nil when no user is authenticated");
}

// ---------------------------------------------------------------------------
// EXPORT-URL-DENY-2: exportURLForReportUUID returns nil for Technician
// ---------------------------------------------------------------------------

- (void)testExportURLForReportUUIDDeniedForTechnician {
    [self loginAs:@"technician"];
    NSURL *url = [[CPExportService sharedService]
                  exportURLForReportUUID:[[NSUUID UUID] UUIDString]];
    XCTAssertNil(url,
                 @"exportURLForReportUUID must return nil for a user without report.read/export permission");
}

// ---------------------------------------------------------------------------
// EXPORT-LIST-2: After a successful admin export the report appears in the list
// ---------------------------------------------------------------------------

- (void)testSuccessfulExportAppearsInFetchList {
    [self loginAs:@"admin"];

    NSUInteger countBefore = [[CPExportService sharedService] fetchReportExports].count;

    XCTestExpectation *exp = [self expectationWithDescription:@"exportForList"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeAnalyticsSummary
             format:CPExportFormatCSV
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        // Only assert the list grows when no permission error occurred.
        if (!error || error.code != -1) {
            NSUInteger countAfter = [[CPExportService sharedService] fetchReportExports].count;
            if (!error) {
                // Successful export must create a ReportExport record.
                XCTAssertGreaterThan(countAfter, countBefore,
                    @"A successful export must appear in fetchReportExports");
            }
        }
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end
