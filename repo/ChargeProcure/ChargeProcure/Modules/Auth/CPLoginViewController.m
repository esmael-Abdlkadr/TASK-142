//
//  CPLoginViewController.m
//  ChargeProcure
//
//  Full-screen login screen. Built entirely in code using Auto Layout.
//  Handles password/biometric authentication, lockout display, keyboard
//  avoidance, and root-VC replacement on success.
//

#import "CPLoginViewController.h"
#import "CPAuthService.h"
#import "AppDelegate.h"

#import <LocalAuthentication/LocalAuthentication.h>

// MARK: - Private interface

@interface CPLoginViewController () <UITextFieldDelegate>

// MARK: UI elements
@property (nonatomic, strong) UIScrollView      *scrollView;
@property (nonatomic, strong) UIView            *contentView;       // Inside scroll view
@property (nonatomic, strong) UILabel           *logoLabel;
@property (nonatomic, strong) UILabel           *appSubtitleLabel;
@property (nonatomic, strong) UITextField       *usernameField;
@property (nonatomic, strong) UITextField       *passwordField;
@property (nonatomic, strong) UIButton          *loginButton;
@property (nonatomic, strong) UIButton          *biometricButton;   // Hidden when unavailable
@property (nonatomic, strong) UILabel           *lockoutLabel;      // Red, shown on lockout
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

// MARK: State
@property (nonatomic, assign) BOOL biometricAvailable;
@property (nonatomic, strong) LAContext *laContext;

// MARK: Keyboard tracking
@property (nonatomic, assign) CGFloat keyboardHeight;

@end

// MARK: - Implementation

@implementation CPLoginViewController

// MARK: - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationController.navigationBar.hidden = YES;

    [self checkBiometricAvailability];
    [self buildUI];
    [self applyConstraints];
    [self setupKeyboardHandling];
    [self setupDismissKeyboardGesture];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBar.hidden = NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: - Biometric detection

- (void)checkBiometricAvailability {
    self.laContext = [[LAContext alloc] init];
    NSError *error = nil;
    self.biometricAvailable =
        [self.laContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                                    error:&error];
}

// MARK: - UI construction

- (void)buildUI {
    // --- Scroll view (keyboard avoidance container) ---
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode  = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    // --- Logo label (replaces an image view for code-only approach) ---
    self.logoLabel = [[UILabel alloc] init];
    self.logoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.logoLabel.text = @"⚡";
    self.logoLabel.font = [UIFont systemFontOfSize:72.0 weight:UIFontWeightBold];
    self.logoLabel.textAlignment = NSTextAlignmentCenter;
    self.logoLabel.accessibilityLabel = NSLocalizedString(@"ChargeProcure Logo", nil);
    self.logoLabel.accessibilityTraits = UIAccessibilityTraitImage;
    [self.contentView addSubview:self.logoLabel];

    // --- App subtitle ---
    self.appSubtitleLabel = [[UILabel alloc] init];
    self.appSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.appSubtitleLabel.text = NSLocalizedString(@"ChargeProcure", nil);
    self.appSubtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    self.appSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.appSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.appSubtitleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.appSubtitleLabel];

    // --- Username field ---
    self.usernameField = [self makeTextFieldWithPlaceholder:NSLocalizedString(@"Username", nil)
                                              keyboardType:UIKeyboardTypeDefault
                                            secureTextEntry:NO
                                          accessibilityLabel:NSLocalizedString(@"Username field", nil)];
    self.usernameField.returnKeyType = UIReturnKeyNext;
    self.usernameField.textContentType = UITextContentTypeUsername;
    self.usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.usernameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.usernameField.accessibilityIdentifier = @"loginUsernameField";
    [self.contentView addSubview:self.usernameField];

    // --- Password field ---
    self.passwordField = [self makeTextFieldWithPlaceholder:NSLocalizedString(@"Password", nil)
                                              keyboardType:UIKeyboardTypeDefault
                                            secureTextEntry:YES
                                          accessibilityLabel:NSLocalizedString(@"Password field", nil)];
    self.passwordField.returnKeyType = UIReturnKeyGo;
    self.passwordField.textContentType = UITextContentTypePassword;
    self.passwordField.accessibilityIdentifier = @"loginPasswordField";
    [self.contentView addSubview:self.passwordField];

    // --- Lockout label ---
    self.lockoutLabel = [[UILabel alloc] init];
    self.lockoutLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.lockoutLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.lockoutLabel.adjustsFontForContentSizeCategory = YES;
    self.lockoutLabel.textColor = [UIColor systemRedColor];
    self.lockoutLabel.textAlignment = NSTextAlignmentCenter;
    self.lockoutLabel.numberOfLines = 0;
    self.lockoutLabel.hidden = YES;
    self.lockoutLabel.accessibilityTraits = UIAccessibilityTraitStaticText;
    [self.contentView addSubview:self.lockoutLabel];

    // --- Login button ---
    self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginButton setTitle:NSLocalizedString(@"Sign In", nil) forState:UIControlStateNormal];
    self.loginButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.loginButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.loginButton.backgroundColor = [UIColor systemBlueColor];
    [self.loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.loginButton.layer.cornerRadius = 12.0;
    self.loginButton.layer.masksToBounds = YES;
    self.loginButton.accessibilityLabel = NSLocalizedString(@"Sign in button", nil);
    self.loginButton.accessibilityIdentifier = @"loginButton";
    [self.loginButton addTarget:self
                         action:@selector(loginButtonTapped:)
               forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.loginButton];

    // --- Activity indicator ---
    self.activityIndicator = [[UIActivityIndicatorView alloc]
                               initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    self.activityIndicator.color = [UIColor whiteColor];
    [self.loginButton addSubview:self.activityIndicator];

    // --- Biometric button ---
    self.biometricButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.biometricButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self configureBiometricButton];
    self.biometricButton.hidden = !self.biometricAvailable;
    [self.biometricButton addTarget:self
                             action:@selector(biometricButtonTapped:)
                   forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.biometricButton];
}

/// Creates a styled UITextField.
- (UITextField *)makeTextFieldWithPlaceholder:(NSString *)placeholder
                                 keyboardType:(UIKeyboardType)keyboardType
                               secureTextEntry:(BOOL)secure
                            accessibilityLabel:(NSString *)a11yLabel {
    UITextField *tf = [[UITextField alloc] init];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.placeholder = placeholder;
    tf.keyboardType = keyboardType;
    tf.secureTextEntry = secure;
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    tf.adjustsFontForContentSizeCategory = YES;
    tf.accessibilityLabel = a11yLabel;
    tf.delegate = self;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    return tf;
}

/// Configures the biometric button's image and accessibility label based on
/// the available biometric type (Face ID or Touch ID).
- (void)configureBiometricButton {
    NSString *imageName;
    NSString *a11yLabel;

    if (@available(iOS 11.0, *)) {
        if (self.laContext.biometryType == LABiometryTypeFaceID) {
            imageName = @"faceid";
            a11yLabel = NSLocalizedString(@"Sign in with Face ID", nil);
        } else if (self.laContext.biometryType == LABiometryTypeTouchID) {
            imageName = @"touchid";
            a11yLabel = NSLocalizedString(@"Sign in with Touch ID", nil);
        } else {
            imageName = @"touchid";
            a11yLabel = NSLocalizedString(@"Sign in with Biometrics", nil);
        }
    } else {
        imageName = @"touchid";
        a11yLabel = NSLocalizedString(@"Sign in with Touch ID", nil);
    }

    UIImage *icon = [UIImage systemImageNamed:imageName];
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:36.0 weight:UIImageSymbolWeightLight];
    icon = [icon imageByApplyingSymbolConfiguration:config];

    [self.biometricButton setImage:icon forState:UIControlStateNormal];
    self.biometricButton.tintColor = [UIColor systemBlueColor];
    self.biometricButton.accessibilityLabel = a11yLabel;
}

// MARK: - Auto Layout

- (void)applyConstraints {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    CGFloat margin = 40.0;

    // Scroll view fills the safe area.
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor      constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor   constraintEqualToAnchor:safe.bottomAnchor],
    ]];

    // Content view fills the scroll view's content area and is at least as
    // tall as the frame so the content stays centred when there is room.
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor      constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor  constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor   constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        // Width = scroll view frame width (prevents horizontal scrolling).
        [self.contentView.widthAnchor    constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
        // Minimum height keeps items vertically centred.
        [self.contentView.heightAnchor   constraintGreaterThanOrEqualToAnchor:self.scrollView.frameLayoutGuide.heightAnchor],
    ]];

    // Standard field height.
    CGFloat fieldHeight = 50.0;
    CGFloat buttonHeight = 52.0;

    [NSLayoutConstraint activateConstraints:@[
        // Logo — vertically centred in the top portion.
        [self.logoLabel.topAnchor       constraintEqualToAnchor:self.contentView.topAnchor constant:60.0],
        [self.logoLabel.centerXAnchor   constraintEqualToAnchor:self.contentView.centerXAnchor],

        // App subtitle.
        [self.appSubtitleLabel.topAnchor      constraintEqualToAnchor:self.logoLabel.bottomAnchor constant:8.0],
        [self.appSubtitleLabel.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:margin],
        [self.appSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-margin],

        // Username field.
        [self.usernameField.topAnchor      constraintEqualToAnchor:self.appSubtitleLabel.bottomAnchor constant:40.0],
        [self.usernameField.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:margin],
        [self.usernameField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-margin],
        [self.usernameField.heightAnchor   constraintEqualToConstant:fieldHeight],

        // Password field.
        [self.passwordField.topAnchor      constraintEqualToAnchor:self.usernameField.bottomAnchor constant:16.0],
        [self.passwordField.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:margin],
        [self.passwordField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-margin],
        [self.passwordField.heightAnchor   constraintEqualToConstant:fieldHeight],

        // Lockout label.
        [self.lockoutLabel.topAnchor      constraintEqualToAnchor:self.passwordField.bottomAnchor constant:8.0],
        [self.lockoutLabel.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:margin],
        [self.lockoutLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-margin],

        // Login button.
        [self.loginButton.topAnchor      constraintEqualToAnchor:self.lockoutLabel.bottomAnchor constant:24.0],
        [self.loginButton.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:margin],
        [self.loginButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-margin],
        [self.loginButton.heightAnchor   constraintEqualToConstant:buttonHeight],

        // Activity indicator centred inside the login button.
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.loginButton.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.loginButton.centerYAnchor],

        // Biometric button.
        [self.biometricButton.topAnchor     constraintEqualToAnchor:self.loginButton.bottomAnchor constant:20.0],
        [self.biometricButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.biometricButton.widthAnchor   constraintEqualToConstant:60.0],
        [self.biometricButton.heightAnchor  constraintEqualToConstant:60.0],

        // Bottom padding.
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.biometricButton.bottomAnchor
                                                                   constant:60.0],
    ]];
}

// MARK: - Keyboard handling

- (void)setupKeyboardHandling {
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(keyboardWillShow:)
     name:UIKeyboardWillShowNotification
     object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(keyboardWillHide:)
     name:UIKeyboardWillHideNotification
     object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info  = notification.userInfo;
    CGRect keyboardRect = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve =
        (UIViewAnimationCurve)[info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    self.keyboardHeight = CGRectGetHeight(keyboardRect);
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, self.keyboardHeight, 0);

    [UIView animateWithDuration:duration
                          delay:0
                        options:(UIViewAnimationOptions)(curve << 16)
                     animations:^{
        self.scrollView.contentInset          = insets;
        self.scrollView.scrollIndicatorInsets = insets;
    } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve =
        (UIViewAnimationCurve)[info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    self.keyboardHeight = 0.0;

    [UIView animateWithDuration:duration
                          delay:0
                        options:(UIViewAnimationOptions)(curve << 16)
                     animations:^{
        self.scrollView.contentInset          = UIEdgeInsetsZero;
        self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    } completion:nil];
}

- (void)setupDismissKeyboardGesture {
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

// MARK: - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.usernameField) {
        [self.passwordField becomeFirstResponder];
    } else if (textField == self.passwordField) {
        [self.passwordField resignFirstResponder];
        [self attemptLogin];
    }
    return YES;
}

// MARK: - Actions

- (IBAction)loginButtonTapped:(id)sender {
    [self dismissKeyboard];
    [self attemptLogin];
}

- (IBAction)biometricButtonTapped:(id)sender {
    [self attemptBiometricLogin];
}

// MARK: - Authentication logic

- (void)attemptLogin {
    NSString *username = [self.usernameField.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = self.passwordField.text ?: @"";

    if (username.length == 0 || password.length == 0) {
        [self shakeButton:self.loginButton];
        return;
    }

    [self setLoginInProgress:YES];

    [[CPAuthService sharedService]
     loginWithUsername:username
     password:password
     completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setLoginInProgress:NO];

            if (success) {
                [self handleLoginSuccess];
            } else {
                [self handleLoginFailure:error];
            }
        });
    }];
}

- (void)attemptBiometricLogin {
    [[CPAuthService sharedService]
     authenticateWithBiometrics:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self handleLoginSuccess];
            } else {
                if (error) {
                    NSLog(@"[CPLoginViewController] Biometric auth failed: %@",
                          error.localizedDescription);
                }
            }
        });
    }];
}

// MARK: - Login result handling

- (void)handleLoginSuccess {
    self.lockoutLabel.hidden = YES;
    self.passwordField.text  = @"";

    // F-06: Force password rotation for seeded default accounts.
    if ([CPAuthService sharedService].needsPasswordChange) {
        [self promptForcedPasswordChange];
        return;
    }
    [self configureRootViewController];
}

// MARK: - Forced password-change flow (first login with bootstrap account)

- (void)promptForcedPasswordChange {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Password Change Required", nil)
        message:NSLocalizedString(@"Set a new password to continue. Minimum 10 characters, at least 1 digit.", nil)
        preferredStyle:UIAlertControllerStyleAlert];

    // No "current password" field — the bootstrap password is randomly generated
    // and not intended to be known by the user.
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = NSLocalizedString(@"New password (min 10 chars, 1 digit)", nil);
        tf.secureTextEntry = YES;
        tf.returnKeyType = UIReturnKeyNext;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = NSLocalizedString(@"Confirm new password", nil);
        tf.secureTextEntry = YES;
        tf.returnKeyType = UIReturnKeyDone;
    }];

    UIAlertAction *changeAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Set Password", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
        NSString *new1 = alert.textFields[0].text ?: @"";
        NSString *new2 = alert.textFields[1].text ?: @"";
        [self commitForcedPasswordChange:new1 confirm:new2];
    }];
    [alert addAction:changeAction];
    // No cancel action — the change is mandatory.
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)commitForcedPasswordChange:(NSString *)newPassword
                            confirm:(NSString *)confirmPassword {
    if (![newPassword isEqualToString:confirmPassword]) {
        [self showPasswordChangeError:NSLocalizedString(@"New passwords do not match.", nil)];
        return;
    }
    NSError *error = nil;
    NSString *userID = [CPAuthService sharedService].currentUserID;
    BOOL ok = [[CPAuthService sharedService] forceChangePasswordForUserID:userID
                                                              newPassword:newPassword
                                                                    error:&error];
    if (!ok) {
        [self showPasswordChangeError:error.localizedDescription ?: NSLocalizedString(@"Password change failed.", nil)];
        return;
    }
    [self configureRootViewController];
}

- (void)showPasswordChangeError:(NSString *)message {
    UIAlertController *err = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Error", nil)
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *a) {
        [self promptForcedPasswordChange];
    }]];
    [self presentViewController:err animated:YES completion:nil];
}

- (void)handleLoginFailure:(nullable NSError *)error {
    [self shakeButton:self.loginButton];

    if (!error) {
        return;
    }

    if (error.domain == CPAuthErrorDomain &&
        error.code == CPAuthErrorLockedOut) {
        // Show lockout message with remaining time if available.
        NSNumber *minutes = error.userInfo[@"CPLockoutRemainingMinutes"];
        if (minutes) {
            self.lockoutLabel.text =
                [NSString stringWithFormat:
                 NSLocalizedString(@"Account locked. Try again in %@ minute(s).", nil),
                 minutes];
        } else {
            self.lockoutLabel.text = NSLocalizedString(@"Account locked. Please try again later.", nil);
        }
        self.lockoutLabel.hidden = NO;
    } else {
        self.lockoutLabel.hidden = YES;
        // Show generic error in an alert.
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Sign In Failed", nil)
                                                message:error.localizedDescription
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

// MARK: - Root VC transition

/// Asks the AppDelegate to configure the correct root view controller now
/// that the user is authenticated.
- (void)configureRootViewController {
    AppDelegate *appDelegate =
        (AppDelegate *)[[UIApplication sharedApplication] delegate];
    if ([appDelegate respondsToSelector:@selector(configureRootViewControllerForAuthState)]) {
        [appDelegate performSelector:@selector(configureRootViewControllerForAuthState)];
    }
}

// MARK: - UI helpers

/// Shows/hides the activity indicator and disables/enables interactive elements.
- (void)setLoginInProgress:(BOOL)inProgress {
    self.usernameField.enabled  = !inProgress;
    self.passwordField.enabled  = !inProgress;
    self.loginButton.enabled    = !inProgress;
    self.biometricButton.enabled = !inProgress;
    [self.loginButton setTitle:(inProgress ? @"" : NSLocalizedString(@"Sign In", nil))
                      forState:UIControlStateNormal];

    if (inProgress) {
        [self.activityIndicator startAnimating];
    } else {
        [self.activityIndicator stopAnimating];
    }
}

/// Applies a horizontal shake animation to a view to signal invalid input.
- (void)shakeButton:(UIView *)view {
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    shake.duration = 0.45;
    shake.values = @[@(-10), @(10), @(-8), @(8), @(-5), @(5), @(-2), @(2), @(0)];
    [view.layer addAnimation:shake forKey:@"shake"];
}

// MARK: - Dark Mode / trait changes

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // System colors update automatically; refresh any custom colours if needed.
    self.view.backgroundColor = [UIColor systemBackgroundColor];
}

@end
