//
//  CPChargerSimulatorAdapter.h
//  ChargeProcure
//
//  Deterministic in-process adapter used by XCTests and simulator builds.
//  Replaces the previously hard-coded arc4random_uniform simulation with
//  a configurable, injectable implementation of CPChargerAdapterProtocol.
//
//  Do NOT use in production builds — leave CPChargerService.adapter as nil
//  to engage the hardware ACK path.
//

#import <Foundation/Foundation.h>
#import "CPChargerService.h"

NS_ASSUME_NONNULL_BEGIN

@interface CPChargerSimulatorAdapter : NSObject <CPChargerAdapterProtocol>

/// When YES (default) the adapter calls back with success=YES after `responseDelay`.
/// Set to NO to force a failure response, exercising the timeout/PendingReview path.
@property (nonatomic, assign) BOOL shouldSucceed;

/// Delay before the adapter fires the completion block, in seconds.
/// Default: 0.1 (fast). Set to > kCommandTimeoutInterval to trigger timeout.
@property (nonatomic, assign) NSTimeInterval responseDelay;

/// Creates a fast-succeed adapter (responseDelay=0.1, shouldSucceed=YES).
+ (instancetype)fastSucceedAdapter;

/// Creates a fast-fail adapter (responseDelay=0.1, shouldSucceed=NO).
+ (instancetype)fastFailAdapter;

/// Creates an adapter that always times out by delaying past the 8-second threshold.
+ (instancetype)timeoutAdapter;

@end

NS_ASSUME_NONNULL_END
