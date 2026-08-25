/* TransparentView */

#import <Cocoa/Cocoa.h>

@interface TransparentView : NSView
{
	// Drawing attributes for buttons and clock
	NSDictionary *statusAttributes;
	NSDictionary *clockAttributes;
	NSDictionary *buttonAttributes;

	// Stored frames and locations (for dragging and resizing)
	// NSRect and NSPoint are simple structs
	NSSize minSize;
	NSRect originalViewBounds;
	NSRect initialWindowFrame;
	NSPoint initialLocationInWindow;
	NSPoint initialLocationInScreen;

	// Coordinates of frame, clock, buttons, etc (NSRect is a simple struct)
	NSRect viewRect;
	NSRect statusLine1Rect;
	NSRect statusLine2Rect;
	NSRect clockRect;
	NSRect bigClockRect;
	NSRect leftModifierRect;
	NSRect rightModifierRect;
	NSRect leftButtonRect;
	NSRect rightButtonRect;

	// Left modifier
	BOOL isRolloverMinus;
	BOOL isPressedMinus;
	BOOL wasPressedMinus;
	// Plus button
	BOOL isRolloverPlus;
	BOOL isPressedPlus;
	BOOL wasPressedPlus;
	// Left button
	BOOL isRolloverLeft;
	BOOL isPressedLeft;
	BOOL wasPressedLeft;
	// Right button
	BOOL isRolloverRight;
	BOOL isPressedRight;
	BOOL wasPressedRight;
	// Window
	BOOL isPressedWindow;

    IBOutlet id transparentController;
}

// Used by TransparentWindow to configure real system window resize behavior
// (content aspect ratio / minimum size) to match what this view was designed for.
- (NSSize)minSize;
- (NSSize)originalSize;

@end
