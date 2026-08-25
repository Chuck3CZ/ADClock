#import <Foundation/Foundation.h>

/**
 XPC protocol implemented by the wakehelper LaunchDaemon (WakeHelperMain.m) and called by the
 sandboxed app (ADClockTasks.m) to schedule/cancel a wake-from-sleep power event.
 IOPMSchedulePowerEvent/IOPMCancelScheduledPowerEvent require root, which a sandboxed app can
 no longer become itself (the old approach - chown/chmod a setuid helper via
 AuthorizationExecuteWithPrivileges - doesn't work inside the App Sandbox App Store
 distribution requires), so a privileged daemon installed via SMAppService does it instead.
**/
@protocol AlarmWakeHelperProtocol

- (void)scheduleWakeAtDate:(NSDate *)date reply:(void (^)(BOOL success))reply;
- (void)cancelWakeAtDate:(NSDate *)date reply:(void (^)(BOOL success))reply;

@end

#define kAlarmWakeHelperMachServiceName @"com.3czplay.adclock.wakehelper"
