#import "CPPermission+CoreDataProperties.h"

@implementation CPPermission (CoreDataProperties)

+ (NSFetchRequest<CPPermission *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Permission"];
}

@dynamic uuid, resource, action, isGranted, role;

@end
