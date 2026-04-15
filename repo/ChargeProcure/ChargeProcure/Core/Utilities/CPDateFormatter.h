#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPDateFormatter : NSObject

+ (instancetype)sharedFormatter;

/// Format: "MMM d, yyyy" (e.g. "Apr 13, 2026")
- (NSString *)displayDateStringFromDate:(NSDate *)date;

/// Format: "MMM d, yyyy h:mm a" (e.g. "Apr 13, 2026 2:30 PM")
- (NSString *)displayDateTimeStringFromDate:(NSDate *)date;

/// Format: "h:mm a" (e.g. "2:30 PM")
- (NSString *)displayTimeStringFromDate:(NSDate *)date;

/// Format: "YYYYMMDD"
- (NSString *)compactDateStringFromDate:(NSDate *)date;

/// Parse ISO 8601 date string. Returns nil if parsing fails.
- (nullable NSDate *)dateFromISO8601String:(NSString *)string;

/// Format as ISO 8601 string.
- (NSString *)iso8601StringFromDate:(NSDate *)date;

/// Relative date string: "2 hours ago", "Yesterday", "3 days ago"
- (NSString *)relativeStringFromDate:(NSDate *)date;

/// Returns start and end of month containing given date.
- (void)startDate:(NSDate **)start endDate:(NSDate **)end forMonthContaining:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
