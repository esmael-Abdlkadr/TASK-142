//
//  CPChargerSimulatorAdapter.m
//  ChargeProcure
//

#import "CPChargerSimulatorAdapter.h"

// Timeout interval must exceed kCommandTimeoutInterval=8.0 to guarantee a
// timeout in tests.  We use 10.0 seconds as a safe upper bound.
static const NSTimeInterval kTimeoutResponseDelay = 10.0;

@implementation CPChargerSimulatorAdapter

- (instancetype)init {
    self = [super init];
    if (self) {
        _shouldSucceed  = YES;
        _responseDelay  = 0.1;
    }
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Factory methods
// ---------------------------------------------------------------------------

+ (instancetype)fastSucceedAdapter {
    CPChargerSimulatorAdapter *a = [[CPChargerSimulatorAdapter alloc] init];
    a.shouldSucceed = YES;
    a.responseDelay = 0.1;
    return a;
}

+ (instancetype)fastFailAdapter {
    CPChargerSimulatorAdapter *a = [[CPChargerSimulatorAdapter alloc] init];
    a.shouldSucceed = NO;
    a.responseDelay = 0.1;
    return a;
}

+ (instancetype)timeoutAdapter {
    CPChargerSimulatorAdapter *a = [[CPChargerSimulatorAdapter alloc] init];
    a.shouldSucceed = NO;
    a.responseDelay = kTimeoutResponseDelay;
    return a;
}

// ---------------------------------------------------------------------------
#pragma mark - CPChargerAdapterProtocol
// ---------------------------------------------------------------------------

- (void)sendCommand:(NSString *)commandUUID
          toCharger:(NSString *)chargerUUID
        commandType:(NSString *)commandType
         parameters:(nullable NSDictionary *)parameters
         completion:(void (^)(BOOL success, NSString * _Nullable failureReason))completion {

    NSTimeInterval delay       = self.responseDelay;
    BOOL           shouldSucceed = self.shouldSucceed;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                   ^{
        if (shouldSucceed) {
            completion(YES, nil);
        } else {
            // Only fire the failure callback when not timing out.
            // A timeout is modelled by not calling completion at all within
            // the 8-second window so the CPChargerService timer fires instead.
            if (delay < 9.0) {
                completion(NO, @"Simulated adapter failure");
            }
            // delay >= 9.0 → the block fires after the 8-second timeout, so
            // CPChargerService has already marked the command PendingReview.
            // Calling completion at that point is a no-op (pending map cleared).
            else {
                completion(NO, @"Simulated adapter timeout");
            }
        }
    });
}

@end
