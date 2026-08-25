#import <Foundation/Foundation.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <unistd.h>

int main (int argc, const char * argv[])
{
	if(argc != 3) return -1;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSString *event = [NSString stringWithUTF8String:argv[1]];
	
	NSString *dateStr = [NSString stringWithUTF8String:argv[2]];
	NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:[dateStr doubleValue]];
	
	NSString *scheduler = [NSString stringWithUTF8String:getlogin()];
	
	// For some reason, G5's don't work with AutoWake, but do with AutoWakeOrPowerOn
	// Not sure why this is, and if this is still true, but keeping it anyway.
	//
	//NSString *eventType = [NSString stringWithCString:kIOPMAutoWake];
	NSString *eventType = [NSString stringWithUTF8String:kIOPMAutoWakeOrPowerOn];
	
	int result = 1;
	
	if([event isEqualToString:@"1"])
	{
		// An ADD operation
		NSLog(@"Adding power event: %@", [date description]);
		result = IOPMSchedulePowerEvent((CFDateRef)date, (CFStringRef)scheduler, (CFStringRef)eventType);
	}
	if([event isEqualToString:@"0"])
	{
		// A DELETE operation
		NSLog(@"Deleting power event: %@", [date description]);
		result = IOPMCancelScheduledPowerEvent((CFDateRef)date, (CFStringRef)scheduler, (CFStringRef)eventType);
	}
	
	[pool release];
	return result;
}
