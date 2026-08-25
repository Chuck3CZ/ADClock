#import <Foundation/Foundation.h>

@interface NSDate (CalendarAdditions)

// For comparing dates
- (BOOL)isEarlierDate:(NSDate *)anotherDate;
- (BOOL)isLaterDate:(NSDate *)anotherDate;

// For extracting precision date components
- (NSTimeInterval)intervalOfMinute;
- (NSTimeInterval)intervalOfDay;

// For laying out calendars
- (NSUInteger) daysInMonth;
- (NSUInteger) monthsInYear;
- (NSUInteger) startingWeekdayOfMonth;

// For altering dates
- (NSDate *)dateByRollingYears:(int)year months:(int)month days:(int)day hours:(int)hour minutes:(int)minute seconds:(int)second;
- (NSDate *)dateBySwitchingToTimeZone:(NSTimeZone *)newTimeZone;

@end
