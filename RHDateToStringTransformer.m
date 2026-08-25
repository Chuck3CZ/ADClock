#import "RHDateToStringTransformer.h"


@implementation RHDateToStringTransformer

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (Class)transformedValueClass;
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation;
{
    return NO;   
}

// TRANSFORMING WORK
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)transformedValue:(id)value;
{
	if(![value isKindOfClass:[NSDate class]])
		return nil;
	
	NSDate *date = value;
	
	if([[NSCalendar currentCalendar] isDateInToday:date])
	{
		NSString *todayStr = NSLocalizedString(@"Today", @"Today");
		
		NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
		[df setFormatterBehavior:NSDateFormatterBehavior10_4];
		[df setDateStyle:NSDateFormatterNoStyle];
		[df setTimeStyle:NSDateFormatterShortStyle];
		
		return [NSString stringWithFormat:@"%@ %@", todayStr, [df stringFromDate:date]]; 
	}
	else if([[NSCalendar currentCalendar] isDateInYesterday:date])
	{
		NSString *yesterdayStr = NSLocalizedString(@"Yesterday", @"Yesterday");
		
		NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
		[df setFormatterBehavior:NSDateFormatterBehavior10_4];
		[df setDateStyle:NSDateFormatterNoStyle];
		[df setTimeStyle:NSDateFormatterShortStyle];
		
		return [NSString stringWithFormat:@"%@ %@", yesterdayStr, [df stringFromDate:date]]; 
	}
	else
	{
		NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
		[df setFormatterBehavior:NSDateFormatterBehavior10_4];
		[df setDateStyle:NSDateFormatterMediumStyle];
		[df setTimeStyle:NSDateFormatterShortStyle];
		
		return [df stringFromDate:date];
	}
}

@end
