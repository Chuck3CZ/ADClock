#import "EditorController.h"
#import "ADClockScheduler.h"
#import "Alarm.h"
#import "CalendarView.h"
#import "ITunesData.h"
#import "ITunesTable.h"
#import "ITunesPlayer.h"

/**
 A purely decorative background layer. Unlike RoundedWindow/TransparentWindow (where the
 glass view is the designated contentView wrapping a single interactive view), here it's
 inserted as an extra sibling behind this window's many pre-existing controls, so it must
 never intercept clicks meant for them - hence -hitTest: always returns nil.
**/
@interface EditorGlassBackgroundView : NSVisualEffectView
@end

@implementation EditorGlassBackgroundView
- (NSView *)hitTest:(NSPoint)point
{
	return nil;
}
@end

@interface EditorController (PrivateAPI)
- (void)parseITunesMusicLibrary;
- (void)setupPlaylistMenu;
- (void)addPlaylistItemsWithFolder:(NSNumber *)parentID indentation:(int)level;
- (void)setIsEnabled:(BOOL)status;
- (void)updateTimeImage;
- (void)updateSearchLabel;
- (void)updateSongLabelAndShuffleButton;
- (void)updateWindowStatus;
@end


@implementation EditorController

/**
 repeatDayButtons is ordered left-to-right visually, not by tag, so schedule-bitmask code
 (which cares about "which day", not "which button is Nth from the left") looks buttons up
 by their preserved original tag instead of by array position.
**/
- (NSButton *)dayButtonWithTag:(NSInteger)tag
{
	for(NSButton *button in repeatDayButtons)
	{
		if([button tag] == tag)
			return button;
	}
	return nil;
}

/**
 We don't have outlets for every button in this nib (e.g. Cancel/OK), so this finds one by
 the action selector it's wired to, searching the view tree rooted at `view`.
**/
- (NSButton *)findButtonWithAction:(SEL)action inView:(NSView *)view
{
	for(NSView *subview in [view subviews])
	{
		if([subview isKindOfClass:[NSButton class]] && [(NSButton *)subview action] == action)
			return (NSButton *)subview;

		NSButton *found = [self findButtonWithAction:action inView:subview];
		if(found)
			return found;
	}
	return nil;
}

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

- (id)init;
{
	return [self initWithIndex:-1];
}

- (id)initWithIndex:(int)index
{
	if(self = [super initWithWindowNibName:@"AlarmEditor"])
	{
		// Initialize alarm reference and copy
		if(index < 0)
		{
			alarmReference = nil;
			alarm = [[Alarm alloc] init];
		}
		else
		{
			alarmReference = [[ADClockScheduler alarmReferenceForIndex:index] retain];
			alarm = [[ADClockScheduler alarmCloneForIndex:index] retain];
		}
		
		// Intialize images
		NSBundle *bundle = [NSBundle bundleForClass:[self class]];
		NSString *path = [bundle resourcePath];
		playImage = [[NSImage alloc] initByReferencingFile:[path stringByAppendingString:@"/play.tif"]];
		stopImage = [[NSImage alloc] initByReferencingFile:[path stringByAppendingString:@"/stop.tif"]];
		
		// Initialize lock
		lock = [[NSLock alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Loading and Opening Window:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/* Called after laoding the nib file
** Configures gui elements
**/
- (void)awakeFromNib
{
	// Interface Builder Bug (I think)
	// The "Auto Save Name" doesn't work properly when using an NSWindowController
	[self setShouldCascadeWindows:NO];
	[self setWindowFrameAutosaveName:@"AlarmEditorWindow"];
	
	// Change window title, if needed
	if(alarmReference != nil)
	{
		NSString *title = NSLocalizedStringFromTable(@"Edit Alarm", @"AlarmEditor", @"Window title when editing an alarm");
		[[self window] setTitle:title];
	}
	
	// Set status button
	[statusButton setState:([alarm isEnabled] ? NSControlStateValueOn: NSControlStateValueOff)];
	
	// Set delete button
	[deleteButton setEnabled:(alarmReference == nil) ? NO : YES];
	
	// Set time
	[timeField setDateValue:[alarm time]];
	[self updateTimeImage];
	
	// Set date
	[dateField setDateValue:[alarm time]];

	// Replace the old NSMatrix day-of-week picker (which renders its 7 cells flush against
	// each other, with no gaps) with 7 individual push buttons laid out with a real gap
	// between them. (An NSSegmentedControl was tried first, but even in "select any"
	// mode a segmented control is one joined bar with hairline dividers, not separate
	// buttons with air between them - not what was wanted here.) Each day still toggles
	// independently (the schedule is a bitmask of days).
	//
	// Important: we iterate by grid position (cellAtRow:column:), not by tag, so the new
	// buttons appear left-to-right in the same visual order the nib laid out (localized
	// day order, e.g. Monday-first for Czech) - a cell's tag is what encodes *which power
	// of two* that day contributes to the schedule bitmask, and isn't guaranteed to match
	// its visual column. Each button keeps its cell's original tag so the bitmask math
	// below (which looks buttons up by tag, not array position) stays correct.
	if(repeatSchedule && [repeatSchedule isKindOfClass:[NSMatrix class]] && repeatDayButtons == nil)
	{
		NSMatrix *oldMatrix = repeatSchedule;
		NSView *superview = [oldMatrix superview];
		NSRect oldFrame = [oldMatrix frame];
		NSInteger dayCount = [oldMatrix numberOfColumns];

		CGFloat gap = 4.0;
		CGFloat buttonWidth = (oldFrame.size.width - gap * (dayCount - 1)) / dayCount;

		NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:dayCount];
		for(NSInteger col = 0; col < dayCount; col++)
		{
			NSCell *oldCell = [oldMatrix cellAtRow:0 column:col];
			NSRect buttonFrame = NSMakeRect(oldFrame.origin.x + col * (buttonWidth + gap),
											 oldFrame.origin.y,
											 buttonWidth, oldFrame.size.height);

			NSButton *dayButton = [[NSButton alloc] initWithFrame:buttonFrame];
			[dayButton setButtonType:NSButtonTypePushOnPushOff];
			[dayButton setBezelStyle:NSBezelStyleRounded];
			[dayButton setFont:[oldCell font]];
			[dayButton setTitle:[oldCell title]];
			[dayButton setTag:[oldCell tag]];
			[dayButton setTarget:[oldMatrix target]];
			[dayButton setAction:[oldMatrix action]];
			[dayButton setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];

			[superview addSubview:dayButton];
			[buttons addObject:dayButton];
			[dayButton release];
		}

		[oldMatrix removeFromSuperview];
		repeatDayButtons = [buttons copy];
	}

	// Set repeat type (One-time or Repeating)
	if([alarm schedule] > 0)
		[repeatType selectCellAtRow:1 column:0];
	else
		[repeatType selectCellAtRow:0 column:0];
	
	// Set repeat schedule
	int schedule = [alarm schedule];
	
	if(schedule > 0)
	{
		if(schedule >= 64) {
			[[self dayButtonWithTag:6] setState:NSControlStateValueOn];
			schedule -= 64;
		}
		if(schedule >= 32) {
			[[self dayButtonWithTag:5] setState:NSControlStateValueOn];
			schedule -= 32;
		}
		if(schedule >= 16) {
			[[self dayButtonWithTag:4] setState:NSControlStateValueOn];
			schedule -= 16;
		}
		if(schedule >= 8) {
			[[self dayButtonWithTag:3] setState:NSControlStateValueOn];
			schedule -= 8;
		}
		if(schedule >= 4) {
			[[self dayButtonWithTag:2] setState:NSControlStateValueOn];
			schedule -= 4;
		}
		if(schedule >= 2) {
			[[self dayButtonWithTag:1] setState:NSControlStateValueOn];
			schedule -= 2;
		}
		if(schedule >= 1)
			[[self dayButtonWithTag:0] setState:NSControlStateValueOn];
	}
	
	// Set easyWake
	[easyWakeButton setState:([alarm usesEasyWake] ? NSControlStateValueOn : NSControlStateValueOff)];
	
	// Set shuffle
	[shuffleButton setState:([alarm usesShuffle] ? NSControlStateValueOn : NSControlStateValueOff)];
	
	// Call methods to properly disable components (such as one-time-date if using a repeating alarm)
	[self setIsEnabled:[alarm isEnabled]];

	// The app no longer integrates with the Music library - alarms always use the built-in
	// default sound - so hide the now-unused song/playlist picker controls on the Alarm tab.
	// (Easy Wake, which lives on the same tab, stays visible.)
	[playlists setHidden:YES];
	[previewButton setHidden:YES];
	[searchField setHidden:YES];
	[searchLabel setHidden:YES];
	[shuffleButton setHidden:YES];
	[songLabel setHidden:YES];
	if([table enclosingScrollView])
		[[table enclosingScrollView] setHidden:YES];
	else
		[table setHidden:YES];

	// The nib also has a static "Source:" caption label next to the playlists popup. It has
	// no outlet (its text never changes at runtime), so we can't reference it directly - find
	// it heuristically instead: any NSTextField sharing playlists' superview, roughly on the
	// same row, that isn't one of our other known outlets.
	if(playlists && [playlists superview])
	{
		NSRect playlistsFrame = [(NSView *)playlists frame];
		for(NSView *sibling in [[playlists superview] subviews])
		{
			if(sibling == playlists || sibling == searchLabel || sibling == songLabel)
				continue;
			if(![sibling isKindOfClass:[NSTextField class]])
				continue;

			NSRect siblingFrame = [sibling frame];
			BOOL sameRow = fabs(NSMidY(siblingFrame) - NSMidY(playlistsFrame)) < 10.0;
			BOOL toTheLeft = NSMaxX(siblingFrame) <= NSMinX(playlistsFrame) + 4.0;

			if(sameRow && toTheLeft)
				[sibling setHidden:YES];
		}
	}

	// After removing the Music integration, only easyWakeButton remains visible on the
	// "Alarm" tab - a whole second NSTabView pane is no longer justified for one checkbox.
	// Eliminate the tabs entirely and rebuild the Time+Alarm content as one vertical
	// NSStackView, pulling the already-working, outlet-connected controls out of their old
	// fixed-frame boxes. Auto Layout then computes the spacing itself instead of it being
	// guessed pixel-by-pixel, which is what made the previous frame-based fixes unreliable.
	if(tabView && [(NSView *)tabView superview])
	{
		NSView *contentView = [[self window] contentView];

		// "Alarm Date:"/"Alarm Time:" are static captions with no outlets. Their containing
		// boxes aren't wired either, but can be found structurally: repeatType/timeField both
		// sit two levels inside their box's content view (box -> box's contentView -> control).
		NSView *dateBox = [[repeatType superview] superview];
		NSView *timeBox = [[(NSView *)timeField superview] superview];
		NSView *timeTabView = [dateBox superview];

		NSTextField *dateCaption = nil;
		NSTextField *timeCaption = nil;
		for(NSView *sub in [timeTabView subviews])
		{
			if(![sub isKindOfClass:[NSTextField class]])
				continue;
			CGFloat distanceToTime = fabs(NSMidY([sub frame]) - NSMidY([timeBox frame]));
			CGFloat distanceToDate = fabs(NSMidY([sub frame]) - NSMidY([dateBox frame]));
			if(distanceToTime < distanceToDate)
				timeCaption = (NSTextField *)sub;
			else
				dateCaption = (NSTextField *)sub;
		}

		NSStackView *timeRow = [self rowWithViews:@[(NSView *)timeField, (NSView *)sunMoonImage] spacing:8.0];
		NSStackView *dateFieldRow = [self rowWithViews:@[(NSView *)dateField, (NSView *)dateButton] spacing:8.0];
		NSStackView *dayButtonsRow = [self rowWithViews:repeatDayButtons spacing:4.0];

		NSMutableArray *mainRows = [NSMutableArray array];
		if(timeCaption) [mainRows addObject:timeCaption];
		[mainRows addObject:timeRow];
		if(dateCaption) [mainRows addObject:dateCaption];
		[mainRows addObject:(NSView *)repeatType];
		[mainRows addObject:dateFieldRow];
		[mainRows addObject:dayButtonsRow];
		[mainRows addObject:(NSView *)easyWakeButton];

		NSStackView *mainStack = [NSStackView stackViewWithViews:mainRows];
		[mainStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
		[mainStack setAlignment:NSLayoutAttributeLeading];
		[mainStack setSpacing:14.0];

		NSRect tabFrame = [(NSView *)tabView frame];

		[contentView addSubview:mainStack];
		[(NSView *)tabView removeFromSuperview];

		[NSLayoutConstraint activateConstraints:@[
			[[mainStack leadingAnchor] constraintEqualToAnchor:[contentView leadingAnchor] constant:tabFrame.origin.x],
			[[mainStack topAnchor] constraintEqualToAnchor:[contentView topAnchor] constant:([contentView frame].size.height - NSMaxY(tabFrame))],
			[[mainStack trailingAnchor] constraintLessThanOrEqualToAnchor:[contentView trailingAnchor] constant:-([contentView frame].size.width - NSMaxX(tabFrame))],
		]];
	}

	// Replace the old hand-drawn CalendarView + custom sheet (calPanel) with a standard
	// NSPopover containing a real NSDatePicker - the native macOS pattern for "click a
	// button, a calendar appears" (this is how Calendar.app's own date pickers work). The
	// old sheet forced a date picker into a 130x113 frame sized for the ancient bitmap,
	// which is why it didn't render or behave correctly. calPanel/calView/calMonths/
	// calYears are no longer used (same as the Apple Remote cleanup: left declared since
	// we can't edit the nib, just no longer referenced).
	[self setupCalendarPopover];

	// Cancel/OK (and other button pairs like it throughout this nib) were laid out flush
	// against each other with no gap. We don't have outlets for them, so find them by their
	// wired-up action and nudge them apart - half the gap from each side, so neither button
	// is pushed hard against a neighbor (e.g. the Delete button) or the window edge.
	{
		NSView *contentView = [[self window] contentView];
		NSButton *cancelButton = [self findButtonWithAction:@selector(cancel:) inView:contentView];
		NSButton *okButton = [self findButtonWithAction:@selector(ok:) inView:contentView];
		if(cancelButton && okButton)
		{
			NSButton *leftButton = (NSMinX([cancelButton frame]) < NSMinX([okButton frame])) ? cancelButton : okButton;
			NSButton *rightButton = (leftButton == cancelButton) ? okButton : cancelButton;
			NSRect leftFrame = [leftButton frame];
			NSRect rightFrame = [rightButton frame];
			const CGFloat desiredGap = 12.0;
			CGFloat currentGap = NSMinX(rightFrame) - NSMaxX(leftFrame);
			if(currentGap < desiredGap)
			{
				CGFloat halfShift = (desiredGap - currentGap) / 2.0;
				leftFrame.origin.x -= halfShift;
				rightFrame.origin.x += halfShift;
				[leftButton setFrame:leftFrame];
				[rightButton setFrame:rightFrame];
			}
		}
	}

	// Give the editor's content a Liquid Glass background, consistent with the rest of the app.
	NSView *contentView = [[self window] contentView];
	if(contentView)
	{
		EditorGlassBackgroundView *glassBackground = [[EditorGlassBackgroundView alloc] initWithFrame:[contentView bounds]];
		[glassBackground setMaterial:NSVisualEffectMaterialSidebar];
		[glassBackground setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
		[glassBackground setState:NSVisualEffectStateActive];
		[glassBackground setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[contentView addSubview:glassBackground positioned:NSWindowBelow relativeTo:nil];
		[glassBackground release];
	}
}

- (void)windowDidLoad
{
	// The app no longer integrates with the Music library (alarms always use the built-in
	// default sound), so there's nothing to parse here anymore.
}


/*!
 Background thread function to parse iTunes library
 
 This method is run in a separate thread.
 It parses the iTunes music library in a background thread, allowing the GUI to remain responsive.
*/
- (void)parseThread:(NSObject *)obj
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[self parseITunesMusicLibrary];
    [pool release];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Closing and Releasing Window:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when the user clicks the red close button in the window titleBar.
 
 This method checks to see if the user is trying to close the window with unsaved changes.
 If they are, they are first prompted with the standard, "wanna save changes?" dialog.
**/
- (BOOL)windowShouldClose:(id)sender
{
	if([[self window] isDocumentEdited])
	{
		// Repeating alarm type was selected, but no days were selected
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedStringFromTable(@"Do you want to save changes to this alarm before closing?", @"AlarmEditor", @"Main prompt in sheet")];
		[alert setInformativeText:NSLocalizedStringFromTable(@"If you don't save, your changes will be lost.", @"AlarmEditor", @"Sub prompt in sheet")];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Save", @"AlarmEditor", @"Dialog Button")];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Don't Save", @"AlarmEditor", @"Dialog Button")];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Cancel", @"AlarmEditor", @"Dialog Button")];
		[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn) {
				// User clicked "Save"
				// Programmatically click "OK" to start the save routine
				[self ok:self];
				
			}
			else if (returnCode == NSAlertSecondButtonReturn)
			{
				// User clicked "Don't Save"
				// Don't wait for sheet to be dismissed, immediately close the window
				[[self window] close];
			}
		}];
		return NO;
	}
	
	return YES;
}

/**
 Called immediately before the window closes.
 
 This method's job is to release the WindowController (self)
 This is so that the nib file is not held in memory,
 which helps because the alarm clock is supposed to be a background program.
**/
- (void)windowWillClose:(NSNotification *)aNotification
{
	// Post notification for closed alarm editor window
	[[NSNotificationCenter defaultCenter] postNotificationName:@"AlarmEditorWindowClosed" object:self];
	
	// Release self
	[self autorelease];
}

/**
 Standard Deallocation method.
 Release any objects this instance is retaining.
**/
- (void)dealloc
{	
	NSLog(@"Destroying %@", self);
	[alarmReference release];
	[alarm release];
	[data release];
	[playImage release];
	[stopImage release];
	[player release];
	[lock release];
	[repeatDayButtons release];
	[calendarPopover release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Parsing of iTunes Music Library:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 The app no longer integrates with the Music library, so there's no track/playlist data to
 parse or restore when switching tabs - just allow the switch.
**/
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	return YES;
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
}

/**
 Parses the iTunes data into memory.
  
 Invokes the proper procedures to parse the iTunes music library into memory.
 After this is complete, the playlist popup box is populated, and the table is loaded, and the labels are set.
 
 This method is muli-thread safe (the method first requests a lock).
 This method should complete PRIOR to displaying the alarms tab.
**/
- (void)parseITunesMusicLibrary
{
	[lock lock];
	
	// Parse iTunes data if needed
	if(data == nil)
	{
		NSLog(@"Parsing iTunes Music Library...");
		NSDate *start = [NSDate date];
		
		// Initialize data
		data = [[ITunesTable alloc] init];
		
		// Initialize player
		player = [[ITunesPlayer alloc] initWithITunesData:data];
		
		// The stored trackID may have changed
		// Check this, and update the alarm if needed
		// Also update the alarm reference, so we don't have to continually fix this everytime
		int correctTrackID = [data validateTrackID:[alarm trackID] withPersistentTrackID:[alarm persistentTrackID]];
		if(correctTrackID != [alarm trackID])
		{
			[alarm setTrackID:correctTrackID withPersistentTrackID:[alarm persistentTrackID]];
			[alarmReference setTrackID:correctTrackID withPersistentTrackID:[alarm persistentTrackID]];
		}
		
		// The stored playlistID may have changed
		// Check this, and update the alarm if needed
		// Also update the alarm reference, so we don't have to continually fix this everytime
		int correctPlaylistID = [data validatePlaylistID:[alarm playlistID] withPersistentPlaylistID:[alarm persistentPlaylistID]];
		if(correctPlaylistID != [alarm playlistID])
		{
			[alarm setPlaylistID:correctPlaylistID withPersistentPlaylistID:[alarm persistentPlaylistID]];
			[alarmReference setPlaylistID:correctPlaylistID withPersistentPlaylistID:[alarm persistentPlaylistID]];
		}
		
		NSDate *end = [NSDate date];
		NSLog(@"Done parsing (time: %f seconds)", [end timeIntervalSinceDate:start]);
		
		// Setup the playlist menu
		[self setupPlaylistMenu];
		
		// Load the data into the table
		[table reloadData];
		
		// Update song label
		[self updateSongLabelAndShuffleButton];
		
		// Update search label
		[self updateSearchLabel];
	}
	
	[lock unlock];
}

/**
 Configures the playlist using the fetched iTunes data.
 Everything is added in the proper order, with proper icons and tags.
**/
- (void)setupPlaylistMenu
{
	// Update playlist menu
	[playlists removeAllItems];
	
	int i;
	
	// Library
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist isMaster])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesLibrary.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Music
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindMusic)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesMusic.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Movies
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindMovies)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesMovies.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// TV Shows
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindTVShows)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesTVShows.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Podcasts
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindPodcasts)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesPodcasts.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Videos
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindHomeVideos ||
		   [currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindMusicVideos ||
		   [currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindLibraryMusicVideos)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesVideos.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Audiobooks
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindAudiobooks)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesAudiobooks.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Purchased Music
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindPurchases)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesPurchasedMusic.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Folders
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist kind] == ITLibPlaylistKindFolder && ![currentPlaylist parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesFolder.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
			
			// Add sub-folders and folder items
			[self addPlaylistItemsWithFolder:[currentPlaylist persistentID] indentation:1];
		}
	}
	
	// Smart Playlists
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindNone &&
		   [currentPlaylist kind] == ITLibPlaylistKindSmart &&
		   ![currentPlaylist parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesSmartPlaylist.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Normal Playlists
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindNone &&
		   ![currentPlaylist isMaster] &&
		   [currentPlaylist kind] == ITLibPlaylistKindRegular &&
		   ![currentPlaylist parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesPlaylist.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
}

/**
 Recursively adds folders (since folders may be nested), and their internal playlists
**/
- (void)addPlaylistItemsWithFolder:(NSNumber *)parentID indentation:(int)level
{
	int i;
	
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		
		if([[currentPlaylist parentID] isEqualToNumber:parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setIndentationLevel:level];
			
			if([currentPlaylist kind] == ITLibPlaylistKindFolder)
				[temp setImage:[NSImage imageNamed:@"iTunesFolder.png"]];
			else if([currentPlaylist kind] == ITLibPlaylistKindSmart)
				[temp setImage:[NSImage imageNamed:@"iTunesSmartPlaylist.png"]];
			else
				[temp setImage:[NSImage imageNamed:@"iTunesPlaylist.png"]];
			
			[temp setTag:i];
			[[playlists menu] addItem:temp];
			
			if([currentPlaylist kind] == ITLibPlaylistKindFolder)
			{
				[self addPlaylistItemsWithFolder:[currentPlaylist persistentID] indentation:(level+1)];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Methods Called by MenuController:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns the alarm object this EditorController is for
  
 This method allows the WindowManager to probe open AlarmEditor windows,
 to discover if the wanted window is already open.  If it is, it can be brought
 to the front.  If not, a new AlarmEditor window can be opened.
 
 @result  The original alarm object (a reference) is returned, which may be compared to desired alarm objects.
**/
- (Alarm *)alarmReference
{
	return alarmReference;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Toggle Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when user enables/disables the alarm.
  
 This method enables/disables all GUI elements appropriately.
 IE - if alarm is being disabled, then all GUI elements are disabled.
 The reason for doing this in rather fundamental. It should be overly obvious
 when an alarm is enabled or disabled. Users should not be allowed to edit
 disabled alarms, as they may not notice they forgot to enable the alarm.
 The last thing we want is for users to be under the impression they set an alarm, when in fact they didn't.
 
 @param sender - Object invoking method (sent from nib file)
 
 @result All GUI elements are properly enabled/disabled.
**/
- (IBAction)toggleStatus:(id)sender
{
	// Grab the status of the statusButton
	BOOL status = [statusButton state] == NSControlStateValueOn;
	
	// Set the alarm status appropriately
	[alarm setIsEnabled:status];
	
	// Enable/Disable gui elements properly
	[self setIsEnabled:status];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

/**
 Called when the user alters the date or time.
 Changes the date/time of the alarm accordingly.
 
 @param sender - Object invoking method (sent from nib file)
**/
- (IBAction)toggleDateTime:(id)sender
{
	BOOL isRepeating = [repeatType selectedRow] == 1;
	
	// Update the schedule if needed
	if(sender == repeatType || [repeatDayButtons containsObject:sender])
	{
		// Enable, disable components
		[dateField		setEnabled:!isRepeating];
		[dateButton     setEnabled:!isRepeating];
		for(NSButton *dayButton in repeatDayButtons)
		{
			[dayButton setEnabled:isRepeating];
		}

		if(!isRepeating)
		{
			[alarm setSchedule:0];
		}
		else
		{
			// Get schedule total
			int total = 0;

			// If it repeats weekly
			if([[self dayButtonWithTag:6] state] == NSControlStateValueOn) total += 64;
			if([[self dayButtonWithTag:5] state] == NSControlStateValueOn) total += 32;
			if([[self dayButtonWithTag:4] state] == NSControlStateValueOn) total += 16;
			if([[self dayButtonWithTag:3] state] == NSControlStateValueOn) total += 8;
			if([[self dayButtonWithTag:2] state] == NSControlStateValueOn) total += 4;
			if([[self dayButtonWithTag:1] state] == NSControlStateValueOn) total += 2;
			if([[self dayButtonWithTag:0] state] == NSControlStateValueOn) total += 1;

			[alarm setSchedule:total];
		}
	}
	
	// Update the date/time
	NSDate *dmy, *hm, *newTime;
	NSCalendar *calendar = [NSCalendar currentCalendar];
	
	// Set the time from timeField
	hm = [timeField dateValue];
	
	// Set the date from the dateField if one-time alarm
	//  or from a time in the past (yesterday) if a repeating alarm (It will get updated to the proper time)
	dmy = [dateField dateValue];
	if(isRepeating) {
		NSDateComponents *components = [[NSDateComponents alloc] init];
		[components setDay:-1];
		dmy = [calendar dateByAddingComponents:components toDate:[NSDate date] options:0];
		[components release];
	}
	
	NSDateComponents *components = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:dmy];
	components.hour  = [calendar component:NSCalendarUnitHour fromDate:hm];
	components.minute = [calendar component:NSCalendarUnitMinute fromDate:hm];
	components.second = 0;
	
	newTime = [calendar dateFromComponents:components];
	
	// Set the alarm's time
	[alarm setTime:newTime];
	
	// And make sure it's updated
	[alarm updateTime];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
	
	// And finally, update the sunMoonImage to reflect the AM/PM status
	[self updateTimeImage];
}

/**
 Called when user alters the state of the easyWake switch button.
 Changes usesEasyWake option of alarm accordingly.
 
 @param sender - Object invoking method (sent from nib file)
**/
- (IBAction)toggleEasyWake:(id)sender
{
	// Set the alarm easyWake property appropriately
	[alarm setUsesEasyWake:([sender state] == NSControlStateValueOn)];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

/**
 * Called when user alters the state of the shuffle switch button.
 * Changes usesShuffle option of alarm accordingly.
 *
 * @param  sender - Object invoking method (sent from nib file)
**/
- (IBAction)toggleShuffle:(id)sender
{
	// Set the alarm usesShuffle property appropriately
	[alarm setUsesShuffle:([sender state] == NSControlStateValueOn)];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Date Selection:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Builds the NSPopover + NSDatePicker used by -selectDate:, the native macOS pattern for
 * "click a button, a calendar appears" (e.g. Calendar.app's own date pickers). Called once
 * from -awakeFromNib.
**/
- (void)setupCalendarPopover
{
	calendarDatePicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 280, 220)];
	[calendarDatePicker setDatePickerStyle:NSDatePickerStyleClockAndCalendar];
	[calendarDatePicker setDatePickerElements:NSDatePickerElementFlagYearMonthDay];
	[calendarDatePicker setDatePickerMode:NSDatePickerModeSingle];
	[calendarDatePicker setBezeled:NO];
	[calendarDatePicker setDrawsBackground:NO];
	[calendarDatePicker setTarget:self];
	[calendarDatePicker setAction:@selector(popoverDateChanged:)];

	NSViewController *popoverVC = [[NSViewController alloc] init];
	NSView *popoverView = [[NSView alloc] initWithFrame:[calendarDatePicker frame]];
	[popoverView addSubview:calendarDatePicker];
	[popoverVC setView:popoverView];
	[popoverView release];

	calendarPopover = [[NSPopover alloc] init];
	[calendarPopover setContentViewController:popoverVC];
	[calendarPopover setBehavior:NSPopoverBehaviorTransient];
	[popoverVC release];
}

/**
 * No longer used now that the calendar is shown in an NSPopover (see -selectDate:), but left
 * as harmless no-ops since they're still declared in the header - same pattern as the Apple
 * Remote cleanup.
**/
- (IBAction)changeCal:(id)sender
{
}

- (IBAction)closeCalPanel:(id)sender
{
}

/**
 * Called when the user clicks the button to select a date.
 *
 * Sets the date picker to the date currently shown in the text field, then shows it in a
 * popover anchored to the button that was clicked.
 *
 * @result  Calendar popover is displayed.
**/
- (IBAction)selectDate:(id)sender
{
	[calendarDatePicker setDateValue:[dateField dateValue]];
	[calendarPopover showRelativeToRect:[(NSView *)sender bounds] ofView:(NSView *)sender preferredEdge:NSMinYEdge];
}

/**
 * Target/action of calendarDatePicker: updates the date field and dismisses the popover.
**/
- (IBAction)popoverDateChanged:(id)sender
{
	[dateField setDateValue:[calendarDatePicker dateValue]];
	[calendarPopover close];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Table Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when the user switches the playlist.
 Method performs switch, and updates table and label.
 
 @param sender - Object invoking method (sent from nib file)
**/
- (IBAction)switchSource:(id)sender
{
	// First deselect any selected songs
	// This is important, because this fires the tableSelectionDidChange method
	[table deselectAll:self];
	
	NSInteger playlistIndex = [[playlists selectedItem] tag];
		
	// Perform switch on table
	[data setPlaylist:playlistIndex];
		
	// Get playlist
	ITLibPlaylist *playlist = [[data playlists] objectAtIndex:playlistIndex];
	
	// Update alarm playlist and type
	NSNumber *persistentPlaylistID = [playlist persistentID];
	[alarm setPlaylistID:(int)playlistIndex withPersistentPlaylistID:persistentPlaylistID];
	[alarm setType:ALARMTYPE_PLAYLIST];
	
	// Clear search field
	[searchField setStringValue:@""];
	
	// Update search label
	[self updateSearchLabel];
	
	// Update song label (and shuffle button)
	[self updateSongLabelAndShuffleButton];
	
	// Update table
	[table reloadData];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

/*!
 @abstract   Called whenever the user types something into the search field.
 @discussion
 
 Performs the search, and updates table and search label.
 
 @result Table is properly filtered, displaying search results.
*/
- (IBAction)search:(id)sender
{
	// Perform search
	[data setSearchCriteria:[searchField stringValue]];
		
	// Update search label
	[self updateSearchLabel];
		
	// Notify table of changes
	[table reloadData];
}

- (IBAction)preview:(id)sender
{
	if([player isPlaying])
	{
		[player stop];
		[previewButton setImage:playImage];
	}
	else
	{
		// Configure the player for the new preview
		if([alarm isPlaylist])
		{
			[player setPlaylistWithPlaylistID:[alarm playlistID] usesShuffle:[alarm usesShuffle]];
		}
		else if([alarm isTrack])
		{
			[player setTrackWithTrackID:[alarm trackID]];
		}
		else
		{
			[player setFileWithPath:[Alarm defaultAlarmFile]];
		}
		
		// Start the player
		[player play];
		
		// Verify it's playing, and change the button if needed
		if([player isPlaying])
		{
			[previewButton setImage:stopImage];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Table Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called automatically by Cocoa.
 Returns the number of items in the table.
**/
- (NSUInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [[data table] count];
}

/**
 Called automatically by Cocoa.
 Returns the proper object that should be placed at the given row and column.
**/
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)col row:(int)rowIndex
{
	int trackID = [[[data table] objectAtIndex:rowIndex] intValue];
	ITLibMediaItem *track = [data trackForID:trackID];
	
	if([@"Song" isEqualToString:[col identifier]])
	{
		return [track title];
	}
	else if([@"Artist" isEqualToString:[col identifier]])
	{
		return [[track artist] name];
	}
	else
	{
		int millis = (int)[track totalTime];
		int totalSeconds = millis / 1000;
		int minutes = totalSeconds / 60;
		int seconds = totalSeconds % 60;
		
		if(seconds < 10)
			return [NSString stringWithFormat:@"%i:0%i",minutes,seconds];
		else
			return [NSString stringWithFormat:@"%i:%i", minutes,seconds];
	}
}

/**
 Called before cells in table are displayed.
 Allows the programmer to alter the default appearance of cells.
 This is used to make the table smaller by using a smaller font size.
**/
- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)col row:(int)rowIndex
{
	NSFont *smallFont = [NSFont userFontOfSize:[NSFont smallSystemFontSize]];
	[aCell setFont:smallFont];
}

/**
 Called when the user double-clicks on a cell.
 This is used to play a preview of a song.
**/
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)col row:(int)rowIndex
{	
	// Stop playing current song
	if([player isPlaying])
	{
		[player stop];
		[previewButton setImage:playImage];
	}
	
	// Play selected song
	[self preview:self];
	
	return NO;
}

/**
 Called when the user selects a song in the table.
  
 This method updates the alarm file.
 It updates the trackID and persistentTrackID of the alarm.
 
 @param  aNotification - NSNotification sent from table
**/
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if([table selectedRow] >= 0)
	{
		// User selected a song
		// Grab the trackID, which is simply the object at that index in the table
		int trackID = [[[data table] objectAtIndex:[table selectedRow]] intValue];
		
		// Now grab the Track dictionary
		ITLibMediaItem *track = [data trackForID:trackID];
		NSNumber *persistentTrackID = [track persistentID];
		
		// Set the alarm file and type
		[alarm setTrackID:trackID withPersistentTrackID:persistentTrackID];
		[alarm setType:ALARMTYPE_TRACK];
	}
	else
	{
		// User deselected a song, so nothing is selected
		// Revert to default alarm file
		[alarm setTrackID:0 withPersistentTrackID:nil];
		[alarm setType:ALARMTYPE_DEFAULT];
	}
	
	// Update the song label (and shuffle button)
	[self updateSongLabelAndShuffleButton];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Button Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when the user clicks the 'OK' button.
**/
- (IBAction)ok:(id)sender
{
	BOOL isRepeating = [repeatType selectedRow] == 1;
	
	if(([alarm schedule] == 0) && isRepeating)
	{
		// Repeating alarm type was selected, but no days were selected
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedStringFromTable(@"Invalid alarm time", @"AlarmEditor", @"Main prompt in sheet")];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Please select the days the alarm should repeat.", @"AlarmEditor", @"Sub prompt in sheet")];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"AlarmEditor", @"Dialog Button")];
		[alert beginSheetModalForWindow:self.window completionHandler:nil];
		return;
	}
	
	NSDate *dmy, *hm, *newTime;
	NSCalendar *calendar = [NSCalendar currentCalendar];
	
	// Set the time from timeField
	hm = [timeField dateValue];
	
	// Set the date from the dateField if one-time alarm
	//  or from a time in the past (yesterday) if a repeating alarm (It will get updated to the proper time)
	dmy = [dateField dateValue];
	if(isRepeating) {
		NSDateComponents *components = [[NSDateComponents alloc] init];
		[components setDay:-1];
		dmy = [calendar dateByAddingComponents:components toDate:[NSDate date] options:0];
		[components release];
	}
	
	NSDateComponents *components = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:dmy];
	components.hour  = [calendar component:NSCalendarUnitHour fromDate:hm];
	components.minute = [calendar component:NSCalendarUnitMinute fromDate:hm];
	components.second = 0;

	newTime = [calendar dateFromComponents:components];
	
	// Set the time
	[alarm setTime:newTime];
	
	// Make sure the time is updated
	[alarm updateTime];
	
	// Ensure the time is at least a second or two after now
	if([[alarm time] timeIntervalSinceNow] < 1)
	{
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedStringFromTable(@"Invalid alarm time", @"AlarmEditor", @"Main prompt in sheet")];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Please select a date and time in the future.", @"AlarmEditor", @"Error message in AlarmEditor")];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"AlarmEditor", @"Dialog Button")];
		[alert beginSheetModalForWindow:self.window completionHandler:nil];
	}
	else
	{
		// Register alarm with Alarms
		if(alarmReference == nil)
			[ADClockScheduler addAlarm:alarm];
		else
			[ADClockScheduler setAlarm:alarm forReference:alarmReference];
		
		// Close the window
		// Note: this is different than performClose as the delegate is NOT sent shouldWindowClose
		[[self window] close];
	}
}

/**
 Called when the user clicks the 'Cancel' button.
**/
- (IBAction)cancel:(id)sender
{
	// Close the window
	// Note: this is different than performClose as the delegate is NOT sent shouldWindowClose
	[[self window] close];
}

/**
 Called when the user clicks the 'Delete' button.
**/
- (IBAction)delete:(id)sender
{
	// Delete the alarm, using the original reference
	[ADClockScheduler removeAlarm:alarmReference];
	
	// Close the window
	// Note: this is different than performClose as the delegate is NOT sent shouldWindowClose
	[[self window] close];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setIsEnabled:(BOOL)isEnabled
{	
	/// Time Tab ///
	
	// Time
	[timeField      setEnabled:isEnabled];
	
	// Date, repeat type, and repeat schedule
	[repeatType     setEnabled:isEnabled];
	
	BOOL isRepeating = [alarm schedule] > 0;
	
	[dateField      setEnabled:(isEnabled && !isRepeating)];
	[dateButton     setEnabled:(isEnabled && !isRepeating)];
	for(NSButton *dayButton in repeatDayButtons)
	{
		[dayButton setEnabled:(isEnabled && isRepeating)];
	}
	
	/// Alarm Tab ///
	
	// Playlist chooser, preview button, search field
	[playlists      setEnabled:isEnabled];
	[previewButton  setEnabled:isEnabled];
	[searchField    setEnabled:isEnabled];
	
	// Easy wake button
	[easyWakeButton setEnabled:isEnabled];
	
	// Shuffle button
	BOOL isPlaylist = [alarm isPlaylist];
	
	[shuffleButton setEnabled:(isEnabled && isPlaylist)];
}

/**
 * Updates the image next to the time field.
 * If it's AM, sets the image to a sun.
 * If it's PM, sets the image to a moon.
**/
- (void)updateTimeImage
{
	NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
	[df setFormatterBehavior:NSDateFormatterBehavior10_4];
	[df setDateStyle:NSDateFormatterNoStyle];
	[df setTimeStyle:NSDateFormatterShortStyle];
	
	NSRange range = [[df dateFormat] rangeOfString:@"a"];
	
	if(range.length == 0)
	{
		// The user is using a 24 hour clock
		[sunMoonImage setHidden:YES];
	}
	else
	{
		[sunMoonImage setHidden:NO];
		
        NSInteger hourOfDay = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[alarm time]];
		
		if(hourOfDay >= 6 && hourOfDay < 18)
			[sunMoonImage setImage:[NSImage imageNamed:@"sun.png"]];
		else
			[sunMoonImage setImage:[NSImage imageNamed:@"moon.png"]];
	}
}

/**
 * Updates the search label to reflect the number of songs currently in the table.
**/
- (void)updateSearchLabel
{
	NSInteger tableCount = [[data table] count];
	
	if(tableCount == 1)
	{
		NSString *format = NSLocalizedStringFromTable(@"1 song", @"AlarmEditor", @"Label next to search field");
		[searchLabel setStringValue:format];
	}
	else
	{
		NSString *format = NSLocalizedStringFromTable(@"%i songs", @"AlarmEditor", @"Label next to search field");
		[searchLabel setStringValue:[NSString stringWithFormat:format, tableCount]];
	}
}

/**
 Updates the song label and properly enables/disables the shuffleButton.
 The song label reflects the currently selected song or playlist.
 If nothing is selected (or an invalid trackID/playlistID is set) then "Default Alarm" is displayed.
 The shuffle button is disabled unles a playlist is selected.
**/
- (void)updateSongLabelAndShuffleButton
{
	// Check to make sure data isn't nil
	// If it is, then iTunes hasn't been fully parsed yet, and we don't even need to bother
	if(data == nil) return;
	
	NSString *defaultStr = NSLocalizedStringFromTable(@"Default Alarm", @"AlarmEditor", @"Song label when no track/playlist is selected.");
	
	if([alarm isPlaylist])
	{
		NSString *playlistName = [[data playlistForID:[alarm playlistID]] name];
		if(playlistName != nil)
		{
			NSString *format  = NSLocalizedStringFromTable(@"Playlist: %@", @"AlarmEditor", @"Song label when using a playlist");
			[songLabel setStringValue:[NSString stringWithFormat:format, playlistName]];
			
			// We can enable the shuffle button in this scenario
			// But remember, only if the alarm is enabled
			[shuffleButton setEnabled:[alarm isEnabled]];
		}
		else
		{
			[songLabel setStringValue:defaultStr];
			[shuffleButton setEnabled:NO];
		}
	}
	else if([alarm isTrack])
	{
		NSString *songName = [[data trackForID:[alarm trackID]] title];
		if(songName != nil)
		{
			NSString *format = NSLocalizedStringFromTable(@"Song: %@", @"AlarmEditor", @"Song label when using a song");
			[songLabel setStringValue:[NSString stringWithFormat:format, songName]];
			[shuffleButton setEnabled:NO];
		}
		else
		{
			[songLabel setStringValue:defaultStr];
			[shuffleButton setEnabled:NO];
		}
	}
	else
	{
		[songLabel setStringValue:defaultStr];
		[shuffleButton setEnabled:NO];
	}
}

- (void)updateWindowStatus
{
	// If the alarm has changed, put the little dot in the red close button
	[[self window] setDocumentEdited:![alarm isEqualToAlarm:alarmReference]];
}

@end
