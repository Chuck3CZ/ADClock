#import <Foundation/Foundation.h>
@class Alarm;

@interface AlarmScheduler : NSObject

+ (void)initialize;
+ (void)deinitialize;

// Saving alarm info to user defaults
+ (void)savePrefs;

// Getting alarms
+ (Alarm *)alarmReferenceForIndex:(int)index;
+ (Alarm *)alarmCloneForIndex:(int)index;

// Changing alarms
+ (void)setAlarm:(Alarm *)clone forReference:(Alarm *)reference;
+ (void)addAlarm:(Alarm *)newAlarm;
+ (void)removeAlarm:(Alarm *)deletedAlarm;

// Updating alarms
+ (void)updateAllAlarms;

// Getting number of alarms
+ (NSUInteger)numberOfAlarms;

// Getting info about next and last alarm
+ (Alarm *)lastAlarmClone;
+ (NSDate *)nextAlarmDate;

// Querying for sounding alarms
+ (int)alarmStatus:(NSDate *)now;

@end
