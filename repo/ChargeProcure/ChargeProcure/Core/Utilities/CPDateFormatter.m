#import "CPDateFormatter.h"

@interface CPDateFormatter ()

@property (nonatomic, strong) NSDateFormatter *displayDateFormatter;
@property (nonatomic, strong) NSDateFormatter *displayDateTimeFormatter;
@property (nonatomic, strong) NSDateFormatter *displayTimeFormatter;
@property (nonatomic, strong) NSDateFormatter *compactDateFormatter;
@property (nonatomic, strong) NSDateFormatter *iso8601Formatter;
@property (nonatomic, strong) NSCalendar *calendar;

@end

@implementation CPDateFormatter

+ (instancetype)sharedFormatter {
    static CPDateFormatter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPDateFormatter alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _initFormatters];
    }
    return self;
}

- (void)_initFormatters {
    NSLocale *enUS = [NSLocale localeWithLocaleIdentifier:@"en_US"];

    // Display date: "Apr 13, 2026"
    _displayDateFormatter = [[NSDateFormatter alloc] init];
    _displayDateFormatter.dateFormat = @"MMM d, yyyy";
    _displayDateFormatter.locale = enUS;

    // Display date-time: "Apr 13, 2026 2:30 PM"
    _displayDateTimeFormatter = [[NSDateFormatter alloc] init];
    _displayDateTimeFormatter.dateFormat = @"MMM d, yyyy h:mm a";
    _displayDateTimeFormatter.locale = enUS;

    // Display time: "2:30 PM"
    _displayTimeFormatter = [[NSDateFormatter alloc] init];
    _displayTimeFormatter.dateFormat = @"h:mm a";
    _displayTimeFormatter.locale = enUS;

    // Compact date: "20260413"
    _compactDateFormatter = [[NSDateFormatter alloc] init];
    _compactDateFormatter.dateFormat = @"yyyyMMdd";
    _compactDateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    // ISO 8601
    _iso8601Formatter = [[NSDateFormatter alloc] init];
    _iso8601Formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    _iso8601Formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    _iso8601Formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

    // Calendar for month calculations
    _calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    _calendar.locale = enUS;
}

#pragma mark - Public API

- (NSString *)displayDateStringFromDate:(NSDate *)date {
    NSAssert(date != nil, @"date must not be nil");
    return [self.displayDateFormatter stringFromDate:date];
}

- (NSString *)displayDateTimeStringFromDate:(NSDate *)date {
    NSAssert(date != nil, @"date must not be nil");
    return [self.displayDateTimeFormatter stringFromDate:date];
}

- (NSString *)displayTimeStringFromDate:(NSDate *)date {
    NSAssert(date != nil, @"date must not be nil");
    return [self.displayTimeFormatter stringFromDate:date];
}

- (NSString *)compactDateStringFromDate:(NSDate *)date {
    NSAssert(date != nil, @"date must not be nil");
    return [self.compactDateFormatter stringFromDate:date];
}

- (nullable NSDate *)dateFromISO8601String:(NSString *)string {
    if (string.length == 0) {
        return nil;
    }
    return [self.iso8601Formatter dateFromString:string];
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    NSAssert(date != nil, @"date must not be nil");
    return [self.iso8601Formatter stringFromDate:date];
}

- (NSString *)relativeStringFromDate:(NSDate *)date {
    NSAssert(date != nil, @"date must not be nil");

    NSDate *now = [NSDate date];
    NSTimeInterval delta = [now timeIntervalSinceDate:date];

    // Future dates — return absolute display string
    if (delta < 0) {
        return [self displayDateStringFromDate:date];
    }

    // Less than 1 minute
    if (delta < 60.0) {
        return @"Just now";
    }

    // Less than 1 hour — show minutes
    if (delta < 3600.0) {
        NSInteger minutes = (NSInteger)(delta / 60.0);
        return minutes == 1 ? @"1 minute ago"
                            : [NSString stringWithFormat:@"%ld minutes ago", (long)minutes];
    }

    // Less than 24 hours — show hours
    if (delta < 86400.0) {
        NSInteger hours = (NSInteger)(delta / 3600.0);
        return hours == 1 ? @"1 hour ago"
                          : [NSString stringWithFormat:@"%ld hours ago", (long)hours];
    }

    // Check if yesterday (calendar-aware)
    NSDate *startOfToday = [self.calendar startOfDayForDate:now];
    NSDate *startOfYesterday = [self.calendar dateByAddingUnit:NSCalendarUnitDay
                                                         value:-1
                                                        toDate:startOfToday
                                                       options:0];
    NSDate *startOfDate = [self.calendar startOfDayForDate:date];

    if ([startOfDate isEqualToDate:startOfYesterday]) {
        return @"Yesterday";
    }

    // Less than 7 days — show days
    if (delta < 7 * 86400.0) {
        NSInteger days = (NSInteger)(delta / 86400.0);
        return days == 1 ? @"1 day ago"
                         : [NSString stringWithFormat:@"%ld days ago", (long)days];
    }

    // Less than 4 weeks — show weeks
    if (delta < 28 * 86400.0) {
        NSInteger weeks = (NSInteger)(delta / (7 * 86400.0));
        return weeks == 1 ? @"1 week ago"
                          : [NSString stringWithFormat:@"%ld weeks ago", (long)weeks];
    }

    // Older — fall back to display date
    return [self displayDateStringFromDate:date];
}

- (void)startDate:(NSDate **)start endDate:(NSDate **)end forMonthContaining:(NSDate *)date {
    NSAssert(date != nil, @"date must not be nil");

    NSDateComponents *components = [self.calendar
        components:(NSCalendarUnitYear | NSCalendarUnitMonth)
          fromDate:date];

    // Start = first day of month at midnight
    NSDate *monthStart = [self.calendar dateFromComponents:components];

    // End = first day of next month (exclusive upper bound)
    NSDateComponents *oneMonth = [[NSDateComponents alloc] init];
    oneMonth.month = 1;
    NSDate *monthEnd = [self.calendar dateByAddingComponents:oneMonth
                                                      toDate:monthStart
                                                     options:0];

    if (start) { *start = monthStart; }
    if (end)   { *end   = monthEnd;   }
}

@end
