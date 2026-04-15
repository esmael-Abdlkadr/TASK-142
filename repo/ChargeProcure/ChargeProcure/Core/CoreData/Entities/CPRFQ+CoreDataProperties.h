#import "CPRFQ+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPProcurementCase;
@class CPRFQBid;

NS_ASSUME_NONNULL_BEGIN

@interface CPRFQ (CoreDataProperties)

+ (NSFetchRequest<CPRFQ *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *caseID;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, copy) NSDate *issuedAt;
@property (nullable, nonatomic, copy) NSDate *dueDate;

@property (nullable, nonatomic, retain) CPProcurementCase *procurementCase;
@property (nullable, nonatomic, retain) NSSet<CPRFQBid *> *bids;

@end

@interface CPRFQ (CoreDataGeneratedAccessors)

- (void)addBidsObject:(CPRFQBid *)value;
- (void)removeBidsObject:(CPRFQBid *)value;
- (void)addBids:(NSSet<CPRFQBid *> *)values;
- (void)removeBids:(NSSet<CPRFQBid *> *)values;

@end

NS_ASSUME_NONNULL_END
