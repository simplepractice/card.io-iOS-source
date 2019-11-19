//
//  CardIOMacros.h
//  See the file "LICENSE.md" for the full license governing this code.
//

// CardIOLog is a replacement for NSLog that logs iff CARDIO_DEBUG is set.

#if CARDIO_DEBUG
#define CardIOLog(format, args...) NSLog(format, ## args)
#else
#define CardIOLog(format, args...)
#endif

@interface CardIOMacros : NSObject

+ (id)localSettingForKey:(NSString *)key defaultValue:(NSString *)defaultValue productionValue:(NSString *)productionValue;

+ (NSUInteger)deviceSystemMajorVersion;

+ (BOOL)appHasViewControllerBasedStatusBar;

@end
