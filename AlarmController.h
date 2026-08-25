#import <Cocoa/Cocoa.h>
#import "ADClockController.h"

/**
 AlarmWindow.nib references its window controller by class name ("AlarmController") baked into
 its compiled keyedobjects.nib for every localization - a string we have no way to update
 without Interface Builder access. Since the nib loader resolves that name at runtime via the
 Objective-C class list, this empty subclass is enough to satisfy it: it inherits every ivar,
 outlet, and method from ADClockController (the actual, renamed implementation) unchanged.
**/
@interface AlarmController : ADClockController
@end
