#import "rocketbootstrap_internal.h"

#import <CaptainHook/CaptainHook.h>

@interface CPDistributedMessagingCenter : NSObject
- (void)_setupInvalidationSource;
@end

%group messaging_center

static bool has_hooked_messaging_center;

%hook CPDistributedMessagingCenter

- (mach_port_t)_sendPort
{
	if (objc_getAssociatedObject(self, &has_hooked_messaging_center)) {
		mach_port_t *_sendPort = CHIvarRef(self, _sendPort, mach_port_t);
		NSLock **_lock = CHIvarRef(self, _lock, NSLock *);
		NSString **_centerName = CHIvarRef(self, _centerName, NSString *);
		if (_sendPort && _lock && _centerName && *_centerName && [self respondsToSelector:@selector(_setupInvalidationSource)]) {
			[*_lock lock];
			mach_port_t bootstrap = MACH_PORT_NULL;
			task_get_bootstrap_port(mach_task_self(), &bootstrap);
			rocketbootstrap_look_up(bootstrap, [*_centerName UTF8String], _sendPort);
			[self _setupInvalidationSource];
			[*_lock unlock];
			return *_sendPort;
		}
	}
	return %orig();
}

- (void)runServerOnCurrentThreadProtectedByEntitlement:(id)entitlement
{
	if (objc_getAssociatedObject(self, &has_hooked_messaging_center)) {
		NSString **_centerName = CHIvarRef(self, _centerName, NSString *);
		if (_centerName && *_centerName) {
			rocketbootstrap_unlock([*_centerName UTF8String]);
		}
	}
	%orig();
}

%end

%end

void rocketbootstrap_distributedmessagingcenter_apply(CPDistributedMessagingCenter *messaging_center)
{
	if (rocketbootstrap_is_passthrough())
		return;
	if (!has_hooked_messaging_center) {
		has_hooked_messaging_center = true;
		%init(messaging_center);
	}
	objc_setAssociatedObject(messaging_center, &has_hooked_messaging_center, (id)kCFBooleanTrue, OBJC_ASSOCIATION_ASSIGN);
}
