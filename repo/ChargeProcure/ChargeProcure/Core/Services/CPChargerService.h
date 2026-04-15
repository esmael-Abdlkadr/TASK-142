#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPChargerServiceErrorDomain;
FOUNDATION_EXPORT NSString * const CPChargerStatusChangedNotification;
FOUNDATION_EXPORT NSString * const CPCommandAcknowledgedNotification;

// ---------------------------------------------------------------------------
// CPChargerAdapterProtocol
//
// Abstraction layer for vendor SDK communication. In production this is
// implemented by the on-device charger vendor SDK integration. In tests it
// is replaced by CPChargerSimulatorAdapter for deterministic, fast tests.
// ---------------------------------------------------------------------------

@protocol CPChargerAdapterProtocol <NSObject>

/// Deliver a command to the physical charger and call `completion` with
/// the result. Must call completion exactly once — on any queue.
///
/// @param commandUUID  Unique identifier assigned by CPChargerService.
/// @param chargerUUID  Target charger's persistent UUID.
/// @param commandType  One of "RemoteStart", "RemoteStop", "SoftReset", "ParameterPush".
/// @param parameters   Optional JSON-serializable parameters dictionary.
/// @param completion   Called with (success, failureReason) when the vendor
///                     SDK responds or the adapter gives up. Pass YES/nil on
///                     success, NO/reason on failure.
- (void)sendCommand:(NSString *)commandUUID
          toCharger:(NSString *)chargerUUID
        commandType:(NSString *)commandType
         parameters:(nullable NSDictionary *)parameters
         completion:(void (^)(BOOL success, NSString * _Nullable failureReason))completion;

@end

typedef NS_ENUM(NSInteger, CPCommandType) {
    CPCommandTypeRemoteStart = 0,
    CPCommandTypeRemoteStop,
    CPCommandTypeSoftReset,
    CPCommandTypeParameterPush,
};

typedef NS_ENUM(NSInteger, CPCommandStatus) {
    CPCommandStatusPending = 0,
    CPCommandStatusAcknowledged,
    CPCommandStatusFailed,
    CPCommandStatusPendingReview,
    CPCommandStatusTimedOut,
};

@interface CPChargerService : NSObject

+ (instancetype)sharedService;

/// Vendor SDK adapter. Inject a `CPChargerSimulatorAdapter` in tests to get
/// deterministic outcomes. In production leave as nil — commands will await
/// real hardware acknowledgment (or time out after 8 seconds).
@property (nonatomic, strong, nullable) id<CPChargerAdapterProtocol> adapter;

/// Fetch all chargers from Core Data.
- (NSArray *)fetchAllChargers;

/// Fetch a single charger by UUID.
- (nullable id)fetchChargerWithUUID:(NSString *)uuid;

/// Update charger status from vendor SDK data. Creates immutable ChargerEvent.
- (void)updateCharger:(NSString *)chargerUUID
               status:(NSString *)status
               detail:(nullable NSString *)detail;

/// Issue a command to a charger. Completes within 8 seconds or marks PendingReview.
/// commandType: one of "RemoteStart", "RemoteStop", "SoftReset", "ParameterPush"
/// parameters: JSON-serializable dict for the command
- (void)issueCommandToCharger:(NSString *)chargerUUID
                  commandType:(NSString *)commandType
                   parameters:(nullable NSDictionary *)parameters
                   completion:(void (^)(BOOL acknowledged, NSString *commandUUID, NSError * _Nullable error))completion;

/// Get pending review commands.
- (NSArray *)fetchPendingReviewCommands;

/// Retry a pending review command.
- (void)retryCommand:(NSString *)commandUUID
          completion:(void (^)(BOOL acknowledged, NSError * _Nullable error))completion;

/// Register charger with vendor SDK parameters.
- (void)registerCharger:(NSString *)chargerUUID
             parameters:(NSDictionary *)parameters;

#if DEBUG
/// Override the command acknowledgement timeout used by the internal dispatch timer.
/// Default is 0 (no override — the production 8-second constant is used).
/// Set to a short value such as 0.5 in tests that exercise the timeout path so the
/// test completes in < 2 s instead of waiting the full 8 s.
/// Automatically reset to 0 by cancelAllPendingCommandsForTesting.
@property (nonatomic) NSTimeInterval commandTimeoutIntervalOverride;

/// Cancel all pending command timers and clear pending completion blocks.
/// Call in test tearDown to prevent timer state from leaking between test cases
/// when the service singleton is shared across tests.
- (void)cancelAllPendingCommandsForTesting;
#endif

@end

NS_ASSUME_NONNULL_END
