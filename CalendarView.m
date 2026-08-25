#import "CalendarView.h"
#import "CalendarAdditions.h"

@implementation CalendarView

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect]) != nil)
	{
		// Initialize date
		date = [[NSDate alloc] init];
		
		// Setup image
		NSBundle *bundle  = [NSBundle bundleForClass:[self class]];
		NSString *imgPath = [bundle pathForImageResource:@"CalendarBack.tiff"];	
		image = [[NSImage alloc] initWithContentsOfFile:imgPath];
		
		// Setup display attributes
		NSFont *displayFont = [NSFont labelFontOfSize:[NSFont labelFontSize]];
		
		NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
		[paragraphStyle setAlignment:NSTextAlignmentCenter];
		
		attributes = [[NSMutableDictionary alloc] initWithCapacity:2];
		[attributes setObject:displayFont    forKey:NSFontAttributeName];
		[attributes setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		// Determine what the first day of the week is based on the user's locale
		// Sunday = 1
		// Monday = 2
		// etc...
		// We subtract one because the internal code uses Sunday as 0
		// This makes it easier to do modulus arithmetic (i = ++i % 7)
		firstDayOfWeek = [[NSCalendar currentCalendar] firstWeekday] - 1;
		
		// Setup weekdays array, which contains the initials for the days of the week
		// The weekdays array is in the proper order for the current locale
		NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
		NSArray *shortWeekDays = [formatter shortWeekdaySymbols];
		NSMutableArray *weekdaysTemp = [NSMutableArray arrayWithCapacity:7];
		NSUInteger i = firstDayOfWeek;
		while([weekdaysTemp count] < 7)
		{
			[weekdaysTemp addObject:[[shortWeekDays objectAtIndex:i] substringToIndex:1]];
			i = (i+1) % 7;
		}
		
		weekdays = [weekdaysTemp copy];
	}
	return self;
}

- (void)dealloc
{
	[date release];
	[image release];
	[attributes release];
	[weekdays release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PUBLIC METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Changes the date displayed on the calendar.
 * 
 * Explanation of 'withValidDay' flag.
 * When changing from month to month, or year to year, it is generally desirable to keep the selected day the same.
 * For example, if you select May 20th, and then switch to April, you would expect the date to be April 20th.
 * However, this is not always possible, as there are not the same number of days in each month.
 * 
 * If you set the validDay flag to true, the calendar will switch to that exact day.
 * If you set the validDay flag to false, the calendar will attempt to keep the day the same, and if that's not possible
 * then it will use the given day passed in the newDate parameter.
**/
- (void)setCalendarDate:(NSDate *)newDate withValidDay:(BOOL)flag
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *newComponents = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:newDate];
	if(flag == false)
	{
		NSDateComponents *components = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:date];
		NSInteger day = (components.day > [date daysInMonth]) ? [date daysInMonth] : components.day;
		newComponents.day = day;
		
	}
	[date autorelease];
	date = [[calendar dateFromComponents:newComponents] retain];
	[self setNeedsDisplay:YES];
}

/**
 * Returns the date currently selected on the calendar.
 * The returned date is an autoreleased copy.
**/
- (NSDate *)calendarDate
{
	return [[date copy] autorelease];
}

/**
 * I find it easier to use a 'flipped' view for the particular drawing done in this class.
**/
- (BOOL)isFlipped
{
	return YES;
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
	
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *components = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:date];
	NSInteger firstCell = 0 - [date startingWeekdayOfMonth] + 1 + firstDayOfWeek;
	int offset = (firstCell > 1) ? -7 : 0;
	
	int row, col;
	BOOL found = NO;
	BOOL different = NO;
	for(row=0; row<=5 && !found; row++)
	{
		for(col=0; col<7 && !found; col++)
		{
			int x =  5 + (col * 17);
			int y = 21 + (row * 14);
			
			if(pt.x >= x && pt.x <= x+17 && pt.y >= y && pt.y <=y+13)
			{
				NSInteger num = (row * 7) + col - [date startingWeekdayOfMonth] + 1 + firstDayOfWeek + offset;

				if(num > 0 && num <= [date daysInMonth])
				{
					if(components.day != num) different = YES;
					
					[date autorelease];
					[components setDay:num];
					[components setHour:0];
					[components setMinute:0];
					[components setSecond:0];
					date = [calendar dateFromComponents:components];
					
					found = YES;
				}
			}
		}
	}
	
	if(found && different) [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event
{
	// If the user drags the mouse across the calendar, we want the selected date to follow the mouse.
	// Thus we fire a mouseDown event while the user is dragging their mouse across the calendar.
	[self mouseDown:event];
}

- (void)drawRect:(NSRect)rect
{	
	// Draw background image
	[image drawInRect:NSMakeRect(0, 0, 130, 113)];
	
	NSRect displayRect;
	displayRect.size.width  = 17;
	displayRect.size.height = 13;
	
	// Draw table headers
	int i;
	for(i = 0; i < 7; i++)
	{
		displayRect.origin.x = 5 + (i * 17);
		displayRect.origin.y = 5;
		[[weekdays objectAtIndex:i] drawInRect:displayRect withAttributes:attributes];
	}
	
	// Draw days of the month
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSInteger currentDay = [calendar component:NSCalendarUnitDay fromDate:date];
	
	NSInteger firstCell = 0 - [date startingWeekdayOfMonth] + 1 + firstDayOfWeek;
	int offset = (firstCell > 1) ? -7 : 0;
	
	int row, col;
	for(row = 0; row <= 5; row++)
	{
		for(col = 0; col < 7; col++)
		{
			NSInteger num = (row * 7) + col - [date startingWeekdayOfMonth] + 1 + firstDayOfWeek + offset;
			
			displayRect.origin.x =  5 + (col * 17);
			displayRect.origin.y = 21 + (row * 14);
			
			if(num > 0 && num <= [date daysInMonth])
			{
				if(num == currentDay)
				{
					[[NSColor selectedTextBackgroundColor] set];
					[NSBezierPath fillRect:displayRect];
				}
				
				NSString *displayStr = [NSString stringWithFormat:@"%lu", num];
				[displayStr drawInRect:displayRect withAttributes:attributes];
			}
		}
	}
}

@end
