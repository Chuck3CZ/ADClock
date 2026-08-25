#import "TransparentView.h"
#import "TransparentController.h"

@implementation TransparentView

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Standard init method for NSView.
 This method handles configuring the styles for the various elements, and sets up the NSRect variables.
**/
- (id)initWithFrame:(NSRect)frameRect
{
	if(self = [super initWithFrame:frameRect])
	{
		// Setup alignment of strings
		NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
		[paragraphStyle setAlignment:NSTextAlignmentCenter];
		[paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
		
		// Setup shadow for strings
		NSShadow *textShadow = [[[NSShadow alloc] init] autorelease];
		NSSize shadowSize = {0.0f, -1.5f};
		[textShadow setShadowOffset:shadowSize];
		[textShadow setShadowBlurRadius:3.5f];
		[textShadow setShadowColor:[NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:0.92]];
		
		// Setup status attributes
		NSFont *statusFont = [NSFont labelFontOfSize:[NSFont systemFontSize]+2];
		NSColor *statusColor = [NSColor whiteColor];
		
		NSMutableDictionary *statusAttrTemp = [NSMutableDictionary dictionaryWithCapacity:4];
		[statusAttrTemp setObject:statusFont forKey:NSFontAttributeName];
		[statusAttrTemp setObject:textShadow forKey:NSShadowAttributeName];
		[statusAttrTemp setObject:statusColor forKey:NSForegroundColorAttributeName];
		[statusAttrTemp setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		statusAttributes = [statusAttrTemp copy];
		
		// Setup clock attributes
		NSFont *clockFont = [NSFont userFixedPitchFontOfSize:50.0];
		NSColor *clockColor = [NSColor whiteColor];
		
		NSMutableDictionary *clockAttrTemp = [NSMutableDictionary dictionaryWithCapacity:3];
		[clockAttrTemp setObject:clockFont forKey:NSFontAttributeName];
		[clockAttrTemp setObject:clockColor forKey:NSForegroundColorAttributeName];
		[clockAttrTemp setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		clockAttributes = [clockAttrTemp copy];
		
		// Setup button attributes
		NSFont *buttonFont = [NSFont labelFontOfSize:[NSFont systemFontSize]+2];
		NSColor *buttonColor = [NSColor whiteColor];
		
		NSMutableDictionary *buttonAttrTemp = [NSMutableDictionary dictionaryWithCapacity:4];
		[buttonAttrTemp setObject:buttonFont forKey:NSFontAttributeName];
		[buttonAttrTemp setObject:textShadow forKey:NSShadowAttributeName];
		[buttonAttrTemp setObject:buttonColor forKey:NSForegroundColorAttributeName];
		[buttonAttrTemp setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		buttonAttributes = [buttonAttrTemp copy];
		
		// Setup Rects

		/*
		 We now setup the viewRect
		 This sets up the drawable portion of the window
		 Effectively giving the window a nice padding between content and edges.
		 The top inset is taller than the bottom to leave room for the real (transparent)
		 system titlebar and its traffic-light buttons, which now sit above our content.
		 */
		float topInset = 32.0;
		float bottomInset = 15.0;

		viewRect.origin.x = frameRect.origin.x + 12;
		viewRect.origin.y = frameRect.origin.y + bottomInset;
		viewRect.size.width = frameRect.size.width - 24;
		viewRect.size.height = frameRect.size.height - bottomInset - topInset;
		
		// Don't forget - Coordinate system => 0,0 => Lower lefthand corner
		
		float buttonSpace = 14.0;
		float buttonWidth = ((viewRect.size.width - buttonSpace) / 2.0);
		
		leftButtonRect.origin.x = viewRect.origin.x;
		leftButtonRect.origin.y = viewRect.origin.y;
		leftButtonRect.size.width  = buttonWidth;
		leftButtonRect.size.height = [buttonFont pointSize] + 8;
		
		rightButtonRect.origin.x = leftButtonRect.origin.x + leftButtonRect.size.width + buttonSpace;
		rightButtonRect.origin.y = viewRect.origin.y;
		rightButtonRect.size.width = buttonWidth;
		rightButtonRect.size.height = [buttonFont pointSize] + 8;
		
		clockRect.origin.x = viewRect.origin.x;
		clockRect.origin.y = leftButtonRect.origin.y + leftButtonRect.size.height + 20;
		clockRect.size.width  = viewRect.size.width;
		clockRect.size.height = [clockFont pointSize] + 15;
		
		statusLine2Rect.origin.x = viewRect.origin.x + 25;
		statusLine2Rect.origin.y = clockRect.origin.y + clockRect.size.height + 15;
		statusLine2Rect.size.width  = viewRect.size.width - 50;
		statusLine2Rect.size.height = [statusFont pointSize] + 8;
		
		leftModifierRect.origin.x = viewRect.origin.x;
		leftModifierRect.origin.y = statusLine2Rect.origin.y + 2;
		leftModifierRect.size.width  = [statusFont pointSize] + 4;
		leftModifierRect.size.height = [statusFont pointSize] + 4;
		
		rightModifierRect.origin.x = viewRect.origin.x + viewRect.size.width - ([statusFont pointSize] + 4);
		rightModifierRect.origin.y = statusLine2Rect.origin.y + 2;
		rightModifierRect.size.width  = [statusFont pointSize] + 4;
		rightModifierRect.size.height = [statusFont pointSize] + 4;
		
		statusLine1Rect.origin.x = viewRect.origin.x + 25;
		statusLine1Rect.origin.y = statusLine2Rect.origin.y + statusLine2Rect.size.height + 5;
		statusLine1Rect.size.width  = viewRect.size.width - 50;
		statusLine1Rect.size.height = [statusFont pointSize] + 4;
		
		// Store the original bounds
		originalViewBounds = [self bounds];
		
		// Configure minimum size of window and view
		NSRect originalViewFrame = [self frame];
		
		minSize.width = 160;
		minSize.height = 160 * (originalViewFrame.size.height / originalViewFrame.size.width);
	}
	return self;
}

/**
 Don't forget to tidy up!
**/
-(void) dealloc
{
	//NSLog(@"Destroying %@", self);
	[statusAttributes release];
	[clockAttributes release];
	[buttonAttributes release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Overridden NSView Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 We want to respond to click-through.
 That is, we want to be notified of the first click on this view, when the window is not key.
 This is similar behavior to other windows on OS X.
**/
- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	return YES;
}

- (void)setFrame:(NSRect)newViewFrame
{
	[super setFrame:newViewFrame];
	[super setBounds:originalViewBounds];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Drawing Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Helper method to fill rects with specified radius', colors and highlight state.
 This method handles the underlying bezier path methods and drawing.
**/
- (void)fillRect:(NSRect)rect topRadius:(float)tRad bottomRadius:(float)bRad color:(NSColor *)bgColor highlight:(BOOL)highlight
{
	int minX = NSMinX(rect);
	int midX = NSMidX(rect);
    int maxX = NSMaxX(rect);
    int minY = NSMinY(rect);
    int midY = NSMidY(rect);
    int maxY = NSMaxY(rect);
    
    NSBezierPath *bgPath = [NSBezierPath bezierPath];
    
    // Bottom edge and bottom-right curve
    [bgPath moveToPoint:NSMakePoint(midX, minY)];
    [bgPath appendBezierPathWithArcFromPoint:NSMakePoint(maxX, minY) 
                                     toPoint:NSMakePoint(maxX, midY) 
                                      radius:bRad];
    
    // Right edge and top-right curve
    [bgPath appendBezierPathWithArcFromPoint:NSMakePoint(maxX, maxY) 
                                     toPoint:NSMakePoint(midX, maxY) 
                                      radius:tRad];
    
    // Top edge and top-left curve
    [bgPath appendBezierPathWithArcFromPoint:NSMakePoint(minX, maxY) 
                                     toPoint:NSMakePoint(minX, midY) 
                                      radius:tRad];
    
    // Left edge and bottom-left curve
    [bgPath appendBezierPathWithArcFromPoint:rect.origin 
                                     toPoint:NSMakePoint(midX, minY) 
                                      radius:bRad];
    [bgPath closePath];
    
    [bgColor set];
    [bgPath fill];
	
	if(highlight)
	{
		[[NSColor whiteColor] set];
		[bgPath setLineWidth:2.0];
		[bgPath stroke];
	}
}

/**
 Helper method to draw background for buttons (and clock).
 Fills all buttons with standard background color.
**/
- (void)fillRoundedRect:(NSRect)rect usingRadius:(float)radius color:(NSColor *)baseColor andRollover:(BOOL)rollover andClick:(BOOL)click
{
	// Darken slightly on click, same trick as before, just starting from a semantic
	// color instead of a flat hardcoded gray.
	NSColor *bgColor = click ? [baseColor colorWithAlphaComponent:[baseColor alphaComponent] * 0.6] : baseColor;

	[self fillRect:rect topRadius:radius bottomRadius:radius color:bgColor highlight:rollover];
}

- (void)drawRect:(NSRect)rect
{
	// The window chrome (titlebar, traffic lights, resize) and the glass background are now
	// provided by the real system window (see TransparentWindow's -awakeFromNib), so we only
	// draw the smaller "pill" elements (clock, modifier and left/right buttons) on top of it.

	// Status line 1
	[[transparentController statusLine1] drawInRect:statusLine1Rect withAttributes:statusAttributes];
	
	// Status line 2
	[[transparentController statusLine2] drawInRect:statusLine2Rect withAttributes:statusAttributes];
	
	// Dynamic, semantic colors instead of flat hardcoded gray, so the pills pick up
	// vibrancy/contrast from the glass behind them and the user's own accent color,
	// rather than looking like flat gray chips regardless of appearance/wallpaper.
	NSColor *chipColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.16];
	NSColor *clockColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.28];
	NSColor *actionColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.55];

	if([transparentController shouldDisplayModifierButtons])
	{
		// Left modifier
		[self fillRoundedRect:leftModifierRect usingRadius:3.0 color:chipColor andRollover:isRolloverMinus andClick:isPressedMinus];
		[[transparentController leftModifierStr] drawInRect:leftModifierRect withAttributes:buttonAttributes];

		// Right modifier
		[self fillRoundedRect:rightModifierRect usingRadius:3.0 color:chipColor andRollover:isRolloverPlus andClick:isPressedPlus];
		[[transparentController rightModifierStr] drawInRect:rightModifierRect withAttributes:buttonAttributes];
	}

	// Clock display
	[self fillRoundedRect:clockRect usingRadius:15.0 color:clockColor andRollover:NO andClick:NO];
	[[transparentController timeStr] drawInRect:clockRect withAttributes:clockAttributes];

	// Left button
	[self fillRoundedRect:leftButtonRect usingRadius:12.0 color:actionColor andRollover:isRolloverLeft andClick:isPressedLeft];
	[[transparentController leftButtonStr] drawInRect:leftButtonRect withAttributes:buttonAttributes];

	// Right button
	[self fillRoundedRect:rightButtonRect usingRadius:12.0 color:actionColor andRollover:isRolloverRight andClick:isPressedRight];
	[[transparentController rightButtonStr] drawInRect:rightButtonRect withAttributes:buttonAttributes];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mouse Movement and Action:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Receives mouse movement events, forwarded from the window.
 If the mouse moves inside any of the active buttons, those buttons are highlighted.
 
 Note that we don't terminate early if we find movement in or out of a button rect.
 It's possible to have overlapping buttons, or buttons right next to each other.
 Thus in one mouse movement, there could theoretically be multiple updates.
 Therefore we check each rect for mouse activity.
**/
- (void)mouseMoved:(NSEvent *)event
{
	// Convert the window coordinates to our scaled coordinate system for this view
	NSPoint mousePoint = [self convertPoint:[event locationInWindow] fromView:nil];

	// Left, Right modifiers
	BOOL newIsRolloverMinus = [self mouse:mousePoint inRect:leftModifierRect];
	BOOL newIsRolloverPlus = [self mouse:mousePoint inRect:rightModifierRect];
	
	if([transparentController shouldDisplayModifierButtons])
	{
		if((newIsRolloverMinus != isRolloverMinus) || (newIsRolloverPlus != isRolloverPlus))
		{
			isRolloverMinus = newIsRolloverMinus;
			isRolloverPlus = newIsRolloverPlus;
			[self setNeedsDisplay:YES];
		}
	}
	
	// Left, Right buttons
	BOOL newIsRolloverLeft = [self mouse:mousePoint inRect:leftButtonRect];
	BOOL newIsRolloverRight = [self mouse:mousePoint inRect:rightButtonRect];
	
	if((newIsRolloverLeft != isRolloverLeft) || (newIsRolloverRight != isRolloverRight))
	{
		isRolloverLeft = newIsRolloverLeft;
		isRolloverRight = newIsRolloverRight;
		[self setNeedsDisplay:YES];
	}
}

/**
 Called when the user presses the left mouse button down.
 We check to see if the mouse down event was in any of the active buttons.
 If it was, this click is noted, and the button changes appearance to reflect the click.
 If the mouse wasn't pressed on any buttons, then we allow the user to move the window,
 and make the necessary preparations.
**/
- (void)mouseDown:(NSEvent *)event
{
	// Convert the window coordinates to our scaled coordinate system for this view
	NSPoint mouseLocationInWindow = [event locationInWindow];
	NSPoint mouseLocationInView   = [self convertPoint:mouseLocationInWindow fromView:nil];
	
	if([self mouse:mouseLocationInView inRect:statusLine1Rect] || [self mouse:mouseLocationInView inRect:statusLine2Rect])
	{
		// Status Line 1 or 2
		// These fire on mouse down
		[transparentController statusLineClicked];
		[self setNeedsDisplay:YES];
	}
	
	if([transparentController shouldDisplayModifierButtons] && [self mouse:mouseLocationInView inRect:rightModifierRect])
	{
		// Plus button
		wasPressedPlus = isPressedPlus = YES;
		[self setNeedsDisplay:YES];
	}
	else if([transparentController shouldDisplayModifierButtons] && [self mouse:mouseLocationInView inRect:leftModifierRect])
	{
		// Decrease button
		wasPressedMinus = isPressedMinus = YES;
		[self setNeedsDisplay:YES];
	}
	else if([self mouse:mouseLocationInView inRect:leftButtonRect])
	{
		// Left button
		wasPressedLeft = isPressedLeft = YES;
		[self setNeedsDisplay:YES];
	}
	else if([self mouse:mouseLocationInView inRect:rightButtonRect])
	{
		// Rigth button
		wasPressedRight = isPressedRight = YES;
		[self setNeedsDisplay:YES];
	}
	else
	{
		// Click anywhere else in window
		isPressedWindow = YES;
		
		// Store initial frame and location
		initialWindowFrame = [[self window] frame];
		initialLocationInWindow = [event locationInWindow];
		initialLocationInScreen = [[self window] convertRectToScreen:NSMakeRect(initialLocationInWindow.x, initialLocationInWindow.y, 0, 0)].origin;
	}
}

/**
 Constantly called while the user drags the mouse around the screen.
 If the user is moving the window around, or resizing the window, we quickly react and immediately return.
 Otherwise, we check to see if the mouse is moving over buttons.
 Remember, buttons only light up (during drag) if they were originally clicked on.
 Otherwise mouse movement during a drag is ignored for buttons.
**/
- (void)mouseDragged:(NSEvent *)event
{
	if(isPressedWindow)
	{
		NSPoint currentLocation;
		NSPoint newOrigin;
		NSRect  screenFrame = [[NSScreen mainScreen] frame];
		NSRect  windowFrame = [[self window] frame];
		
		NSPoint windowPoint = [event locationInWindow];
		currentLocation = [[self window] convertRectToScreen:NSMakeRect(windowPoint.x, windowPoint.y, 0, 0)].origin;
		newOrigin.x = currentLocation.x - initialLocationInWindow.x;
		newOrigin.y = currentLocation.y - initialLocationInWindow.y;
		
		CGFloat menuBarHeight = [[NSStatusBar systemStatusBar] thickness];
		if((newOrigin.y + windowFrame.size.height) > (NSMaxY(screenFrame) - menuBarHeight))
		{
			// Prevent dragging into the menu bar area
			newOrigin.y = NSMaxY(screenFrame) - windowFrame.size.height - menuBarHeight;
		}
		
		[[self window] setFrameOrigin:newOrigin];
		
		return;
	}
	
	// Convert the window coordinates to our scaled coordinate system for this view
	NSPoint mousePoint = [self convertPoint:[event locationInWindow] fromView:nil];

	// Left, Right modifiers - Ignored if not currently active
	BOOL newIsPressedMinus = [self mouse:mousePoint inRect:leftModifierRect];
	BOOL newIsPressedPlus = [self mouse:mousePoint inRect:rightModifierRect];
	
	if([transparentController shouldDisplayModifierButtons])
	{
		if((newIsPressedPlus != isPressedPlus) || (newIsPressedMinus != isPressedMinus))
		{
			isRolloverMinus = isPressedMinus = wasPressedMinus && newIsPressedMinus;
			isRolloverPlus = isPressedPlus = wasPressedPlus && newIsPressedPlus;
			[self setNeedsDisplay:YES];
		}
	}
	
	// Left, Right buttons
	BOOL newIsPressedLeft = [self mouse:mousePoint inRect:leftButtonRect];
	BOOL newIsPressedRight = [self mouse:mousePoint inRect:rightButtonRect];
	
	if((newIsPressedLeft != isPressedLeft) || (newIsPressedRight != isPressedRight))
	{
		isRolloverLeft = isPressedLeft = wasPressedLeft && newIsPressedLeft;
		isRolloverRight = isPressedRight = wasPressedRight && newIsPressedRight;
		[self setNeedsDisplay:YES];
	}
}

/**
 Called when the user releases the mouse from it's pressed down state.
 If the user pressed down and released on the same button, then that button fires.
 Otherwise, the event is ignored, just as it would be under normal circumstances.
**/
- (void)mouseUp:(NSEvent *)event
{
	// Convert the window coordinates to our scaled coordinate system for this view
	NSPoint mousePoint = [self convertPoint:[event locationInWindow] fromView:nil];
	
	if(isPressedMinus && [transparentController shouldDisplayModifierButtons])
	{
		// Left Modifier
		wasPressedMinus = isPressedMinus = NO;
		if([self mouse:mousePoint inRect:leftModifierRect])
		{
			[transparentController leftModifierClicked];
			[self setNeedsDisplay:YES];
		}
	}
	else if(isPressedPlus && [transparentController shouldDisplayModifierButtons])
	{
		// Right Modifier
		wasPressedPlus = isPressedPlus = NO;
		if([self mouse:mousePoint inRect:rightModifierRect])
		{
			[transparentController rightModifierClicked];
			[self setNeedsDisplay:YES];
		}
	}
	else if(isPressedLeft)
	{
		// Left Button
		wasPressedLeft = isPressedLeft = NO;
		if([self mouse:mousePoint inRect:leftButtonRect])
		{
			[transparentController leftButtonClicked];
			[self setNeedsDisplay:YES];
		}
	}
	else if(isPressedRight)
	{
		// Right Button
		wasPressedRight = isPressedRight = NO;
		if([self mouse:mousePoint inRect:rightButtonRect])
		{
			[transparentController rightButtonClicked];
			[self setNeedsDisplay:YES];
		}
	}
	else
	{
		isPressedWindow = NO;
	}
}

// Used by TransparentWindow to configure real system window resize behavior
// (content aspect ratio / minimum size) to match what this view was designed for.
- (NSSize)minSize
{
	return minSize;
}

- (NSSize)originalSize
{
	return originalViewBounds.size;
}

@end
