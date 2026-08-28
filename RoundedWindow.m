#import "RoundedWindow.h"

@implementation RoundedWindow

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

    if (self = [super initWithContentRect:contentRect
								styleMask:style
								  backing:NSBackingStoreBuffered
									defer:NO])
	{
		// Use this level to make it above all other applications
        [self setLevel: NSStatusWindowLevel];

		// Use this level to let the user put it in the background
		//[self setLevel: NSNormalWindowLevel];

		// The titlebar area is still real (drag, traffic lights), but drawn transparent
		// so the glass content shows through underneath it.
		[self setTitlebarAppearsTransparent:YES];
		[self setTitleVisibility:NSWindowTitleHidden];

        [self setBackgroundColor:[NSColor clearColor]];
        [self setAlphaValue:1.0];
        [self setOpaque:NO];
        [self setHasShadow:YES];
		[self setMinSize:NSMakeSize(220, 220)];

		// Listen for mouse movement
		// We need to forward these events to our custom view
		[self setAcceptsMouseMovedEvents:YES];
    }
    return self;
}

/**
 The nib installs our custom RoundedView as the window's content view (and wires it to the
 roundedView outlet). Here we re-parent it inside a glass background so the window gets a
 real Liquid Glass look instead of the old hand-drawn black translucent rectangle. Liquid
 Glass (NSGlassEffectView) only exists on macOS 26+ - on older systems we fall back to a
 plain vibrant blur with the same rounded corner, since the deployment target is lower than
 26.0 to keep the app running on those systems too.
**/
- (void)awakeFromNib
{
	if(roundedView && [self contentView] == roundedView)
	{
		NSView *content = roundedView;
		[content retain];
		[content setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

		NSView *glassView;
		if (@available(macOS 26.0, *))
		{
			NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:[content frame]];
			[glass setStyle:NSGlassEffectViewStyleRegular];
			[glass setCornerRadius:24.0];
			[glass setTintColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.35]];
			[glass setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
			[glass setContentView:content];
			glassView = glass;
		}
		else
		{
			NSVisualEffectView *blur = [[NSVisualEffectView alloc] initWithFrame:[content frame]];
			[blur setMaterial:NSVisualEffectMaterialHUDWindow];
			[blur setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
			[blur setState:NSVisualEffectStateActive];
			[blur setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
			[blur setWantsLayer:YES];
			[[blur layer] setCornerRadius:24.0];
			[[blur layer] setMasksToBounds:YES];
			[blur addSubview:content];
			glassView = blur;
		}

		[self setContentView:glassView];

		[glassView release];
		[content release];
	}
}

/**
 Don't forget to tidy up when we're done!
 We don't actually create any variables, but it's good practice to do this anyways.
**/
-(void) dealloc
{
	// NSLog(@"Destroying %@", self);
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
	[roundedView mouseMoved:theEvent];
}

@end
