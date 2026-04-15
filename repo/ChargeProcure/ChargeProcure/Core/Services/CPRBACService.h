#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Resources and actions for RBAC
FOUNDATION_EXPORT NSString * const CPResourceCharger;
FOUNDATION_EXPORT NSString * const CPResourceProcurement;
FOUNDATION_EXPORT NSString * const CPResourceBulletin;
FOUNDATION_EXPORT NSString * const CPResourcePricing;
FOUNDATION_EXPORT NSString * const CPResourceUser;
FOUNDATION_EXPORT NSString * const CPResourceAudit;
FOUNDATION_EXPORT NSString * const CPResourceInvoice;
FOUNDATION_EXPORT NSString * const CPResourceWriteOff;
FOUNDATION_EXPORT NSString * const CPResourceReport;

FOUNDATION_EXPORT NSString * const CPActionRead;
FOUNDATION_EXPORT NSString * const CPActionCreate;
FOUNDATION_EXPORT NSString * const CPActionUpdate;
FOUNDATION_EXPORT NSString * const CPActionDelete;
FOUNDATION_EXPORT NSString * const CPActionApprove;
FOUNDATION_EXPORT NSString * const CPActionExecute;
FOUNDATION_EXPORT NSString * const CPActionExport;

@interface CPRBACService : NSObject

+ (instancetype)sharedService;

/// Check if current user has permission for resource+action.
- (BOOL)currentUserCanPerform:(NSString *)action onResource:(NSString *)resource;

/// Check permission for specific user by ID.
- (BOOL)userID:(NSString *)userID canPerform:(NSString *)action onResource:(NSString *)resource;

/// Grant a permission to a role. Logs permission-change audit event.
- (BOOL)grantPermission:(NSString *)action
             onResource:(NSString *)resource
                 toRole:(NSString *)roleName
                  error:(NSError **)error;

/// Revoke a permission from a role. Logs permission-change audit event.
- (BOOL)revokePermission:(NSString *)action
              onResource:(NSString *)resource
                fromRole:(NSString *)roleName
                   error:(NSError **)error;

/// Get all permissions for a role.
- (NSArray *)permissionsForRoleName:(NSString *)roleName;

@end

NS_ASSUME_NONNULL_END
