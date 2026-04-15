//
//  AppDelegate.h
//  ChargeProcure
//
//  Created by ChargeProcure Team.
//  Copyright © 2024 ChargeProcure. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : UIResponder <UIApplicationDelegate>

/// The app's main window.
@property (nonatomic, strong) UIWindow *window;

// MARK: - Low Power Mode

/**
 * Called when NSProcessInfoPowerStateDidChangeNotification fires.
 * Pauses or resumes background-intensive work according to the new power state.
 */
- (void)handlePowerStateDidChange:(NSNotification *)notification;

// MARK: - Navigation

/**
 * Configures the root view controller based on whether a session is active.
 * Call this after login or logout to switch between login and main navigation.
 */
- (void)configureRootViewControllerForAuthState;

@end

NS_ASSUME_NONNULL_END
