#import "CPExportService.h"
#import "CPCoreDataStack.h"
#import "CPAuthService.h"
#import "CPRBACService.h"
#import <CoreData/CoreData.h>
#import <UIKit/UIKit.h>

NSString * const CPExportErrorDomain = @"com.chargeprocure.export";

static const NSInteger CPExportErrorGenerationFailed = 6001;
static const NSInteger CPExportErrorFileTooLarge     = 6002;
static const NSInteger CPExportErrorSaveFailed       = 6003;
static const NSInteger CPExportErrorNotFound         = 6004;

static const NSInteger kExportMaxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

@implementation CPExportService

+ (instancetype)sharedService {
    static CPExportService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPExportService alloc] init];
    });
    return instance;
}

#pragma mark - Public API

- (void)generateReport:(CPReportType)reportType
                format:(CPExportFormat)format
            parameters:(nullable NSDictionary *)parameters
            completion:(void (^)(NSURL * _Nullable fileURL, NSError * _Nullable error))completion {

    // Service-layer RBAC enforcement — reject unauthorized callers regardless of
    // how they arrive at this call site (direct invocation, alternate nav path, etc.).
    if (![[CPRBACService sharedService] currentUserCanPerform:CPActionExport onResource:CPResourceReport]) {
        NSError *authError = [NSError errorWithDomain:CPExportErrorDomain
                                                 code:CPExportErrorGenerationFailed
                                             userInfo:@{NSLocalizedDescriptionKey: @"Insufficient permissions to generate reports."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) { completion(nil, authError); }
        });
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSURL *fileURL = [self generateReportSync:reportType
                                           format:format
                                       parameters:parameters
                                            error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(fileURL, error);
            }
        });
    });
}

- (NSURL *)exportURLForReportUUID:(NSString *)reportUUID {
    // Service-layer read authorization — callers must have Read or Export on Report.
    BOOL canRead = [[CPRBACService sharedService] currentUserCanPerform:CPActionRead   onResource:CPResourceReport]
                || [[CPRBACService sharedService] currentUserCanPerform:CPActionExport onResource:CPResourceReport];
    if (!canRead) {
        return nil;
    }

    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ReportExport"];
    request.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", reportUUID];
    request.fetchLimit = 1;

    NSError *error = nil;
    NSArray *results = [context executeFetchRequest:request error:&error];
    NSManagedObject *export = results.firstObject;
    if (!export) {
        return nil;
    }

    NSString *filePath = [export valueForKey:@"filePath"];
    if (!filePath) {
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (nullable NSArray *)fetchReportExports {
    // Service-layer read authorization — callers must have Read or Export on Report.
    BOOL canRead = [[CPRBACService sharedService] currentUserCanPerform:CPActionRead   onResource:CPResourceReport]
                || [[CPRBACService sharedService] currentUserCanPerform:CPActionExport onResource:CPResourceReport];
    if (!canRead) {
        return nil;
    }

    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ReportExport"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"generatedAt" ascending:NO]];

    NSError *error = nil;
    NSArray *results = [context executeFetchRequest:request error:&error];
    return results ?: @[];
}

- (void)exportAuditLogsWithResourceType:(nullable NSString *)resourceType
                                  search:(nullable NSString *)search
                              completion:(void(^)(NSURL * _Nullable, NSError * _Nullable))completion {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (resourceType.length > 0) { params[@"resourceType"] = resourceType; }
    if (search.length > 0)       { params[@"search"]       = search; }

    [self generateReport:CPReportTypeAuditLog
                  format:CPExportFormatCSV
              parameters:params.count > 0 ? [params copy] : nil
              completion:completion];
}

#pragma mark - Private Generation

- (nullable NSURL *)generateReportSync:(CPReportType)reportType
                                 format:(CPExportFormat)format
                             parameters:(nullable NSDictionary *)parameters
                                  error:(NSError **)error {
    // Determine filename
    NSString *typeString = [self stringForReportType:reportType];
    NSString *extension  = (format == CPExportFormatCSV) ? @"csv" : @"pdf";
    NSTimeInterval ts    = [[NSDate date] timeIntervalSince1970];
    NSString *filename   = [NSString stringWithFormat:@"%@_%.0f.%@", typeString, ts, extension];

    // Build output directory
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *reportsDir = [docsDir stringByAppendingPathComponent:@"Reports"];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *dirError = nil;
    [fm createDirectoryAtPath:reportsDir
  withIntermediateDirectories:YES
                   attributes:nil
                        error:&dirError];
    if (dirError) {
        if (error) {
            *error = [NSError errorWithDomain:CPExportErrorDomain
                                         code:CPExportErrorGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create Reports directory.",
                                                NSUnderlyingErrorKey: dirError}];
        }
        return nil;
    }

    NSString *filePath = [reportsDir stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    // Fetch data for report
    NSArray *reportData = [self fetchDataForReportType:reportType parameters:parameters];

    BOOL writeSuccess = NO;
    if (format == CPExportFormatCSV) {
        writeSuccess = [self writeCSVData:reportData
                              reportType:reportType
                                  toPath:filePath
                                   error:error];
    } else {
        writeSuccess = [self writePDFData:reportData
                              reportType:reportType
                               parameters:parameters
                                   toPath:filePath
                                    error:error];
    }

    if (!writeSuccess) {
        return nil;
    }

    // Size check
    NSError *attrError = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:&attrError];
    NSInteger fileSize = [attrs[NSFileSize] integerValue];
    if (fileSize > kExportMaxFileSizeBytes) {
        [fm removeItemAtPath:filePath error:nil];
        if (error) {
            *error = [NSError errorWithDomain:CPExportErrorDomain
                                         code:CPExportErrorFileTooLarge
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Exported file size (%ld bytes) exceeds 25MB limit.", (long)fileSize]}];
        }
        return nil;
    }

    // Save ReportExport record in Core Data (on main context via perform)
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;
    __block NSError *saveError = nil;
    [context performBlockAndWait:^{
        NSManagedObject *exportRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ReportExport"
                                                                     inManagedObjectContext:context];
        [exportRecord setValue:[[NSUUID UUID] UUIDString]                        forKey:@"uuid"];
        [exportRecord setValue:typeString                                         forKey:@"reportType"];
        [exportRecord setValue:filePath                                           forKey:@"filePath"];
        [exportRecord setValue:extension.uppercaseString                          forKey:@"fileFormat"];
        [exportRecord setValue:[NSDate date]                                      forKey:@"generatedAt"];
        [exportRecord setValue:[CPAuthService sharedService].currentUserID        forKey:@"generatedByUserID"];
        [exportRecord setValue:@(fileSize)                                        forKey:@"fileSize"];

        // Serialize parameters to JSON string if provided
        if (parameters) {
            NSData *paramData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:nil];
            NSString *paramString = paramData ? [[NSString alloc] initWithData:paramData encoding:NSUTF8StringEncoding] : nil;
            [exportRecord setValue:paramString forKey:@"parameters"];
        }

        [context save:&saveError];
    }];

    if (saveError) {
        if (error) {
            *error = [NSError errorWithDomain:CPExportErrorDomain
                                         code:CPExportErrorSaveFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to save export record.",
                                                NSUnderlyingErrorKey: saveError}];
        }
        return nil;
    }

    return fileURL;
}

#pragma mark - CSV Generation

- (BOOL)writeCSVData:(NSArray *)data
          reportType:(CPReportType)reportType
              toPath:(NSString *)filePath
               error:(NSError **)error {
    NSMutableString *csv = [NSMutableString string];

    NSArray *headers = [self csvHeadersForReportType:reportType];
    NSString *headerRow = [self csvEscapeRow:headers];
    [csv appendFormat:@"%@\n", headerRow];

    for (id row in data) {
        NSArray *rowValues = [self csvRowValuesForItem:row reportType:reportType];
        [csv appendFormat:@"%@\n", [self csvEscapeRow:rowValues]];
    }

    NSData *csvData = [csv dataUsingEncoding:NSUTF8StringEncoding];
    if (!csvData) {
        if (error) {
            *error = [NSError errorWithDomain:CPExportErrorDomain
                                         code:CPExportErrorGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode CSV data."}];
        }
        return NO;
    }

    NSError *writeError = nil;
    BOOL success = [csvData writeToFile:filePath options:NSDataWritingAtomic error:&writeError];
    if (!success && error) {
        *error = writeError ?: [NSError errorWithDomain:CPExportErrorDomain
                                                   code:CPExportErrorGenerationFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to write CSV file."}];
    }
    return success;
}

- (NSString *)csvEscapeRow:(NSArray *)values {
    NSMutableArray *escaped = [NSMutableArray array];
    for (id val in values) {
        NSString *str = [val description] ?: @"";
        // Escape double-quotes by doubling them, then wrap in quotes if necessary
        if ([str containsString:@","] || [str containsString:@"\""] || [str containsString:@"\n"]) {
            str = [str stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
            str = [NSString stringWithFormat:@"\"%@\"", str];
        }
        [escaped addObject:str];
    }
    return [escaped componentsJoinedByString:@","];
}

#pragma mark - PDF Generation

- (BOOL)writePDFData:(NSArray *)data
          reportType:(CPReportType)reportType
          parameters:(nullable NSDictionary *)parameters
              toPath:(NSString *)filePath
               error:(NSError **)error {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    UIGraphicsPDFRendererFormat *pdfFormat = [UIGraphicsPDFRendererFormat defaultFormat];
    CGRect pageRect = CGRectMake(0, 0, 612, 792); // US Letter in points

    UIGraphicsPDFRenderer *renderer = [[UIGraphicsPDFRenderer alloc] initWithBounds:pageRect
                                                                              format:pdfFormat];

    NSArray *headers = [self csvHeadersForReportType:reportType];
    NSString *reportTitle = [self titleForReportType:reportType];

    NSError *renderError = nil;
    BOOL success = [renderer writePDFToURL:fileURL withActions:^(UIGraphicsPDFRendererContext *ctx) {
        // Fonts and attributes
        UIFont *titleFont   = [UIFont boldSystemFontOfSize:16.0];
        UIFont *headerFont  = [UIFont boldSystemFontOfSize:9.0];
        UIFont *bodyFont    = [UIFont systemFontOfSize:8.0];
        UIFont *footerFont  = [UIFont systemFontOfSize:7.0];

        NSDictionary *titleAttrs  = @{NSFontAttributeName: titleFont,
                                      NSForegroundColorAttributeName: [UIColor blackColor]};
        NSDictionary *headerAttrs = @{NSFontAttributeName: headerFont,
                                      NSForegroundColorAttributeName: [UIColor whiteColor]};
        NSDictionary *bodyAttrs   = @{NSFontAttributeName: bodyFont,
                                      NSForegroundColorAttributeName: [UIColor blackColor]};
        NSDictionary *footerAttrs = @{NSFontAttributeName: footerFont,
                                      NSForegroundColorAttributeName: [UIColor grayColor]};

        const CGFloat margin          = 36.0;
        const CGFloat columnSpacing   = 4.0;
        const CGFloat rowHeight       = 14.0;
        const CGFloat headerRowHeight = 16.0;
        const CGFloat titleHeight     = 30.0;
        const CGFloat footerHeight    = 20.0;

        NSInteger totalCols = headers.count;
        CGFloat availWidth  = pageRect.size.width - 2.0 * margin;
        CGFloat colWidth    = totalCols > 0 ? (availWidth - columnSpacing * (totalCols - 1)) / totalCols : availWidth;

        // Pagination: items per page
        CGFloat bodyHeight   = pageRect.size.height - 2.0 * margin - titleHeight - headerRowHeight - footerHeight;
        NSInteger rowsPerPage = MAX(1, (NSInteger)(bodyHeight / rowHeight));
        NSInteger totalRows   = data.count;
        NSInteger totalPages  = MAX(1, (NSInteger)ceil((double)totalRows / (double)rowsPerPage));

        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateStyle = NSDateFormatterMediumStyle;
        df.timeStyle = NSDateFormatterShortStyle;
        NSString *generatedStr = [NSString stringWithFormat:@"Generated: %@", [df stringFromDate:[NSDate date]]];

        for (NSInteger page = 0; page < totalPages; page++) {
            [ctx beginPage];
            CGContextRef cgCtx = ctx.CGContext;

            CGFloat y = margin;

            // Title
            NSString *titleStr = [NSString stringWithFormat:@"%@  (Page %ld of %ld)",
                                  reportTitle, (long)(page + 1), (long)totalPages];
            [titleStr drawInRect:CGRectMake(margin, y, availWidth, titleHeight)
                  withAttributes:titleAttrs];
            y += titleHeight;

            // Header row background
            CGContextSetFillColorWithColor(cgCtx, [[UIColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:1.0] CGColor]);
            CGContextFillRect(cgCtx, CGRectMake(margin, y, availWidth, headerRowHeight));

            // Header cells
            for (NSInteger col = 0; col < totalCols; col++) {
                CGFloat x = margin + col * (colWidth + columnSpacing);
                CGRect cellRect = CGRectMake(x + 2.0, y + 2.0, colWidth - 4.0, headerRowHeight - 4.0);
                NSString *headerText = headers[col];
                [headerText drawInRect:cellRect withAttributes:headerAttrs];
            }
            y += headerRowHeight;

            // Data rows
            NSInteger startRow = page * rowsPerPage;
            NSInteger endRow   = MIN(startRow + rowsPerPage, totalRows);

            for (NSInteger rowIdx = startRow; rowIdx < endRow; rowIdx++) {
                id item = data[rowIdx];
                NSArray *rowValues = [self csvRowValuesForItem:item reportType:reportType];

                // Alternating row background
                if ((rowIdx % 2) == 0) {
                    CGContextSetFillColorWithColor(cgCtx, [[UIColor colorWithWhite:0.95 alpha:1.0] CGColor]);
                    CGContextFillRect(cgCtx, CGRectMake(margin, y, availWidth, rowHeight));
                }

                for (NSInteger col = 0; col < (NSInteger)rowValues.count && col < totalCols; col++) {
                    CGFloat x = margin + col * (colWidth + columnSpacing);
                    CGRect cellRect = CGRectMake(x + 2.0, y + 2.0, colWidth - 4.0, rowHeight - 4.0);
                    NSString *cellText = [rowValues[col] description] ?: @"";
                    [cellText drawInRect:cellRect withAttributes:bodyAttrs];
                }
                y += rowHeight;
            }

            // Footer
            CGFloat footerY = pageRect.size.height - margin - footerHeight;
            [generatedStr drawInRect:CGRectMake(margin, footerY, availWidth, footerHeight)
                      withAttributes:footerAttrs];
        }
    } error:&renderError];

    if (!success && error) {
        *error = renderError ?: [NSError errorWithDomain:CPExportErrorDomain
                                                    code:CPExportErrorGenerationFailed
                                                userInfo:@{NSLocalizedDescriptionKey: @"Failed to render PDF."}];
    }
    return success;
}

#pragma mark - Data Fetching

- (NSArray *)fetchDataForReportType:(CPReportType)reportType parameters:(nullable NSDictionary *)parameters {
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
    __block NSArray *results = @[];

    [context performBlockAndWait:^{
        NSString *entityName = [self entityNameForReportType:reportType];
        if (!entityName) {
            results = @[];
            return;
        }

        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entityName];
        request.sortDescriptors = [self sortDescriptorsForReportType:reportType];

        // Apply date range filter from parameters if present
        NSDate *fromDate = parameters[@"fromDate"];
        NSDate *toDate   = parameters[@"toDate"];
        if (fromDate || toDate) {
            NSString *dateKey = [self dateKeyForReportType:reportType];
            if (dateKey) {
                NSMutableArray *predicates = [NSMutableArray array];
                if (fromDate) {
                    [predicates addObject:[NSPredicate predicateWithFormat:@"%K >= %@", dateKey, fromDate]];
                }
                if (toDate) {
                    [predicates addObject:[NSPredicate predicateWithFormat:@"%K <= %@", dateKey, toDate]];
                }
                request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
            }
        }

        NSError *error = nil;
        NSArray *fetchedObjects = [context executeFetchRequest:request error:&error];
        results = fetchedObjects ?: @[];
    }];

    return results;
}

#pragma mark - Report Type Helpers

- (NSString *)stringForReportType:(CPReportType)type {
    switch (type) {
        case CPReportTypeProcurementSummary: return @"ProcurementSummary";
        case CPReportTypeVendorStatement:    return @"VendorStatement";
        case CPReportTypeChargerActivity:    return @"ChargerActivity";
        case CPReportTypeAuditLog:           return @"AuditLog";
        case CPReportTypeAnalyticsSummary:   return @"AnalyticsSummary";
        default:                             return @"Report";
    }
}

- (NSString *)titleForReportType:(CPReportType)type {
    switch (type) {
        case CPReportTypeProcurementSummary: return @"Procurement Summary Report";
        case CPReportTypeVendorStatement:    return @"Vendor Statement Report";
        case CPReportTypeChargerActivity:    return @"Charger Activity Report";
        case CPReportTypeAuditLog:           return @"Audit Log Report";
        case CPReportTypeAnalyticsSummary:   return @"Analytics Summary Report";
        default:                             return @"Report";
    }
}

- (nullable NSString *)entityNameForReportType:(CPReportType)type {
    switch (type) {
        case CPReportTypeProcurementSummary: return @"ProcurementCase";
        case CPReportTypeVendorStatement:    return @"Vendor";
        case CPReportTypeChargerActivity:    return @"ChargerEvent";
        case CPReportTypeAuditLog:           return @"AuditEvent";
        case CPReportTypeAnalyticsSummary:   return @"ChargerEvent";
        default:                             return nil;
    }
}

- (NSArray *)sortDescriptorsForReportType:(CPReportType)type {
    switch (type) {
        case CPReportTypeProcurementSummary:
            return @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
        case CPReportTypeVendorStatement:
            return @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
        case CPReportTypeChargerActivity:
        case CPReportTypeAnalyticsSummary:
            return @[[NSSortDescriptor sortDescriptorWithKey:@"occurredAt" ascending:NO]];
        case CPReportTypeAuditLog:
            return @[[NSSortDescriptor sortDescriptorWithKey:@"occurredAt" ascending:NO]];
        default:
            return @[];
    }
}

- (nullable NSString *)dateKeyForReportType:(CPReportType)type {
    switch (type) {
        case CPReportTypeProcurementSummary: return @"createdAt";
        case CPReportTypeChargerActivity:
        case CPReportTypeAnalyticsSummary:
        case CPReportTypeAuditLog:           return @"occurredAt";
        case CPReportTypeVendorStatement:    return @"createdAt";
        default:                             return nil;
    }
}

- (NSArray *)csvHeadersForReportType:(CPReportType)type {
    switch (type) {
        case CPReportTypeProcurementSummary:
            return @[@"UUID", @"Case Number", @"Title", @"Stage", @"Vendor", @"Total Amount", @"Currency", @"Created At"];
        case CPReportTypeVendorStatement:
            return @[@"UUID", @"Name", @"Contact Name", @"Contact Email", @"Contact Phone", @"Address", @"Active", @"Created At"];
        case CPReportTypeChargerActivity:
        case CPReportTypeAnalyticsSummary:
            return @[@"UUID", @"Charger ID", @"Event Type", @"Previous Status", @"New Status", @"Detail", @"Occurred At"];
        case CPReportTypeAuditLog:
            return @[@"UUID", @"Actor", @"Action", @"Resource", @"Resource ID", @"Detail", @"Occurred At"];
        default:
            return @[@"UUID"];
    }
}

- (NSArray *)csvRowValuesForItem:(NSManagedObject *)item reportType:(CPReportType)type {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateStyle = NSDateFormatterShortStyle;
    df.timeStyle = NSDateFormatterMediumStyle;

    switch (type) {
        case CPReportTypeProcurementSummary:
            return @[
                [item valueForKey:@"uuid"]        ?: @"",
                [item valueForKey:@"caseNumber"]   ?: @"",
                [item valueForKey:@"title"]        ?: @"",
                [item valueForKey:@"stage"]        ?: @"",
                [item valueForKey:@"notes"]        ?: @"",  // vendorName stored in notes for ProcurementCase
                [[item valueForKey:@"totalAmount"] description] ?: @"0",
                @"USD",
                [item valueForKey:@"createdAt"] ? [df stringFromDate:[item valueForKey:@"createdAt"]] : @"",
            ];
        case CPReportTypeVendorStatement:
            return @[
                [item valueForKey:@"uuid"]         ?: @"",
                [item valueForKey:@"name"]          ?: @"",
                [item valueForKey:@"contactName"]   ?: @"",
                [item valueForKey:@"contactEmail"]  ?: @"",
                [item valueForKey:@"contactPhone"]  ?: @"",
                [item valueForKey:@"address"]       ?: @"",
                [[item valueForKey:@"isActive"] boolValue] ? @"Yes" : @"No",
                [item valueForKey:@"createdAt"] ? [df stringFromDate:[item valueForKey:@"createdAt"]] : @"",
            ];
        case CPReportTypeChargerActivity:
        case CPReportTypeAnalyticsSummary:
            return @[
                [item valueForKey:@"uuid"]           ?: @"",
                [item valueForKey:@"chargerID"]       ?: @"",
                [item valueForKey:@"eventType"]       ?: @"",
                [item valueForKey:@"previousStatus"]  ?: @"",
                [item valueForKey:@"newStatus"]       ?: @"",
                [item valueForKey:@"detail"]          ?: @"",
                [item valueForKey:@"occurredAt"] ? [df stringFromDate:[item valueForKey:@"occurredAt"]] : @"",
            ];
        case CPReportTypeAuditLog:
            return @[
                [item valueForKey:@"uuid"]          ?: @"",
                [item valueForKey:@"actorUsername"]  ?: @"",
                [item valueForKey:@"action"]         ?: @"",
                [item valueForKey:@"resource"]       ?: @"",
                [item valueForKey:@"resourceID"]     ?: @"",
                [item valueForKey:@"detail"]         ?: @"",
                [item valueForKey:@"occurredAt"] ? [df stringFromDate:[item valueForKey:@"occurredAt"]] : @"",
            ];
        default:
            return @[[item valueForKey:@"uuid"] ?: @""];
    }
}

@end
