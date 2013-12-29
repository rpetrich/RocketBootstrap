#import "rocketbootstrap.h"

#ifndef __APPLE_API_PRIVATE
#define __APPLE_API_PRIVATE
#include "sandbox.h"
#undef __APPLE_API_PRIVATE
#else
#include "sandbox.h"
#endif

#import <mach/mach.h>
#import <substrate.h>
#import <libkern/OSAtomic.h>
#import <CaptainHook/CaptainHook.h>

static inline bool rocketbootstrap_is_passthrough(void)
{
	return kCFCoreFoundationVersionNumber < 800.0;
}

#define ROCKETBOOTSTRAP_LOOKUP_ID -1

typedef struct {
	mach_msg_header_t head;
	mach_msg_body_t body;
	uint32_t name_length;
	char name[];
} _rocketbootstrap_lookup_query_t;

typedef struct {
	mach_msg_header_t head;
	mach_msg_body_t body;
	mach_msg_port_descriptor_t response_port;
} _rocketbootstrap_lookup_response_t;

static NSMutableSet *allowedNames;
static volatile OSSpinLock namesLock;

kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp)
{
	if (rocketbootstrap_is_passthrough() || allowedNames) {
		if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_5_0) {
			int sandbox_result = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_LOCAL_NAME | SANDBOX_CHECK_NO_REPORT, service_name);
			if (sandbox_result) {
				return sandbox_result;
			}
		}
		return bootstrap_look_up(bp, service_name, sp);
	}
	mach_port_t servicesPort = MACH_PORT_NULL;
	kern_return_t err = bootstrap_look_up(bp, "com.apple.SBUserNotification", &servicesPort);
	if (err)
		return err;
	mach_port_t selfTask = mach_task_self();
	// Create a reply port
	mach_port_name_t replyPort = MACH_PORT_NULL;
	err = mach_port_allocate(selfTask, MACH_PORT_RIGHT_RECEIVE, &replyPort);
	if (err) {
		mach_port_deallocate(selfTask, servicesPort);
		return err;
	}
	// Send message
	size_t service_name_size = strlen(service_name);
	size_t size = (sizeof(_rocketbootstrap_lookup_query_t) + service_name_size + 3) & ~3;
	if (size < sizeof(_rocketbootstrap_lookup_response_t)) {
		size = sizeof(_rocketbootstrap_lookup_response_t);
	}
	char buffer[size];
	_rocketbootstrap_lookup_query_t *message = (_rocketbootstrap_lookup_query_t *)&buffer[0];
	memset(message, 0, sizeof(_rocketbootstrap_lookup_response_t));
	message->head.msgh_id = ROCKETBOOTSTRAP_LOOKUP_ID;
	message->head.msgh_size = size;
	message->head.msgh_remote_port = servicesPort;
	message->head.msgh_local_port = replyPort;
	message->head.msgh_reserved = 0;
	message->head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
	message->name_length = service_name_size;
	memcpy(&message->name[0], service_name, service_name_size);
	err = mach_msg(&message->head, MACH_SEND_MSG | MACH_RCV_MSG, size, size, replyPort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	// Parse response
	if (!err) {
		_rocketbootstrap_lookup_response_t *response = (_rocketbootstrap_lookup_response_t *)message;
		if (response->body.msgh_descriptor_count)
			*sp = response->response_port.name;
		else
			err = 1;
	}
	// Cleanup
	mach_port_deallocate(selfTask, servicesPort);
	mach_port_deallocate(selfTask, replyPort);
	return err;
}

// SpringBoard

kern_return_t rocketbootstrap_unlock(const name_t service_name)
{
	if (allowedNames) {
		NSString *string = [[NSString alloc] initWithUTF8String:service_name];
		OSSpinLockLock(&namesLock);
		[allowedNames addObject:string];
		OSSpinLockUnlock(&namesLock);
		[string release];
		return 0;
	}
	return 1;
}

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
kern_return_t rocketbootstrap_register(mach_port_t bp, name_t service_name, mach_port_t sp)
{
	kern_return_t err = rocketbootstrap_unlock(service_name);
	if (err)
		return err;
	return bootstrap_register(bp, service_name, sp);
}
#pragma GCC diagnostic warning "-Wdeprecated-declarations"

static CFMachPortCallBack originalCallout;

static void machPortCallback(CFMachPortRef port, void *bytes, CFIndex size, void *info)
{
	mach_msg_header_t *head = bytes;
	mach_msg_id_t msg_id = head->msgh_id;
	// Lookup
	if (msg_id == ROCKETBOOTSTRAP_LOOKUP_ID) {
		_rocketbootstrap_lookup_query_t *lookup_message = bytes;
		// Extract service name
		size_t length = size - offsetof(_rocketbootstrap_lookup_query_t, name);
		if (lookup_message->name_length <= length) {
			length = lookup_message->name_length;
		}
		NSString *name = [[NSString alloc] initWithBytes:&lookup_message->name[0] length:length encoding:NSUTF8StringEncoding];
		// Lookup service
		mach_port_t servicePort = MACH_PORT_NULL;
		mach_port_t selfTask = mach_task_self();
		OSSpinLockLock(&namesLock);
		BOOL nameIsAllowed = [allowedNames containsObject:name];
		OSSpinLockUnlock(&namesLock);
		kern_return_t err;
		if (nameIsAllowed) {
			mach_port_t bootstrap = MACH_PORT_NULL;
			err = task_get_bootstrap_port(selfTask, &bootstrap);
			if (!err) {
				bootstrap_look_up(bootstrap, [name UTF8String], &servicePort);
			}
		}
		[name release];
		// Generate response
		_rocketbootstrap_lookup_response_t response;
		response.head.msgh_id = 0;
		response.head.msgh_size = (sizeof(_rocketbootstrap_lookup_response_t) + 3) & ~3;
		response.head.msgh_remote_port = head->msgh_remote_port;
		response.head.msgh_local_port = MACH_PORT_NULL;
		response.head.msgh_reserved = 0;
		response.head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
		if (servicePort != MACH_PORT_NULL) {
			response.head.msgh_bits |= MACH_MSGH_BITS_COMPLEX;
			response.body.msgh_descriptor_count = 1;
			response.response_port.name = servicePort;
			response.response_port.disposition = MACH_MSG_TYPE_COPY_SEND;
			response.response_port.type = MACH_MSG_PORT_DESCRIPTOR;
		} else {
			response.body.msgh_descriptor_count = 0;
		}
		// Send response
		err = mach_msg(&response.head, MACH_SEND_MSG, response.head.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
		if (err) {
			if (servicePort != MACH_PORT_NULL)
				mach_port_mod_refs(selfTask, servicePort, MACH_PORT_RIGHT_SEND, -1);
			mach_port_mod_refs(selfTask, head->msgh_remote_port, MACH_PORT_RIGHT_SEND_ONCE, -1);
		}
	} else {
		originalCallout(port, bytes, size, info);
	}
}

static CFMachPortRef (*_CFMachPortCreateWithPort) (
   CFAllocatorRef allocator,
   mach_port_t portNum,
   CFMachPortCallBack callout,
   CFMachPortContext *context,
   Boolean *shouldFreeInfo
);

static volatile NSInteger replacing;
static volatile CFRunLoopRef targetRunLoop;

static CFMachPortRef $CFMachPortCreateWithPort (
   CFAllocatorRef allocator,
   mach_port_t portNum,
   CFMachPortCallBack callout,
   CFMachPortContext *context,
   Boolean *shouldFreeInfo
) {
	if (replacing && targetRunLoop == CFRunLoopGetCurrent()) {
		targetRunLoop = NULL;
		originalCallout = callout;
		callout = machPortCallback;
	}
	return _CFMachPortCreateWithPort(allocator, portNum, callout, context, shouldFreeInfo);
}

%hook SBUserNotificationCenter

+ (void)startUserNotificationCenter
{
	targetRunLoop = CFRunLoopGetCurrent();
	replacing++;
	%orig();
	replacing--;
	targetRunLoop = NULL;
}

%end

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
	NSLog(@"rocketbootstrap_distributedmessagingcenter_apply(%@)", messaging_center);
	if (rocketbootstrap_is_passthrough())
		return;
	if (!has_hooked_messaging_center) {
		has_hooked_messaging_center = true;
		%init(messaging_center);
	}
	objc_setAssociatedObject(messaging_center, &has_hooked_messaging_center, (id)kCFBooleanTrue, OBJC_ASSOCIATION_ASSIGN);
}

%ctor
{
	%init();
	if (%c(SBUserNotificationCenter)) {
		allowedNames = [[NSMutableSet alloc] init];
		MSHookFunction(CFMachPortCreateWithPort, $CFMachPortCreateWithPort, (void **)&_CFMachPortCreateWithPort);
	}
}
