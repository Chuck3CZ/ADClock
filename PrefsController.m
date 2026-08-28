#import "PrefsController.h"
#import "Prefs.h"
#import "ADClockTasks.h"
#import <ServiceManagement/ServiceManagement.h>

#ifdef ENABLE_UPDATES
#import <Sparkle/Sparkle.h>
#endif

@interface PrefsController (PrivateAPI)
- (BOOL)isLoginItem;
- (void)addLoginItem;
- (void)deleteLoginItem;
@end

/**
 A thin NSTabViewController subclass whose only job is to keep the (now real, visible)
 window title in sync with the selected pane. NSTabViewController installs itself as the
 delegate of its managed NSTabView, so this is the correct place to hook tab selection
 without disturbing its built-in toolbar handling and animated window resizing.
**/
@interface PrefsTabViewController : NSTabViewController
@end

@implementation PrefsTabViewController

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	[super tabView:tabView didSelectTabViewItem:tabViewItem];
	[[[self view] window] setTitle:[tabViewItem label]];
}

@end

@implementation PrefsController

/**
 Horizontal grouping helper for the Auto Layout rebuild below: wraps the given views (already-
 existing, outlet-connected controls) in a new NSStackView row instead of positioning them via
 explicit frames, so their spacing is computed by Auto Layout instead of guessed pixel values.
**/
- (NSStackView *)rowWithViews:(NSArray<NSView *> *)views spacing:(CGFloat)spacing
{
	NSStackView *row = [NSStackView stackViewWithViews:views];
	[row setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[row setAlignment:NSLayoutAttributeCenterY];
	[row setSpacing:spacing];
	return row;
}

/**
 Every pane has static caption text fields (e.g. "Alarm volume:", "Keyboard behavior") with no
 outlets, since their text never changes at runtime - so they can't be referenced directly.
 This finds the closest still-unclaimed one to a given control (vertically adjacent, roughly
 aligned horizontally with it) and removes it from the pool, so the same caption can't be
 claimed twice. Ties (e.g. two captions on the same line) resolve to the leftmost one, so
 repeated calls for the same control pick them up in reading order.
**/
- (NSTextField *)claimCaptionNear:(NSView *)control fromUnclaimed:(NSMutableArray *)unclaimed
{
	NSRect controlFrame = [control frame];
	NSTextField *best = nil;
	CGFloat bestDistance = CGFLOAT_MAX;
	for(NSTextField *candidate in unclaimed)
	{
		NSRect f = [candidate frame];
		BOOL horizontallyNear = (NSMinX(f) < NSMaxX(controlFrame) + 20) && (NSMaxX(f) > NSMinX(controlFrame) - 20);
		if(!horizontallyNear)
			continue;

		CGFloat distance = MIN(fabs(NSMinY(f) - NSMaxY(controlFrame)), fabs(NSMaxY(f) - NSMinY(controlFrame)));
		if(distance < bestDistance - 0.01)
		{
			bestDistance = distance;
			best = candidate;
		}
		else if(fabs(distance - bestDistance) < 0.01 && best != nil && NSMinX(f) < NSMinX([best frame]))
		{
			best = candidate;
		}
	}
	if(best)
		[unclaimed removeObject:best];
	return best;
}

/**
 Rebuilds the "General" pane (coloredIconsButton + 3 slider groups) as a vertical NSStackView,
 pulling the already-working, outlet-connected controls out of their old fixed-frame positions.
**/
- (NSView *)buildGeneralPane
{
	NSMutableArray *unclaimed = [NSMutableArray array];
	for(NSView *sub in [(NSView *)generalView subviews])
	{
		if([sub isKindOfClass:[NSTextField class]] &&
		   sub != (NSView *)prefVolumeLabel && sub != (NSView *)snoozeDurationLabel && sub != (NSView *)killDurationLabel)
		{
			[unclaimed addObject:(NSTextField *)sub];
		}
	}

	NSTextField *prefVolumeCaption = [self claimCaptionNear:(NSView *)prefVolumeSlider fromUnclaimed:unclaimed];
	NSTextField *snoozeCaption = [self claimCaptionNear:(NSView *)snoozeDurationSlider fromUnclaimed:unclaimed];
	NSTextField *killCaption = [self claimCaptionNear:(NSView *)killDurationSlider fromUnclaimed:unclaimed];

	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:(NSView *)coloredIconsButton];
	if(prefVolumeCaption) [rows addObject:prefVolumeCaption];
	[rows addObject:[self rowWithViews:@[(NSView *)prefVolumeSlider, (NSView *)prefVolumeLabel] spacing:8.0]];
	if(snoozeCaption) [rows addObject:snoozeCaption];
	[rows addObject:[self rowWithViews:@[(NSView *)snoozeDurationSlider, (NSView *)snoozeDurationLabel] spacing:8.0]];
	if(killCaption) [rows addObject:killCaption];
	[rows addObject:[self rowWithViews:@[(NSView *)killDurationSlider, (NSView *)killDurationLabel] spacing:8.0]];
	// Any text field not claimed by a slider group is the small explanatory footer text.
	[rows addObjectsFromArray:unclaimed];

	NSStackView *stack = [NSStackView stackViewWithViews:rows];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:10.0];
	[stack setEdgeInsets:NSEdgeInsetsMake(20, 20, 20, 20)];
	return stack;
}

/**
 Rebuilds the "Easy Wake" pane as a vertical NSStackView, same approach as buildGeneralPane.
**/
- (NSView *)buildEasyWakePane
{
	NSMutableArray *unclaimed = [NSMutableArray array];
	for(NSView *sub in [(NSView *)easyWakeView subviews])
	{
		if([sub isKindOfClass:[NSTextField class]] &&
		   sub != (NSView *)minVolumeLabel && sub != (NSView *)maxVolumeLabel && sub != (NSView *)easyWakeDurationLabel)
		{
			[unclaimed addObject:(NSTextField *)sub];
		}
	}

	NSTextField *minCaption = [self claimCaptionNear:(NSView *)minVolumeSlider fromUnclaimed:unclaimed];
	NSTextField *maxCaption = [self claimCaptionNear:(NSView *)maxVolumeSlider fromUnclaimed:unclaimed];
	// The scaling-duration slider has two captions sharing the same line: its label and a
	// small parenthetical note - claim them in that order (claimCaptionNear breaks ties by
	// leftmost position), then group both into one row.
	NSTextField *durationCaption = [self claimCaptionNear:(NSView *)easyWakeDurationSlider fromUnclaimed:unclaimed];
	NSTextField *durationNote = [self claimCaptionNear:(NSView *)easyWakeDurationSlider fromUnclaimed:unclaimed];

	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:(NSView *)easyWakeDefaultButton];
	if(minCaption) [rows addObject:minCaption];
	[rows addObject:[self rowWithViews:@[(NSView *)minVolumeSlider, (NSView *)minVolumeLabel] spacing:8.0]];
	if(maxCaption) [rows addObject:maxCaption];
	[rows addObject:[self rowWithViews:@[(NSView *)maxVolumeSlider, (NSView *)maxVolumeLabel] spacing:8.0]];
	if(durationCaption && durationNote)
		[rows addObject:[self rowWithViews:@[durationCaption, durationNote] spacing:6.0]];
	else if(durationCaption)
		[rows addObject:durationCaption];
	[rows addObject:[self rowWithViews:@[(NSView *)easyWakeDurationSlider, (NSView *)easyWakeDurationLabel] spacing:8.0]];
	[rows addObjectsFromArray:unclaimed];

	NSStackView *stack = [NSStackView stackViewWithViews:rows];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:10.0];
	[stack setEdgeInsets:NSEdgeInsetsMake(20, 20, 20, 20)];
	return stack;
}

/**
 Rebuilds the "Advanced" pane as a vertical NSStackView, same approach as buildGeneralPane.
**/
- (NSView *)buildAdvancedPane
{
	NSMutableArray *unclaimed = [NSMutableArray array];
	for(NSView *sub in [(NSView *)advancedView subviews])
	{
		if([sub isKindOfClass:[NSTextField class]])
			[unclaimed addObject:(NSTextField *)sub];
	}

	NSTextField *wakeCaption = [self claimCaptionNear:(NSView *)wakeFromSleepButton fromUnclaimed:unclaimed];
	NSTextField *keyboardCaption = [self claimCaptionNear:(NSView *)keyboardType fromUnclaimed:unclaimed];

	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:(NSView *)wakeFromSleepButton];
	if(wakeCaption) [rows addObject:wakeCaption];
	[rows addObject:(NSView *)deauthenticateButton];
	if(keyboardCaption) [rows addObject:keyboardCaption];
	[rows addObject:(NSView *)keyboardType];
	// Any text field not claimed above is a trailing footnote (e.g. below the keyboard matrix).
	[rows addObjectsFromArray:unclaimed];
	[rows addObject:(NSView *)loginButton];

	// Testing aid, not a real user-facing setting: lets Liquid Glass be turned off on a
	// macOS 26+ Mac so the pre-26 fallback look (see RoundedWindow/TransparentWindow) can be
	// checked without needing an actual older Mac. No outlet since it's built entirely here,
	// not wired in the nib.
	NSButton *disableLiquidGlassButton = [NSButton checkboxWithTitle:NSLocalizedString(@"Disable Liquid Glass (for testing)", @"Preference Pane Option")
																target:self
																action:@selector(toggleDisableLiquidGlass:)];
	[disableLiquidGlassButton setState:([Prefs disableLiquidGlass] ? NSControlStateValueOn : NSControlStateValueOff)];
	[rows addObject:disableLiquidGlassButton];

	NSStackView *stack = [NSStackView stackViewWithViews:rows];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:10.0];
	[stack setEdgeInsets:NSEdgeInsetsMake(20, 20, 20, 20)];
	return stack;
}

/**
 Wraps a pane view (either an old nib-loaded fixed-frame view, or one of the new NSStackView-
 based panes built above) in a plain NSViewController + NSTabViewItem, so it can be handed to
 the NSTabViewController below.
**/
- (NSTabViewItem *)tabViewItemForView:(NSView *)paneView label:(NSString *)label symbolName:(NSString *)symbolName
{
	// The pane's controls use fixed nib-designed frames (no Auto Layout), but
	// NSTabViewController pins whatever view we give it to fill the full tab content
	// area edge-to-edge - so the pane itself was being stretched wider/taller than it
	// was designed for, throwing off every control's position (reads as "not left
	// aligned", "centered", "big gap", depending on the pane). Setting
	// preferredContentSize alone only hints at a window size; it doesn't stop that
	// stretch. So instead we pin the pane to a fixed-size container at its native size,
	// with autoresizing disabled, and let the container (not the pane) absorb any
	// extra space the tab view controller insists on.
	//
	// fittingSize (rather than the old frame.size) is what makes this work for the new
	// NSStackView-based panes too, since a freshly built stack view has no frame of its own
	// until Auto Layout computes one.
	NSSize nativeSize = [paneView fittingSize];
	[paneView setFrame:NSMakeRect(0, 0, nativeSize.width, nativeSize.height)];
	[paneView setAutoresizingMask:NSViewNotSizable];

	NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, nativeSize.width, nativeSize.height)] autorelease];
	[container addSubview:paneView];

	// Belt and suspenders: NSTabViewController arranges tab content with Auto Layout,
	// not the legacy autoresizing mask, so pin the container's size with real
	// constraints too - otherwise it still gets stretched to fill the tab area.
	[container setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[container.widthAnchor constraintEqualToConstant:nativeSize.width] setActive:YES];
	[[container.heightAnchor constraintEqualToConstant:nativeSize.height] setActive:YES];

	NSViewController *paneController = [[[NSViewController alloc] init] autorelease];
	[paneController setView:container];
	[paneController setPreferredContentSize:nativeSize];

	NSTabViewItem *tabViewItem = [NSTabViewItem tabViewItemWithViewController:paneController];
	[tabViewItem setLabel:label];
	// SF Symbols carry Apple's own icon/text safe-area spacing automatically, unlike the
	// old flat PNGs (General.png etc.) which were flush to their canvas edge and read as
	// cramped against the toolbar label.
	[tabViewItem setImage:[NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:label]];
	return tabViewItem;
}

- (void)awakeFromNib
{
	// Build a modern, System Settings-style toolbar of panes.
	// NSTabViewController with the "toolbar" style automatically creates and manages the
	// window's real NSToolbar (one item per pane), including selection state and the
	// animated window resize when switching panes - replacing our old hand-rolled
	// NSToolbar delegate + switchViews: frame animation.
	tabViewController = [[PrefsTabViewController alloc] init];
	[tabViewController setTabStyle:NSTabViewControllerTabStyleToolbar];

	NSView *generalPane  = [self buildGeneralPane];
	NSView *easyWakePane = [self buildEasyWakePane];
	NSView *advancedPane = [self buildAdvancedPane];

	NSTabViewItem *generalItem  = [self tabViewItemForView:generalPane  label:NSLocalizedString(@"General", @"Preference Pane Option")     symbolName:@"gearshape"];
	NSTabViewItem *easyWakeItem = [self tabViewItemForView:easyWakePane label:NSLocalizedString(@"Easy Wake", @"Preference Pane Option")    symbolName:@"sunrise"];
	NSTabViewItem *advancedItem = [self tabViewItemForView:advancedPane label:NSLocalizedString(@"Advanced", @"Preference Pane Option")     symbolName:@"slider.horizontal.3"];

	[tabViewController addTabViewItem:generalItem];
	[tabViewController addTabViewItem:easyWakeItem];
	[tabViewController addTabViewItem:advancedItem];
#ifdef ENABLE_UPDATES
	NSTabViewItem *softwareUpdateItem = [self tabViewItemForView:softwareUpdateView label:NSLocalizedString(@"Software Update", @"Preference Pane Option") symbolName:@"arrow.triangle.2.circlepath"];
	[tabViewController addTabViewItem:softwareUpdateItem];
#endif

	[window setContentViewController:tabViewController];

	// Now setup all the controls
	
	// Alarms
	[coloredIconsButton setState:([Prefs useColoredIcons] ? NSControlStateValueOn : NSControlStateValueOff)];
	
	[prefVolumeSlider setIntValue:([Prefs prefVolume] * 100)];
	[self setPrefVolume:prefVolumeSlider];
	
	[snoozeDurationSlider setIntValue:(int)[Prefs snoozeDuration]];
	[self setSnoozeDuration:snoozeDurationSlider];
	
	[killDurationSlider setIntValue:(int)[Prefs killDuration]];
	[self setKillDuration:killDurationSlider];
	
	// Easy wake
	[easyWakeDefaultButton setState:([Prefs useEasyWakeByDefault] ? NSControlStateValueOn : NSControlStateValueOff)];
	
	[minVolumeSlider setIntValue:([Prefs minVolume] * 100)];
	[self setMinVolume:minVolumeSlider];
	
	[maxVolumeSlider setIntValue:([Prefs maxVolume] * 100)];
	[self setMaxVolume:maxVolumeSlider];
	
	[easyWakeDurationSlider setIntValue:(int)[Prefs easyWakeDuration]];
	[self setEasyWakeDuration:easyWakeDurationSlider];
	
	// Advanced
	[wakeFromSleepButton setState:([Prefs wakeFromSleep] ? NSControlStateValueOn: NSControlStateValueOff)];
	[deauthenticateButton setEnabled:[Prefs wakeFromSleep]];
	
	[keyboardType selectCellAtRow:([Prefs anyKeyStops] ? 0 : 1) column:0];
	
	// Apple Remote hardware no longer exists on modern Macs; keep the control hidden.
	[appleRemoteButton setHidden:YES];

	[loginButton setState:([Prefs launchAtLogin] ? NSControlStateValueOn: NSControlStateValueOff)];

	// Apple's guidance for preference panes is left-aligned labels, not centered - these
	// checkboxes/radio cells are wide (spanning the pane), so a centered cell alignment
	// leaves the checkbox glyph and its title floating in the middle instead of hugging
	// the left edge like the rest of the system's Settings panes.
	[[wakeFromSleepButton cell] setAlignment:NSTextAlignmentLeft];
	[[deauthenticateButton cell] setAlignment:NSTextAlignmentLeft];
	[[loginButton cell] setAlignment:NSTextAlignmentLeft];
	for (NSCell *cell in [keyboardType cells])
	{
		[cell setAlignment:NSTextAlignmentLeft];
	}

#ifdef ENABLE_UPDATES
	// Software Update
	int updateInterval = [[NSUserDefaults standardUserDefaults] integerForKey:SUScheduledCheckIntervalKey];
	[checkForUpdatesButton setState:(updateInterval > 0) ? NSControlStateValueOn : NSControlStateValueOff];
	
	if(updateInterval == 0) {
		// Select default item "Weekly"
		[updateIntervalPopup setEnabled:NO];
		[updateIntervalPopup selectItemAtIndex:1];
	}
	else if(updateInterval == 86400) {
		[updateIntervalPopup selectItemAtIndex:0];
	}
	else if(updateInterval == 604800) {
		[updateIntervalPopup selectItemAtIndex:1];
	}
	else if(updateInterval == 2592000) {
		[updateIntervalPopup selectItemAtIndex:2];
	}
	else {
		// The updateInterval has been corrupted - reset to zero
		updateInterval = 0;
		[[NSUserDefaults standardUserDefaults] setInteger:updateInterval forKey:SUScheduledCheckIntervalKey];
		[updateIntervalPopup setEnabled:NO];
		[updateIntervalPopup selectItemAtIndex:1];
	}
#endif
	
	// Switch to the default view (preserves the app's previous default of "Advanced")
	[tabViewController setSelectedTabViewItemIndex:[[tabViewController tabViewItems] indexOfObject:advancedItem]];
	[window setTitle:[advancedItem label]];

	// Don't center the window til after we've switched the view, or else it will center that small window stub
	[window center];
	
	// Check that wake from sleep is possible if "wake from sleep" option is selected
	if([Prefs wakeFromSleep] && ![ADClockTasks isAuthenticated])
	{
		// Preferences do not match system!  Bring to users attention
		
		// Deslect the wake from sleep option
		[wakeFromSleepButton setState:NSControlStateValueOff];
		// Disable deauthenticate button and change preference
		[self toggleWakeFromSleep:wakeFromSleepButton];
		
		// Display the prefs window
		[window makeKeyAndOrderFront:nil];
		
		// Bring application to the front
		[NSApp activateIgnoringOtherApps:YES];
		
		// Display the information window
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedString(@"Reauthentication Required", @"Dialog Title")];
		[alert setInformativeText:NSLocalizedString(@"Internal components of the application have changed. Reauthentication is required to wake the computer from sleep.", @"Dialog Message")];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert addButtonWithTitle:NSLocalizedString(@"OK", @"Dialog Button")];
		[alert beginSheetModalForWindow:window completionHandler:nil];
		
		// Also, this means that the user is upgrading their app
		// So turn off isFirstRun because they don't need the welcome message
		[Prefs setIsFirstRun:NO];
	}
	
	// Check that loginButton state matches loginItem
	if([self isLoginItem])
	{
		if(![Prefs launchAtLogin])
		{
			// User manually added login item
			// Check box, but do not set preference
			[loginButton setState:NSControlStateValueOn];
		}
	}
	else
	{
		if([Prefs launchAtLogin])
		{
			// User manually removed login item
			// Preferences do not match system!  Bring to users attention
			
			// Deselect login button
			[loginButton setState:NSControlStateValueOff];
			// Change preference
			[self toggleLogin:loginButton];
			
			// Display the prefs window
			[window makeKeyAndOrderFront:nil];
			
			// Bring application to the front
			[NSApp activateIgnoringOtherApps:YES];
		}
	}
}

- (BOOL)isLoginItem
{
	if (@available(macOS 13.0, *)) {
		return [[SMAppService mainAppService] status] == SMAppServiceStatusEnabled;
	}

	NSMutableString *command = [NSMutableString string];
	[command appendString:@"tell application \"System Events\" \n"];
	[command appendString:@"if \"AD Clock\" is in (name of every login item) then \n"];
	[command appendString:@"return yes \n"];
	[command appendString:@"else \n"];
	[command appendString:@"return no \n"];
	[command appendString:@"end if \n"];
	[command appendString:@"end tell"];

	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:command];
	NSAppleEventDescriptor *ae = [script executeAndReturnError:nil];
	[script autorelease];
	return [[ae stringValue] hasPrefix:@"yes"];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Options:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)toggleColoredIcons:(id)sender
{
	[Prefs setUseColoredIcons:[sender state]];
	
	// Post notification for changed alarm
	// This is to allow the menu to properly change it's icon
	[[NSNotificationCenter defaultCenter] postNotificationName:@"AlarmChanged" object:self];
}

- (IBAction)setPrefVolume:(id)sender
{
	NSString *format = NSLocalizedString(@"%i%%", @"Label in Preferences panel");
	
	[prefVolumeLabel setStringValue:[NSString stringWithFormat:format, [sender intValue]]];
	
	float value = [sender intValue] / 100.0;
	[Prefs setPrefVolume:value];
}

- (IBAction)setSnoozeDuration:(id)sender
{
	NSString *format = NSLocalizedString(@"%i minutes", @"Label in Preferences panel");
	
	[snoozeDurationLabel setStringValue:[NSString stringWithFormat:format, [sender intValue]]];
	[Prefs setSnoozeDuration:[sender intValue]];
}

- (IBAction)setKillDuration:(id)sender
{
	NSString *format = NSLocalizedString(@"%i minutes", @"Label in Preferences panel");
	
	[killDurationLabel setStringValue:[NSString stringWithFormat:format, [sender intValue]]];	
	[Prefs setKillDuration:[sender intValue]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Easy Wake Options:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)toggleEasyWakeDefault:(id)sender
{
	[Prefs setUseEasyWakeByDefault:[sender state]];
}

- (IBAction)setMinVolume:(id)sender
{
	NSString *format = NSLocalizedString(@"%i%%", @"Label in Preferences panel");
	
	[minVolumeLabel setStringValue:[NSString stringWithFormat:format, [sender intValue]]];

	float value = [sender intValue] / 100.0;
	[Prefs setMinVolume:value];
	
	if([Prefs minVolume] > [Prefs maxVolume])
	{
		[maxVolumeSlider setIntValue:[sender intValue]];
		[self setMaxVolume:maxVolumeSlider];
	}
}

- (IBAction)setMaxVolume:(id)sender
{
	NSString *format = NSLocalizedString(@"%i%%", @"Label in Preferences panel");
	
	[maxVolumeLabel setStringValue:[NSString stringWithFormat:format, [sender intValue]]];	
	
	float value = [sender intValue] / 100.0;
	[Prefs setMaxVolume:value];
	
	if([Prefs maxVolume] < [Prefs minVolume])
	{
		[minVolumeSlider setIntValue:[sender intValue]];
		[self setMinVolume:minVolumeSlider];
	}
}

- (IBAction)setEasyWakeDuration:(id)sender
{
	NSString *format = NSLocalizedString(@"%i minutes", @"Label in Preferences panel");
	
	[easyWakeDurationLabel setStringValue:[NSString stringWithFormat:format, [sender intValue]]];
	[Prefs setEasyWakeDuration:[sender intValue]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Advanced Options:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)toggleDisableLiquidGlass:(id)sender
{
	[Prefs setDisableLiquidGlass:([sender state] == NSControlStateValueOn)];
}

- (IBAction)toggleWakeFromSleep:(id)sender
{
	BOOL flag = [sender state];
	
	if(flag)
	{
		if([ADClockTasks authenticate])
		{
			[Prefs setWakeFromSleep:YES];
			[deauthenticateButton setEnabled:YES];
		}
		else
		{
			[sender setState:NO];
		}
	}
	else
	{
		[Prefs setWakeFromSleep:NO];
		[deauthenticateButton setEnabled:NO];
	}
	
	// For some reason, the authentication dialog doesn't return focus to our application
	// Bring application and window back to the front
	[NSApp activateIgnoringOtherApps:YES];
	[window makeKeyAndOrderFront:self];
	
	// Post notification for changed alarm
	// This lets the menu know to change it's icon, based on wake from sleep status
	[[NSNotificationCenter defaultCenter] postNotificationName:@"AlarmChanged" object:self];
}

- (IBAction)deauthenticate:(id)sender
{
	if([ADClockTasks deauthenticate])
	{
		[Prefs setWakeFromSleep:NO];
		[wakeFromSleepButton setState:NSControlStateValueOff];
		[deauthenticateButton setEnabled:NO];
	}
	
	// For some reason, the authentication dialog doesn't return focus to our application
	// Bring application back to the front
	[NSApp activateIgnoringOtherApps:YES];
	[window makeKeyAndOrderFront:self];
	
	// Post notification for changed alarm
	// This lets the menu know to change it's icon, based on wake from sleep status
	[[NSNotificationCenter defaultCenter] postNotificationName:@"AlarmChanged" object:self];
}

- (IBAction)toggleKeyboard:(id)sender
{
	[Prefs setAnyKeyStops:([sender selectedRow] == 0)];
}

- (IBAction)toggleLogin:(id)sender
{
	if([sender state])
	{
		[Prefs setLaunchAtLogin:YES];
		[self addLoginItem];
	}
	else
	{
		[Prefs setLaunchAtLogin:NO];
		[self deleteLoginItem];
	}
}

- (void)addLoginItem
{
	if (@available(macOS 13.0, *)) {
		NSError *error = nil;
		if (![[SMAppService mainAppService] registerAndReturnError:&error]) {
			NSLog(@"Failed to add login item: %@", error);
		}
		return;
	}

	NSMutableString *command = [NSMutableString string];
	[command appendString:@"set app_path to path to me \n"];
	[command appendString:@"tell application \"System Events\" \n"];
	[command appendString:@"if \"AD Clock\" is not in (name of every login item) then \n"];
	[command appendString:@"make login item at end with properties {hidden:false, path:app_path} \n"];
	[command appendString:@"end if \n"];
	[command appendString:@"end tell"];

	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:command];
	[script executeAndReturnError:nil];
	[script release];
}

- (void)deleteLoginItem
{
	if (@available(macOS 13.0, *)) {
		NSError *error = nil;
		if (![[SMAppService mainAppService] unregisterAndReturnError:&error]) {
			NSLog(@"Failed to remove login item: %@", error);
		}
		return;
	}

	NSMutableString *command = [NSMutableString string];
	[command appendString:@"tell application \"System Events\" \n"];
	[command appendString:@"if \"AD Clock\" is in (name of every login item) then \n"];
	[command appendString:@"delete (every login item whose name is \"AD Clock\") \n"];
	[command appendString:@"end if \n"];
	[command appendString:@"end tell"];

	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:command];
	[script executeAndReturnError:nil];
	[script release];
}

#ifdef ENABLE_UPDATES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Software Update Options:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)toggleCheckForUpdates:(id)sender
{
	if([sender state] == NSControlStateValueOff)
	{
		[[NSUserDefaults standardUserDefaults] setInteger:0 forKey:SUScheduledCheckIntervalKey];
		[updateIntervalPopup setEnabled:NO];
	}
	else
	{
		int updateInterval = [updateIntervalPopup selectedTag];
		[[NSUserDefaults standardUserDefaults] setInteger:updateInterval forKey:SUScheduledCheckIntervalKey];
		[updateIntervalPopup setEnabled:YES];
	}
}

- (IBAction)setUpdateInterval:(id)sender
{
	int updateInterval = [sender selectedTag];
	[[NSUserDefaults standardUserDefaults] setInteger:updateInterval forKey:SUScheduledCheckIntervalKey];
}
#endif

@end
