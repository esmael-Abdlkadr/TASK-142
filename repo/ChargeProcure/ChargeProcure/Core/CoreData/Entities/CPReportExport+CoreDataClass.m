#import "CPReportExport+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPReportExport

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPReportExport *obj = [NSEntityDescription insertNewObjectForEntityForName:@"ReportExport" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.generatedAt = [NSDate date];
    return obj;
}

@end
