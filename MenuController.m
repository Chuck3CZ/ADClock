#import "MenuController.h"
#import "Alarm.h"
#import "AlarmScheduler.h"
#import "AlarmTasks.h"
#import "Prefs.h"
#import "WindowManager.h"
#import "RHDateToStringTransformer.h"

@interface MenuController (PrivateAPI)
- (void)updateMenuItems:(NSNotification *)notification;
@end


@implementation MenuController

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		// Register NSValueTransformers
		RHDateToStringTransformer *dateToStringTransformer;
		dateToStringTransformer = [[[RHDateToStringTransformer alloc] init] autorelease];
		
		// Register it with the name that we refer to it within our nib files
		[NSValueTransformer setValueTransformer:dateToStringTransformer
										forName:@"RHDateToStringTransformer"];
		
		// Update initialization status
		initialized = YES;
	}
}

// SETUP
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	if(self = [super init])
	{
		// Cocoa automatically calls the initialize methods for us, but only when we start using the classes.
		// We call them specifically, and in order, here for clarity.
		// Also, classes like AlarmTasks must be started immediately, so we do that.
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wexplicit-initialize-call"
		
		// Initialize Prefs
		// This registers the default options in the user defaults system
		[Prefs initialize];
		
		// Initialize Alarms
		// This loads the alarm info saved in the users preferences
		[AlarmScheduler initialize];
		
		// Initialize Window Manager
		// This sets up the internal window management system
		[WindowManager initialize];
		
		// Initialize Alarm Tasks
		// This starts the timers that automatically check for alarms every minute on the minute
		[AlarmTasks initialize];
        
#pragma clang diagnostic pop

	}
	return self;
}

- (NSImage *)statusBarImageNamed:(NSString *)symbolName accessibilityDescription:(NSString *)description
{
	NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:description];
	[image setTemplate:YES];
	return image;
}

- (void)awakeFromNib
{
	// Setup NSStatusItem
	statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength: NSSquareStatusItemLength] retain];

	statusItem.button.image = [self statusBarImageNamed:@"alarm" accessibilityDescription:@"Alarm Clock"];
	statusItem.menu = menu;
	
	// Setup menu items
	[self updateMenuItems:nil];
	
	// Register for notifications
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateMenuItems:)
												 name:@"AlarmChanged"
											   object:nil];
	
	NSLog(@"Ready");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	if([Prefs isFirstRun])
	{
		// Bring application to the front
		[NSApp activateIgnoringOtherApps:YES];
		
		// Display the welcome panel
		NSString *title = NSLocalizedString(@"Welcome to Alarm Clock", @"Dialog Title");
		NSString *message = NSLocalizedString(@"This application runs in the system menu bar, in the upper right-hand corner.  You may control your alarms, change preferences, and quit the application from this icon.  Enjoy!\n\nPS - To wake the computer from sleep, you must first authenticate in the app's preferences.", @"Dialog Message");
		NSString *okButton = NSLocalizedString(@"OK", @"Dialog Button");
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:title];
		[alert setInformativeText:message];
		[alert addButtonWithTitle:okButton];
		[alert runModal];
		[alert release];
		
		// And set isFirstRun to false
		[Prefs setIsFirstRun:NO];
	}
}

// UPDATING MENU
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateMenuItems:(NSNotification *)notification
{
	int i;
	int total = 0;
	
	// Get items in menu
	NSArray *items = [menu itemArray];
	
	// Find out how many items to remove
	for(i=0; i<[items count]; i++)
	{
		NSMenuItem *item = [items objectAtIndex:i];
		
		if([item action] == @selector(editAlarm:))
		{
			if(total == 0)
				total += 2;
			else
				total += 1;
		}
	}
	
	// Remove the items
	for(i=0; i<total; i++)
	{
		[menu removeItemAtIndex:0];
	}
	
	// Get the number of alarms
	total = (int) [AlarmScheduler numberOfAlarms];
	
	// Add the seperator if necessary
	if(total > 0)
	{
		[menu insertItem:[NSMenuItem separatorItem] atIndex:0];
	}
	
	// Add the alarms
	for(i = total-1; i >= 0; i--)
	{
		Alarm *temp = [AlarmScheduler alarmReferenceForIndex:i];
		
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[temp description]
													  action:@selector(editAlarm:)
											   keyEquivalent:@""];
        
        [item setTarget:self];
		[item setState:([temp isEnabled] ? NSControlStateValueOn : NSControlStateValueOff)];
		[item setRepresentedObject:[NSNumber numberWithInt:i]];
        [menu insertItem:[item autorelease] atIndex:0];
	}
	
	// Set the proper image
	// Note: the status bar icon is now a template SF Symbol, which automatically adapts
	// to light/dark mode and menu bar tinting, so the "colored icons" preference no longer
	// applies to it.
	if([AlarmScheduler nextAlarmDate])
	{
		if([Prefs wakeFromSleep])
		{
			statusItem.button.image = [self statusBarImageNamed:@"alarm.fill" accessibilityDescription:@"Alarm scheduled"];
		}
		else
		{
			statusItem.button.image = [self statusBarImageNamed:@"alarm.waves.left.and.right.fill" accessibilityDescription:@"Alarm scheduled, computer will not wake from sleep"];
		}
	}
	else
	{
		statusItem.button.image = [self statusBarImageNamed:@"alarm" accessibilityDescription:@"No alarm scheduled"];
	}
}

// EDITING AND ADDING ALARMS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)editAlarm:(id)sender
{
	// Get index of alarm
	int index = [[sender representedObject] intValue];
	
	// Tell the window manager to open an alarm editor for the desired alarm
	[WindowManager openAlarmEditorWithAlarmIndex:index];
	
	// Bring application to the front
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)addAlarm:(id)sender
{
	// Tell the window manager to open an alarm editor for a new alarm
	[WindowManager openAlarmEditorForNewAlarm];
	
	// Bring application to the front
	[NSApp activateIgnoringOtherApps:YES];
}

// TIMER AND STOPWATCH
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)openNewTimer:(id)sender
{
	// Tell the window manager to open a new timer window
	[WindowManager openTimerWindow];
	
	// Bring application to the front
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)openNewStopwatch:(id)sender
{
	// Tell the window manager to open a new stopwatch window
	[WindowManager openStopwatchWindow];
	
	// Bring application to the front
	[NSApp activateIgnoringOtherApps:YES];
}

// ABOUT, PREFERENCES, AND QUIT
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)about:(id)sender
{
	[NSApp orderFrontStandardAboutPanel:sender];
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)preferences:(id)sender
{
	[prefsWindow makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)quit:(id)sender
{
	[NSApp terminate:0];
}

/**
 This method is called to determine if the application should be allowed to terminate.
 There is only one thing that would prevent us from terminating the app:
 Open Alarm Editors with unsaved changes.
**/
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	// TODO
	return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	NSLog(@"Shutting down Alarm Clock...");
	
	// Note: Order of deinitialization is important. (Especially if multi-threading)
	
	// Shut down AlarmTasks first
	// This will stop all of the timers from firing, and causing other code to run
	[AlarmTasks deinitialize];
	
	// Now that the timers won't fire, we won't need to open up any new windows
	// And we can close all open windows (AlarmEditors, AlarmWindows, TimerWindows, etc)
	[WindowManager deinitialize];
	
	// And now we can release all our alarms
	[AlarmScheduler deinitialize];
	
	// Take care of any user default issues last
	[Prefs deinitialize];
	
	NSLog(@"Thank you. Come again.");
}

@end
