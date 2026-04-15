#import "CPReportExport+CoreDataProperties.h"

@implementation CPReportExport (CoreDataProperties)

+ (NSFetchRequest<CPReportExport *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"ReportExport"];
}

@dynamic uuid, reportType, parameters, filePath, fileFormat, generatedByUserID, fileSize, generatedAt;

@end
