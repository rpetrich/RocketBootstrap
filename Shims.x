#import "log.h"
#import "unfair_lock.h"
#import "rocketbootstrap_internal.h"

#import <CaptainHook/CaptainHook.h>
#import <libkern/OSAtomic.h>
#import <substrate.h>

static unfair_lock shim_lock;

kern_return_t bootstrap_look_up3(mach_port_t bp, const name_t service_name, mach_port_t *sp, pid_t target_pid, const uuid_t instance_id, uint64_t flags) __attribute__((weak_import));
static kern_return_t (*_bootstrap_look_up3)(mach_port_t bp, const name_t service_name, mach_port_t *sp, pid_t target_pid, const uuid_t instance_id, uint64_t flags);

static kern_return_t $bootstrap_look_up3(mach_port_t bp, const name_t service_name, mach_port_t *sp, pid_t target_pid, const uuid_t instance_id, uint64_t flags)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableDictionary *threadDictionary = [NSThread currentThread].threadDictionary;
	id obj = [threadDictionary objectForKey:@"rocketbootstrap_intercept_next_lookup"];
	if (obj) {
		[threadDictionary removeObjectForKey:@"rocketbootstrap_intercept_next_lookup"];
		[pool drain];
		return rocketbootstrap_look_up(bp, service_name, sp);
	}
	[pool drain];
	return _bootstrap_look_up3(bp, service_name, sp, target_pid, instance_id, flags);
}

static void hook_bootstrap_lookup(void)
{
	static bool hooked_bootstrap_look_up;
	unfair_lock_lock(&shim_lock);
	if (!hooked_bootstrap_look_up) {
		MSHookFunction(bootstrap_look_up3, $bootstrap_look_up3, (void **)&_bootstrap_look_up3);
		hooked_bootstrap_look_up = true;
	}
	unfair_lock_unlock(&shim_lock);
}

CFMessagePortRef rocketbootstrap_cfmessageportcreateremote(CFAllocatorRef allocator, CFStringRef name)
{
	if (rocketbootstrap_is_passthrough())
		return CFMessagePortCreateRemote(allocator, name);
	hook_bootstrap_lookup();
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableDictionary *threadDictionary = [NSThread currentThread].threadDictionary;
	[threadDictionary setObject:(id)kCFBooleanTrue forKey:@"rocketbootstrap_intercept_next_lookup"];
	CFMessagePortRef result = CFMessagePortCreateRemote(allocator, name);
	[threadDictionary removeObjectForKey:@"rocketbootstrap_intercept_next_lookup"];
	[pool drain];
	return result;
}

kern_return_t rocketbootstrap_cfmessageportexposelocal(CFMessagePortRef messagePort)
{
	if (rocketbootstrap_is_passthrough())
		return 0;
	CFStringRef name = CFMessagePortGetName(messagePort);
	if (!name)
		return -1;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	kern_return_t result = rocketbootstrap_unlock([(NSString *)name UTF8String]);
	[pool drain];
	return result;
}

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
		if (_sendPort && _lock) {
			[*_lock lock];
			mach_port_t result = *_sendPort;
			if (result == MACH_PORT_NULL) {
				NSString **_centerName = CHIvarRef(self, _centerName, NSString *);
				if (_centerName && *_centerName && [self respondsToSelector:@selector(_setupInvalidationSource)]) {
					mach_port_t bootstrap = MACH_PORT_NULL;
					task_get_bootstrap_port(mach_task_self(), &bootstrap);
					rocketbootstrap_look_up(bootstrap, [*_centerName UTF8String], _sendPort);
					[self _setupInvalidationSource];
					result = *_sendPort;
				}
			}
			[*_lock unlock];
			return result;
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
	unfair_lock_lock(&shim_lock);
	if (!has_hooked_messaging_center) {
		has_hooked_messaging_center = true;
		%init(messaging_center);
	}
	unfair_lock_unlock(&shim_lock);
	objc_setAssociatedObject(messaging_center, &has_hooked_messaging_center, (id)kCFBooleanTrue, OBJC_ASSOCIATION_ASSIGN);
}

#ifdef __clang__

#ifndef __IPHONE_9_0
#define __IPHONE_9_0 90000
#define __AVAILABILITY_INTERNAL__IPHONE_9_0
#endif

#include <xpc/xpc.h>

static xpc_endpoint_t _xpc_endpoint_create(mach_port_t port)
{
	static xpc_endpoint_t(*__xpc_endpoint_create)(mach_port_t);
	if (!__xpc_endpoint_create) {
		MSImageRef libxpc = MSGetImageByName("/usr/lib/system/libxpc.dylib");
		if (!libxpc) {
			return NULL;
		}
		__xpc_endpoint_create = MSFindSymbol(libxpc, "__xpc_endpoint_create");
		if (!__xpc_endpoint_create) {
			return NULL;
		}
	}
	return __xpc_endpoint_create(port);
}

static mach_port_t _xpc_connection_copy_listener_port(xpc_connection_t connection)
{
	static mach_port_t(*__xpc_connection_copy_listener_port)(xpc_connection_t);
	if (!__xpc_connection_copy_listener_port) {
		MSImageRef libxpc = MSGetImageByName("/usr/lib/system/libxpc.dylib");
		if (!libxpc) {
			return MACH_PORT_NULL;
		}
		__xpc_connection_copy_listener_port = MSFindSymbol(libxpc, "__xpc_connection_copy_listener_port");
		if (!__xpc_connection_copy_listener_port) {
			return MACH_PORT_NULL;
		}
	}
	return __xpc_connection_copy_listener_port(connection);
}

xpc_object_t xpc_connection_copy_entitlement_value(xpc_connection_t, const char* entitlement);

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
xpc_connection_t rocketbootstrap_xpc_connection_create(const char *name, dispatch_queue_t targetq, uint64_t flags)
{
	mach_port_t bootstrap = MACH_PORT_NULL;
	if (task_get_bootstrap_port(mach_task_self(), &bootstrap) != 0) {
		return NULL;
	}
	if (flags & XPC_CONNECTION_MACH_SERVICE_LISTENER) {
		if (rocketbootstrap_unlock(name) != 0) {
			return NULL;
		}
		xpc_connection_t result = xpc_connection_create(NULL, targetq);
		mach_port_t port = _xpc_connection_copy_listener_port(result);
		if (bootstrap_register(bootstrap, (char *)name, port) != 0) {
			xpc_release(result);
			return NULL;
		}
		return result;
	}
	mach_port_t send_port = MACH_PORT_NULL;
	if (rocketbootstrap_look_up(bootstrap, name, &send_port) != 0) {
		return NULL;
	}
	xpc_endpoint_t endpoint = _xpc_endpoint_create(send_port);
	xpc_connection_t result = xpc_connection_create_from_endpoint(endpoint);
	xpc_release(endpoint);
	if (targetq != NULL) {
		xpc_connection_set_target_queue(result, targetq);
	}
	return result;
}

xpc_object_t rocketbootstrap_xpc_connection_copy_application_identifier(xpc_connection_t connection)
{
	xpc_object_t application_id = xpc_connection_copy_entitlement_value(connection, "application-identifier");
	if (!application_id) {
		return NULL;
	}
	if (xpc_get_type(application_id) != XPC_TYPE_STRING) {
		xpc_release(application_id);
		return NULL;
	}
	xpc_object_t team_id = xpc_connection_copy_entitlement_value(connection, "com.apple.developer.team-identifier");
	if (!team_id) {
		return application_id;
	}
	if (xpc_get_type(team_id) != XPC_TYPE_STRING) {
		xpc_release(team_id);
		return application_id;
	}
	const char *application_id_str = xpc_string_get_string_ptr(application_id);
	const char *team_id_str = xpc_string_get_string_ptr(team_id);
	size_t team_id_length = xpc_string_get_length(team_id);
	if (memcmp(application_id_str, team_id_str, team_id_length) != 0 || application_id_str[team_id_length] != '.') {
		xpc_release(team_id);
		return application_id;
	}
	xpc_object_t trimmed_id = xpc_string_create(application_id_str + team_id_length + 1);
	xpc_release(team_id);
	xpc_release(application_id);
	return trimmed_id;
}

#endif
