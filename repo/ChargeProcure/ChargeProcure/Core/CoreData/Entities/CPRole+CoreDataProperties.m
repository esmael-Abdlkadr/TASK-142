#import "CPRole+CoreDataProperties.h"

@implementation CPRole (CoreDataProperties)

+ (NSFetchRequest<CPRole *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Role"];
}

@dynamic uuid, name, createdAt, users, permissions;

@end
