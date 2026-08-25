#import <Cocoa/Cocoa.h>

@interface CalendarView : NSView
{
	NSDate *date;
	NSImage *image;
	NSMutableDictionary *attributes;
	
	NSUInteger firstDayOfWeek;
	NSArray *weekdays;
}
- (void)setCalendarDate:(NSDate *)date withValidDay:(BOOL)flag;
- (NSDate *)calendarDate;

@end
