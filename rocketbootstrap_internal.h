#import <CoreFoundation/CoreFoundation.h>

#import "rocketbootstrap.h"

static inline bool rocketbootstrap_is_passthrough(void)
{
	return kCFCoreFoundationVersionNumber < 800.0;
}

