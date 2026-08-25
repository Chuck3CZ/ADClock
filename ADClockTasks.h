#import <Cocoa/Cocoa.h>


@interface ADClockTasks : NSObject

+ (void)initialize;
+ (void)deinitialize;

+ (void)prepareForSleep;
+ (void)wakeFromSleep;

+ (BOOL)isAuthenticated;
+ (BOOL)authenticate;
+ (BOOL)deauthenticate;

@end
