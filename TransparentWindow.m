#import "TransparentWindow.h"
#import "TransparentView.h"

@implementation TransparentWindow

/**
 We override the standard init method to return a real system window (titled, closable,
 miniaturizable, resizable) with a transparent titlebar. The Liquid Glass content view
 (installed in -awakeFromNib) draws behind the traffic lights, so the window looks like a
 single floating glass card while still behaving like a normal, native macOS window.
**/
- (id)initWithContentRect:(NSRect)contentRect
				styleMask:(NSWindowStyleMask)aStyle
				  backing:(NSBackingStoreType)bufferingType
					defer:(BOOL)flag
{
	NSWindowStyleMask style = NSWindowStyleMaskTitled
							 | NSWindowStyleMaskClosable
							 | NSWindowStyleMaskMiniaturizable
							 | NSWindowStyleMaskResizable
							 | NSWindowStyleMaskFullSizeContentView;

	if(self = [super initWithContentRect:contentRect styleMask:style backing:bufferingType defer:flag])
	{
		// Use this level to make it above all other applications
        //[self setLevel: NSStatusWindowLevel];

		// Use this level to let the user put it in the background
		[self setLevel: NSNormalWindowLevel];

		// The titlebar area is still real (drag, traffic lights, real title text), but
		// drawn transparent so the glass content shows through underneath it.
		[self setTitlebarAppearsTransparent:YES];

		[self setBackgroundColor:[NSColor clearColor]];
		[self setAlphaValue:1.0];
		[self setOpaque:NO];
		[self setHasShadow:YES];

		// Listen for mouse movement
		// We need to forward these events to our custom view
		[self setAcceptsMouseMovedEvents:YES];
    }
    return self;
}

/**
 The nib installs our custom TransparentView as the window's content view (and wires it to
 the transparentView outlet). Here we re-parent it inside an NSGlassEffectView so the window
 gets a real Liquid Glass background instead of the old hand-drawn title bar/content fill.
 We also ask the system to preserve this window's original aspect ratio and minimum size
 during real (user-driven) resizing, replacing the view's old manual resize-corner math.
**/
- (void)awakeFromNib
{
	if(transparentView && ![[self contentView] isKindOfClass:[NSGlassEffectView class]])
	{
		NSView *content = transparentView;
		[content retain];

		NSGlassEffectView *glassView = [[NSGlassEffectView alloc] initWithFrame:[content frame]];
		[glassView setStyle:NSGlassEffectViewStyleRegular];
		[glassView setCornerRadius:20.0];
		[glassView setTintColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.35]];
		[glassView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

		[content setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[glassView setContentView:content];

		[self setContentView:glassView];

		[glassView release];

		NSSize originalSize = [(TransparentView *)content originalSize];
		if(originalSize.width > 0 && originalSize.height > 0)
		{
			[self setContentAspectRatio:originalSize];
		}
		[self setContentMinSize:[(TransparentView *)content minSize]];

		[content release];
	}
}

/**
 Don't forget to tidy up when we're done!
 We don't actually create any variables, but it's good practice to do this anyways.
**/
- (void)dealloc
{
	//NSLog(@"Destroying %@", self);
	[super dealloc];
}

/**
 We want to be able to become the key window, so we override this method to enforce this.
 The default implementation returns YES if the window has a title bar or resize control.
 The transparentView implements a title bar and resize control, so this is still standard OS X policy.
**/
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

/**
 We want to listen to mouse movement events.
 However, we don't actually have anything to do with them.
 Our transparentView needs them, so we forward them to the timerView.
**/
- (void)mouseMoved:(NSEvent *)theEvent
{
	[transparentView mouseMoved:theEvent];
}

@end
