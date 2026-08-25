#import <Foundation/Foundation.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <Security/Security.h>
#import "AlarmWakeHelperProtocol.h"

/**
 The privileged half of the wake-from-sleep feature. Runs as a root LaunchDaemon (installed
 on demand by the sandboxed app via SMAppService, see +[AlarmTasks authenticate] in
 AlarmTasks.m) so it can call IOPMSchedulePowerEvent/IOPMCancelScheduledPowerEvent, which
 require root and can't be called from inside the App Sandbox.
**/
@interface WakeHelperService : NSObject <AlarmWakeHelperProtocol, NSXPCListenerDelegate>
@end

@implementation WakeHelperService

/**
 Only accept connections from processes signed by the same team as this daemon - i.e. the
 AlarmClock app itself, not an arbitrary local process asking us to schedule wake events.
**/
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
	SecCodeRef code = NULL;
	NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid: @(newConnection.processIdentifier)};
	if(SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &code) != errSecSuccess)
		return NO;

	SecRequirementRef requirement = NULL;
	NSString *requirementString = @"anchor apple generic and certificate leaf[subject.OU] = \"LT2EBE5TBV\"";
	SecRequirementCreateWithString((__bridge CFStringRef)requirementString, kSecCSDefaultFlags, &requirement);

	OSStatus status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);

	if(code) CFRelease(code);
	if(requirement) CFRelease(requirement);

	if(status != errSecSuccess)
	{
		NSLog(@"Rejected XPC connection from unsigned/untrusted process (status %d)", (int)status);
		return NO;
	}

	newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AlarmWakeHelperProtocol)];
	newConnection.exportedObject = self;
	[newConnection resume];
	return YES;
}

- (void)scheduleWakeAtDate:(NSDate *)date reply:(void (^)(BOOL success))reply
{
	NSString *scheduler = @"AlarmClock";
	NSString *eventType = [NSString stringWithUTF8String:kIOPMAutoWakeOrPowerOn];
	IOReturn result = IOPMSchedulePowerEvent((__bridge CFDateRef)date, (__bridge CFStringRef)scheduler, (__bridge CFStringRef)eventType);
	reply(result == kIOReturnSuccess);
}

- (void)cancelWakeAtDate:(NSDate *)date reply:(void (^)(BOOL success))reply
{
	NSString *scheduler = @"AlarmClock";
	NSString *eventType = [NSString stringWithUTF8String:kIOPMAutoWakeOrPowerOn];
	IOReturn result = IOPMCancelScheduledPowerEvent((__bridge CFDateRef)date, (__bridge CFStringRef)scheduler, (__bridge CFStringRef)eventType);
	reply(result == kIOReturnSuccess);
}

@end

int main(int argc, const char *argv[])
{
	@autoreleasepool
	{
		WakeHelperService *service = [[WakeHelperService alloc] init];
		NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:kAlarmWakeHelperMachServiceName];
		listener.delegate = service;
		[listener resume];
		[[NSRunLoop currentRunLoop] run];
	}
	return 0;
}
