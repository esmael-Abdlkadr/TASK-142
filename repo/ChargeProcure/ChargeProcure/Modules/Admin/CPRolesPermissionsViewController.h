#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Displays every defined role and its current permissions.
/// Administrators can grant or revoke individual permissions; all changes are
/// audited through CPRBACService and recorded in CPAuditService.
@interface CPRolesPermissionsViewController : UIViewController

@end

NS_ASSUME_NONNULL_END
