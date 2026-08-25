#import "CalendarAdditions.h"

@implementation NSDate (CalendarAdditions)

// FOR COMPARING DATES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns whether or not the current calendarDate is earlier then the given calendarDate.
 Note: If they represent the same date in time, this method returns false.
 Note: Doesn't take into effect the timeZone representation. Just the internal NSDate absolute time.
**/
- (BOOL)isEarlierDate:(NSDate *)anotherDate
{
	return [self timeIntervalSinceDate:anotherDate] < 0;
}

/**
 Returns whether or not the current calendarDate is later then the given calendarDate.
 Note: If they represent the same date in time, this method returns false.
 Note: Doesn't take into effect the timeZone representation. Just the internal NSDate absolute time.
**/
- (BOOL)isLaterDate:(NSDate *)anotherDate
{
	return [self timeIntervalSinceDate:anotherDate] > 0;
}

// FOR EXTRACTING PRECISION DATE COMPONENTS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns an NSTimeInterval within the minute.
 This can be used to determine both the number of seconds, and milliseconds, of the time within the current minute.
 IE - if the time is 5:42:36.238 AM, this method would return 36.238.
 
 typedef double NSTimeInterval: Always in seconds; yields submillisecond precision...
**/
- (NSTimeInterval)intervalOfMinute
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *components = [calendar components:NSCalendarUnitSecond|NSCalendarUnitNanosecond fromDate:self];
	
	double sec = components.second;
	double nano = components.nanosecond;
	
	NSTimeInterval result = sec + (nano * 1.0e-9);
	//NSLog(@"intervalOfMinute: %f", result);
	
	return result;
}

/**
 Returns an NSTimeInterval within the day.
 This can be used to determine both the number of seconds, and milliseconds, of the time within the current day.
 IE - if the time is 12:01:02.003 AM, this method would return 62.003.
 
 typedef double NSTimeInterval: Always in seconds; yields submillisecond precision...
 **/
- (NSTimeInterval)intervalOfDay
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *components = [calendar components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond|NSCalendarUnitNanosecond fromDate:self];
	
	double sec = components.hour * 3600 + components.minute * 60 + components.second;
	double nano = components.nanosecond;
	
	NSTimeInterval result = sec + (nano * 1.0e-9);
	//NSLog(@"intervalOfDay: %f", result);
	
	return result;
}

// FOR LAYING OUT CALENDARS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns the number of days in the current month for this calendarDate.
**/
- (NSUInteger)daysInMonth
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay
								  inUnit:NSCalendarUnitMonth
								 forDate:self];
	return days.length;
}

/**
 Returns the number of months in the current year for this calendarDate.
 Fixme: do we need it for some exotic calendar?
 **/
- (NSUInteger)monthsInYear
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSRange months = [calendar rangeOfUnit:NSCalendarUnitMonth
									inUnit:NSCalendarUnitYear
								   forDate:self];
	return months.length;
	
}

/**
 Returns the weekday of the first day of the month for this calendarDate.
**/
- (NSUInteger)startingWeekdayOfMonth
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *firstDayOfMonth;
	[calendar rangeOfUnit:NSCalendarUnitMonth
				startDate:&firstDayOfMonth
				 interval:nil
				  forDate:self];
	NSUInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:firstDayOfMonth];
	return weekday - 1;
}

// FOR ALTERING DATES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Rolls the current time by the specified amount.
 Rolling means that if the time overflows for one field, it loops, and doesn't affect the other fields.
 IE - if the time was 4:55, and you rolled the time 6 minutes, it would now be 4:01
**/
- (NSDate *)dateByRollingYears:(int)year months:(int)month days:(int)day hours:(int)hour minutes:(int)minute seconds:(int)second
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *components = [calendar components:NSCalendarUnitYear |
									NSCalendarUnitMonth |
									NSCalendarUnitDay |
									NSCalendarUnitHour |
									NSCalendarUnitMinute |
									NSCalendarUnitSecond
											   fromDate:self];
	// Make the common case fast.
	// Common case:  only one variable is being rolled.
	
	// Roll seconds (always 60)
	if(second != 0)
	{
		components.second = (components.second + second) % 60;
	}
	
	// Roll minutes (always 60)
	if(minute != 0)
	{
		components.minute = (components.minute + minute) % 60;
	}
	
	// Roll hours (always 24)
	if(hour != 0)
	{
		components.hour = (components.hour + hour) % 24;
	}
	
	// Roll days (variable, starts @ 1)
	if(day != 0)
	{
		NSUInteger d = [self daysInMonth];
		components.day = ((components.day - 1) + day) % d + 1;
	}
	
	// Roll months (variable??, starts @ 1)
	if(month != 0)
	{
		NSUInteger m = [self monthsInYear];
		components.month = ((components.month - 1) + month) % m + 1;
	}
	
	return [calendar dateFromComponents:components];
}

/**
 Returns a calendar date with the same local time as this one, for the new time zone.
 That is, if the local time for this date is 10:00AM, the local time for the new date will be 10:00AM in it's time zone.
**/
- (NSDate *)dateBySwitchingToTimeZone:(NSTimeZone *)newTimeZone
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *components = [calendar components:NSCalendarUnitYear |
									NSCalendarUnitMonth |
									NSCalendarUnitDay |
									NSCalendarUnitHour |
									NSCalendarUnitMinute |
									NSCalendarUnitSecond |
									NSCalendarUnitTimeZone
											   fromDate:self];
	if (components.timeZone != newTimeZone) {
		components.timeZone = newTimeZone;
	}
	
	return [calendar dateFromComponents:components];
}

@end
