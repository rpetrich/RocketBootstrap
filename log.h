#import <Foundation/Foundation.h>

// Tiny shim to convert NSLog to public os_log statements on iOS 10
#ifdef __clang__
#if __has_include(<os/log.h>)
#include <os/log.h>
#define NSLog(...) do { \
	if (kCFCoreFoundationVersionNumber > 1299.0) { \
		@autoreleasepool { \
			os_log(OS_LOG_DEFAULT, "%{public}@", [NSString stringWithFormat:__VA_ARGS__]); \
		} \
	} else { \
		NSLog(__VA_ARGS__); \
	} \
} while(0)
#endif
#endif
