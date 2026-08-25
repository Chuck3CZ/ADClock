#import "AlarmTasks.h"
#import "Prefs.h"
#import "AlarmScheduler.h"
#import "WindowManager.h"
#import "CalendarAdditions.h"

#import <mach/mach_port.h>
#import <mach/mach_interface.h>
#import <mach/mach_init.h>

#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/IOMessage.h>

#import <ServiceManagement/ServiceManagement.h>
#import "AlarmWakeHelperProtocol.h"

// Callback function to be invoked by the OS for power notifications
void callback(void * x,io_service_t y,natural_t messageType,void * messageArgument);

// Reference to the Root Power Domain IOService
io_connect_t root_port;

// Notification port allocated by IORegisterForSystemPower
IONotificationPortRef notifyPortRef;

// Notifier object, created when registering for power notifications, and used to deregister later
io_object_t notifierObject;


// Declare private methods
@interface AlarmTasks (PrivateAPI)
+ (SMAppService *)wakeHelperService;
+ (BOOL)scheduleWakeEventAdd:(BOOL)add atDate:(NSDate *)date;
+ (void)runHelperToolWithArg:(int)arg;
+ (void)startTimers;
+ (void)initialCheckForAlarm:(NSTimer *)aTimer;
+ (void)checkForAlarm:(NSTimer *)aTimer;
+ (void)updateMenuItemsAtDayChange:(NSTimer *)aTimer;
@end


@implementation AlarmTasks

// CLASS VARIABLES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Timer used to check for alarms every minute
static NSTimer *timer;

// Timer used to update the menu items when the day changes
static NSTimer *dayTimer;

// The time to schedule the computer to wake from sleep
static NSDate *wakeDate;

// INTIALIZATION, DEINITIALIZATION
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Initializes everything needed for the AlarmTasks class.
 This includes registering for system power notifications, as well as starting a timer to check for alarms.
 
 Note that this method is automatically called (courtesy of Cocoa) before the first method of this class is called.
 However, it is directly called by the MenuController during the startup of the application.
 This is because this class is in charge of checking for alarms to go off, and must be started immediately.
 Since it's called directly, we use a static variable to prevent multiple calls to this method.
 (One directly at startup, and the other indirectly via Cocoa the first time a method within it is called)
**/
+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		NSLog(@"Initializing AlarmTasks...");
		
		NSLog(@"Registering for system power notifications...");
		
		// Register for system power notifications
		root_port = IORegisterForSystemPower(0, &notifyPortRef, callback, &notifierObject);
		if(root_port == (int)NULL)
		{
			NSLog(@"IORegisterForSystemPower failed!");
		}
		
		CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopDefaultMode);
		
		// Start the timer
		[self startTimers];
		
		// Update initialization status
		initialized = YES;
	}
}

/**
 Called (via our application delegate) when the application is terminating.
 All cleanup tasks should go here.
**/
+ (void)deinitialize
{
	// Stop and release the timers
	[timer release];
	[timer invalidate];
	[dayTimer release];
	[dayTimer invalidate];
	
	// Release next alarm date
	[wakeDate release];
	
	NSLog(@"Unregistering for system power notifications...");
	
	// Deregister for system power notifications
	
	// Remove the sleep notification port from the application runloop
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopCommonModes);
	
    // Deregister for system sleep notifications
    IODeregisterForSystemPower(&notifierObject);
	
    // IORegisterForSystemPower implicitly opens the Root Power Domain IOService, so we close it here
    IOServiceClose(root_port);
	
    // destroy the notification port allocated by IORegisterForSystemPower
    IONotificationPortDestroy(notifyPortRef);
}

// POWER MANAGEMENT CALLBACK
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called by the System whenever a power event occurs.
 Code courtesy Apple. (Wayne Flansburg)
**/
void callback(void * x, io_service_t y, natural_t messageType, void * messageArgument)
{
    switch(messageType)
	{
		case kIOMessageSystemWillSleep:
			// Handle demand sleep, such as:
			// A. Running out of batteries
			// B. Closing the lid of a laptop
			// C. Selecting sleep from the Apple menu
			NSLog(@"kIOMessageSystemWillSleep");
			[AlarmTasks prepareForSleep];
			IOAllowPowerChange(root_port, (long)messageArgument);
			break;
		case kIOMessageCanSystemSleep:
			// In this case, the computer has been idle for several minutes
			// and will sleep soon so you must either allow or cancel
			// this notification. Important: if you don’t respond, there will
			// be a 30-second timeout before the computer sleeps.
			if([WindowManager canSystemSleep])
			{
				NSLog(@"kIOMessageCanSystemSleep -> Allow");
				IOAllowPowerChange(root_port, (long)messageArgument);
			}
			else
			{
				NSLog(@"kIOMessageCanSystemSleep -> Cancel");
				IOCancelPowerChange(root_port, (long)messageArgument);
			}
			break;
		case kIOMessageSystemHasPoweredOn:
			NSLog(@"kIOMessageSystemHasPoweredOn");
			[AlarmTasks wakeFromSleep];
			break;
	}
}

// AUTHENTICATION METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns the SMAppService representing the wakehelper LaunchDaemon (see WakeHelperMain.m and
 com.3czplay.alarmclock3.wakehelper.plist). The daemon runs as root - required to call
 IOPMSchedulePowerEvent/IOPMCancelScheduledPowerEvent - which this (sandboxed) app can no
 longer become itself.
**/
+ (SMAppService *)wakeHelperService
{
	return [SMAppService daemonServiceWithPlistName:@"com.3czplay.alarmclock3.wakehelper.plist"];
}

/**
 Checks to see if the wakehelper daemon is installed and enabled.
**/
+ (BOOL)isAuthenticated
{
	return [[self wakeHelperService] status] == SMAppServiceStatusEnabled;
}

/**
 Registers the wakehelper daemon with launchd via SMAppService. macOS handles prompting the
 user for approval itself (System Settings > Login Items & Extensions) - no admin password
 dialog needed, unlike the old setuid-helper approach this replaces.
**/
+ (BOOL)authenticate
{
	if([self isAuthenticated]) return YES;

	NSError *error = nil;
	if(![[self wakeHelperService] registerAndReturnError:&error])
	{
		NSLog(@"Failed to register wakehelper: %@", error);

		NSString *title = NSLocalizedString(@"Couldn't Enable Wake From Sleep", @"Dialog Title");
		NSString *message = NSLocalizedString(@"macOS didn't allow the wake-from-sleep helper to be installed. Check System Settings > General > Login Items & Extensions.", @"Dialog Message");
		NSString *okButton = NSLocalizedString(@"OK", @"Dialog Button");
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert setMessageText:title];
		[alert setInformativeText:message];
		[alert addButtonWithTitle:okButton];
		[alert runModal];
		[alert release];

		return NO;
	}

	return YES;
}

/**
 Unregisters the wakehelper daemon.
**/
+ (BOOL)deauthenticate
{
	NSError *error = nil;
	if(![[self wakeHelperService] unregisterAndReturnError:&error])
	{
		NSLog(@"Failed to unregister wakehelper: %@", error);
		return NO;
	}

	return YES;
}

// HANDLING SLEEP METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Prepares the program to go to sleep.
 That is, if it needs to wake the computer from sleep at some time then the event is scheduled in the IOPMQueue
**/
+ (void)prepareForSleep
{
	// We need to figure out when we have to wake up
	// Thus, we need to figure out when the next alarm is
	
	// Release the previous wakeDate
	[wakeDate release];
	
	// We get the time of the next scheduled alarm
	wakeDate = [AlarmScheduler nextAlarmDate];
	
	// What if an open alarm is currently snoozing, or a timer is active, etc...
	// So we also get the earliest date an open window may need to wake up
	NSDate *nextWindowDate = [WindowManager systemWillSleep];
	
	if(nextWindowDate != nil)
	{
		if(wakeDate == nil)
			wakeDate = nextWindowDate;
		else
			wakeDate = (NSDate*)[wakeDate earlierDate:nextWindowDate];
	}
	
	// Don't forget to retain the wakeDate - we need to reference it after we wake from sleep
	[wakeDate retain];
	
	// Now that we know the wakeDate, we can configure the system to wakeup at that time
	[self runHelperToolWithArg:1];
	
	// Stop the timers
	[timer invalidate];
	[dayTimer invalidate];
}

/**
 Removes the scheduled event from the IOPMQueue.
 Additionally NSTimers do not seem to be on schedule after the computer wakes from sleep.
 Thus, this method is used to stop the timer, check for an alarm manually,
 and then start the timer again (thus resyncing it)
**/
+ (void)wakeFromSleep
{
	// Remove the 'wakeFromSleep' event from the IOPMQueue
	[self runHelperToolWithArg:0];
	
	if([Prefs wakeFromSleep])
	{
		// Check for an alarm
		[self checkForAlarm:nil];
	}
	else
	{
		// Update all the alarms, so we don't have 50 go off at once
		// Which is entirely possible since we're not configured to wake the system from sleep
		// Because the computer may have slept through a dozen alarms
		[AlarmScheduler updateAllAlarms];
	}
	
	// Inform all open windows that we've woken from sleep
	[WindowManager systemDidWake];
	
	// Start the timer again
	[self startTimers];
	
	// Post notification for changed alarm
	// This will prompt the MenuController to update it's menu
	[[NSNotificationCenter defaultCenter] postNotificationName:@"AlarmChanged" object:self];
}


/**
 Opens an XPC connection to the wakehelper daemon and asks it to add or cancel the scheduled
 wake event, waiting synchronously (with a timeout) for the reply - callers of
 runHelperToolWithArg: need the completed result before returning, same as the old NSTask-based
 implementation this replaces.
**/
+ (BOOL)scheduleWakeEventAdd:(BOOL)add atDate:(NSDate *)date
{
	__block BOOL success = NO;
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);

	NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:kAlarmWakeHelperMachServiceName options:NSXPCConnectionPrivileged];
	[connection setRemoteObjectInterface:[NSXPCInterface interfaceWithProtocol:@protocol(AlarmWakeHelperProtocol)]];
	[connection resume];

	id<AlarmWakeHelperProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
		NSLog(@"WakeHelper XPC error: %@", error);
		dispatch_semaphore_signal(sema);
	}];

	void (^replyBlock)(BOOL) = ^(BOOL result) {
		success = result;
		dispatch_semaphore_signal(sema);
	};

	if(add)
		[proxy scheduleWakeAtDate:date reply:replyBlock];
	else
		[proxy cancelWakeAtDate:date reply:replyBlock];

	// Wait for the XPC reply (or error handler) - called from the system sleep/wake callback,
	// which needs a prompt answer before it can allow the sleep transition to proceed.
	dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
	dispatch_release(sema);

	[connection invalidate];
	[connection release];

	return success;
}

/**
 Asks the wakehelper daemon to add or remove the scheduled wake-from-sleep power event.
 If arg is 1 - a wake event will be scheduled
 If arg is 0 - the scheduled wake event will be canceled
**/
+ (void)runHelperToolWithArg:(int)arg
{
	// wakeDate is nil if no alarm is scheduled
	if(wakeDate == nil)
	{
		NSLog(@"Nothing to wake up for...");
		return;
	}

	if(![Prefs wakeFromSleep])
	{
		NSLog(@"Not configured to wake computer from sleep...");
		return;
	}

	if(arg == 1)
	{
		// We are scheduling a wake event: figure out the time to use
		double secondsTilAlarm = [wakeDate timeIntervalSinceNow];
		if(secondsTilAlarm <= 60)
		{
			// We barely have any time til the alarm goes off
			// We don't want to set the alarm at its normal time, as it may not wake the computer in time
			// Some computers can take up to 30 seconds to go to sleep...
			// And after they go to sleep, they may ignore wake requests within only a few seconds

			// To be safe, we want to make sure the wake time is at least 60 seconds from now
			// We also try to get this as close as possible to the alarm time
			double secondsTilWake = 60.0 - secondsTilAlarm;

			[wakeDate autorelease];
			wakeDate = [[wakeDate dateByAddingTimeInterval:secondsTilWake] retain];
		}

		[self scheduleWakeEventAdd:YES atDate:wakeDate];
	}
	else
	{
		// We are canceling the wake event: use the wakeDate that was previously set
		[self scheduleWakeEventAdd:NO atDate:wakeDate];
	}
}

// TIMER METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/* Starts the timer
** An initial timer is started that will go off at the turn of the current minute
** After that, a timer will go off every 60 seconds (effectivly at the turn of every minute thereafter)
**/
+ (void)startTimers
{
	// Start the initial timer
	// It shouldn't go off til the seconds (and milliseconds) are zero
	double waitTime1 = 60.0 - [[NSDate date] intervalOfMinute];
	timer = [[NSTimer scheduledTimerWithTimeInterval:waitTime1
											  target:self
											selector:@selector(initialCheckForAlarm:)
											userInfo:nil
											 repeats:NO] retain];
	
	// Start a timer to update menu items when the current day changes
	// This is needed so that items with "Tomorrow" get properly updated to "Today"
	double waitTime2 = 86400.0 - [[NSDate date] intervalOfDay];
	dayTimer = [[NSTimer scheduledTimerWithTimeInterval:waitTime2
												 target:self
											   selector:@selector(updateMenuItemsAtDayChange:)
											   userInfo:nil
												repeats:NO] retain];
}


/**
 Called from the initial timer.  This timer does not repeat.
 It's interval was set based on the current time, so that it went off at zero seconds and zero milliseconds.
**/
+ (void)initialCheckForAlarm:(NSTimer *)aTimer
{
	// Start the regular timer
	[timer autorelease];
	timer = [[NSTimer scheduledTimerWithTimeInterval:60.0
											  target:self
											selector:@selector(checkForAlarm:)
											userInfo:nil
											 repeats:YES] retain];
	// Check for alarms
	[self checkForAlarm:nil];
}


/**
 Called from the regular timer every 60 seconds.
 It's job is to check for an alarm, and sound it if necessary.
**/
+ (void)checkForAlarm:(NSTimer *)aTimer
{
	// Immediately grab the time so we know exactly when this timer fired
	NSDate *now = [NSDate date];
	
	// Timer Accuracy Check
	if([timer isValid] && ([[NSCalendar currentCalendar] component:NSCalendarUnitSecond fromDate:now] > 0))
	{
		// The timer is either firing early (second is probably 59) or it's firing late (second is probably 1)
		// The first is possible due to an OS bug (or timer API bug)
		// The second is possible due to heavy cpu usage
		// Realign the timer
		[timer invalidate];
		[timer autorelease];
		
		double waitTime = 60.0 - [now intervalOfMinute];
		timer = [[NSTimer scheduledTimerWithTimeInterval:waitTime
												  target:self
												selector:@selector(initialCheckForAlarm:)
												userInfo:nil
												 repeats:NO] retain];
	}
	
	// Check to see if an alarm should sound
	// Continously check in case more than one alarm is scheduled at the same time
	int alarmStatus;
	do
	{
		alarmStatus = [AlarmScheduler alarmStatus:now];
		
		if(alarmStatus > 0)
		{
			NSLog(@"AlarmTasks: Alarm should sound!");
			[WindowManager openAlarmWindow];
		}
		
	}while(alarmStatus >= 0);
}

+ (void)updateMenuItemsAtDayChange:(NSTimer *)aTimer
{
	[dayTimer autorelease];
	
	double waitTime = 86400.0 - [[NSDate date] intervalOfDay];
	dayTimer = [[NSTimer scheduledTimerWithTimeInterval:waitTime
												 target:self
											   selector:@selector(updateMenuItemsAtDayChange:)
											   userInfo:nil
												repeats:NO] retain];
	
	NSLog(@"Updating menu items at day change");
	
	// Post notification for changed alarm
	// This will prompt the MenuController to update it's menu
	[[NSNotificationCenter defaultCenter] postNotificationName:@"AlarmChanged" object:self];
}

@end
