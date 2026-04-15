#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPExportErrorDomain;

typedef NS_ENUM(NSInteger, CPExportFormat) {
    CPExportFormatCSV = 0,
    CPExportFormatPDF,
};

typedef NS_ENUM(NSInteger, CPReportType) {
    CPReportTypeProcurementSummary = 0,
    CPReportTypeVendorStatement,
    CPReportTypeChargerActivity,
    CPReportTypeAuditLog,
    CPReportTypeAnalyticsSummary,
};

@interface CPExportService : NSObject

+ (instancetype)sharedService;

/// Generate and save a report. Returns file URL on success.
- (void)generateReport:(CPReportType)reportType
                format:(CPExportFormat)format
            parameters:(nullable NSDictionary *)parameters
            completion:(void (^)(NSURL * _Nullable fileURL, NSError * _Nullable error))completion;

/// Get URL for sharing via UIActivityViewController.
- (NSURL *)exportURLForReportUUID:(NSString *)reportUUID;

/// Fetch all generated report exports.
/// Returns nil if the current user lacks read/export permission on Report.
- (nullable NSArray *)fetchReportExports;

/// Generate and deliver an audit-log report filtered by resourceType and/or actor search term.
/// Completion is called on the main queue.
- (void)exportAuditLogsWithResourceType:(nullable NSString *)resourceType
                                  search:(nullable NSString *)search
                              completion:(void(^)(NSURL * _Nullable fileURL, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
