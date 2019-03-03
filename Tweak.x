#include <Availability.h>
#undef __IOS_PROHIBITED
#define __IOS_PROHIBITED

#include <spawn.h>

#define LIGHTMESSAGING_USE_ROCKETBOOTSTRAP 0
#define LIGHTMESSAGING_TIMEOUT 300
#import "LightMessaging/LightMessaging.h"
#import "log.h"
#import "unfair_lock.h"

#import "rocketbootstrap_internal.h"

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
//#import <launch.h>
#import <CoreFoundation/CFUserNotification.h>
#import <libkern/OSCacheControl.h>
#import <sys/sysctl.h>
#import <dispatch/dispatch.h>
#define __DISPATCH_INDIRECT__
#define DISPATCH_MACH_SPI 1
#import <dispatch/mach_private.h>

extern int *_NSGetArgc(void);
extern const char ***_NSGetArgv(void);

#define kUserAppsPath "/var/mobile/Applications/"
#define kSystemAppsPath "/Applications/"

static BOOL isDaemon;

static kern_return_t rocketbootstrap_look_up_with_timeout(mach_port_t bp, const name_t service_name, mach_port_t *sp, mach_msg_timeout_t timeout)
{
#ifdef DEBUG
	NSLog(@"RocketBootstrap: rocketbootstrap_look_up(%llu, %s, %p)", (unsigned long long)bp, service_name, sp);
#endif
	if (rocketbootstrap_is_passthrough() || isDaemon) {
		if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_5_0) {
			int sandbox_result = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_LOCAL_NAME | SANDBOX_CHECK_NO_REPORT, service_name);
			if (sandbox_result) {
				return sandbox_result;
			}
		}
		return bootstrap_look_up(bp, service_name, sp);
	}
	// Compatibility mode for Flex, limits it to only the processes in rbs 1.0.1 and earlier
	if (strcmp(service_name, "FLMessagingCenterSpringboard") == 0) {
		const char **argv = *_NSGetArgv();
		size_t arg0len = strlen(argv[0]);
		bool allowed = false;
		if ((arg0len > sizeof(kUserAppsPath)) && (memcmp(argv[0], kUserAppsPath, sizeof(kUserAppsPath) - 1) == 0))
			allowed = true;
		if ((arg0len > sizeof(kSystemAppsPath)) && (memcmp(argv[0], kSystemAppsPath, sizeof(kSystemAppsPath) - 1) == 0))
			allowed = true;
		if (!allowed)
			return 1;
	}
	// Ask our service running inside of the com.apple.ReportCrash.SimulateCrash job
	mach_port_t servicesPort = MACH_PORT_NULL;
	kern_return_t err = bootstrap_look_up(bp, "com.apple.ReportCrash.SimulateCrash", &servicesPort);
	if (err) {
#ifdef DEBUG
		NSLog(@"RocketBootstrap: = %lld (failed to lookup com.apple.ReportCrash.SimulateCrash)", (unsigned long long)err);
#endif
		return err;
	}
	mach_port_t selfTask = mach_task_self();
	// Create a reply port
	mach_port_name_t replyPort = MACH_PORT_NULL;
	err = mach_port_allocate(selfTask, MACH_PORT_RIGHT_RECEIVE, &replyPort);
	if (err) {
#ifdef DEBUG
		NSLog(@"RocketBootstrap: = %lld (failed to allocate port)", (unsigned long long)err);
#endif
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
	mach_msg_option_t options = MACH_SEND_MSG | MACH_RCV_MSG;
	if (timeout == 0) {
		timeout = MACH_MSG_TIMEOUT_NONE;
	} else {
		options |= MACH_SEND_TIMEOUT | MACH_RCV_TIMEOUT;
	}
	err = mach_msg(&message->head, options, size, size, replyPort, timeout, MACH_PORT_NULL);
	// Parse response
	if (!err) {
		_rocketbootstrap_lookup_response_t *response = (_rocketbootstrap_lookup_response_t *)message;
		if (response->body.msgh_descriptor_count) {
			*sp = response->response_port.name;
#ifdef DEBUG
			NSLog(@"RocketBootstrap: = 0 (success)");
#endif
		} else {
			err = 1;
#ifdef DEBUG
			NSLog(@"RocketBootstrap: = 1 (disallowed)");
#endif
		}
	}
	// Cleanup
	mach_port_deallocate(selfTask, servicesPort);
	mach_port_deallocate(selfTask, replyPort);
	return err;
}

kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp)
{
	return rocketbootstrap_look_up_with_timeout(bp, service_name, sp, LIGHTMESSAGING_TIMEOUT);
}

static NSMutableSet *allowedNames;
static unfair_lock namesLock;

static void daemon_restarted_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	unfair_lock_lock(&namesLock);
	NSSet *allNames = [allowedNames copy];
	unfair_lock_unlock(&namesLock);
	for (NSString *name in allNames) {
		const char *service_name = [name UTF8String];
		LMConnectionSendOneWay(&connection, 0, service_name, strlen(service_name));             
	}
	[allNames release];
	[pool drain];
}

kern_return_t rocketbootstrap_unlock(const name_t service_name)
{
#ifdef DEBUG
	NSLog(@"RocketBootstrap: rocketbootstrap_unlock(%s)", service_name);
#endif
	if (rocketbootstrap_is_passthrough())
		return 0;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *serviceNameString = [NSString stringWithUTF8String:service_name];
	unfair_lock_lock(&namesLock);
	BOOL containedName;
	if (!allowedNames) {
		allowedNames = [[NSMutableSet alloc] init];
		[allowedNames addObject:serviceNameString];
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), &daemon_restarted_callback, daemon_restarted_callback, CFSTR("com.rpetrich.rocketd.started"), NULL, CFNotificationSuspensionBehaviorCoalesce);
		containedName = NO;
	} else {
		containedName = [allowedNames containsObject:serviceNameString];
		if (!containedName) {
			[allowedNames addObject:serviceNameString];
		}
	}
	unfair_lock_unlock(&namesLock);
	[pool drain];
	if (containedName) {
		return 0;
	}
	// Ask rocketd to unlock it for us
	int sandbox_result = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_LOCAL_NAME | SANDBOX_CHECK_NO_REPORT, kRocketBootstrapUnlockService);
	if (sandbox_result) {
		return sandbox_result;
	}
	return LMConnectionSendOneWay(&connection, 0, service_name, strlen(service_name));
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

static kern_return_t handle_bootstrap_lookup_msg(mach_msg_header_t *request)
{
	_rocketbootstrap_lookup_query_t *lookup_message = (_rocketbootstrap_lookup_query_t *)request;
	// Extract service name
	size_t length = request->msgh_size - offsetof(_rocketbootstrap_lookup_query_t, name);
	if (lookup_message->name_length <= length) {
		length = lookup_message->name_length;
	}
#ifdef DEBUG
	NSLog(@"RocketBootstrap: handle_bootstrap_lookup_msg(%.*s)", (int)length, &lookup_message->name[0]);
#endif
	// Ask rocketd if it's unlocked
	LMResponseBuffer buffer;
	if (LMConnectionSendTwoWay(&connection, 1, &lookup_message->name[0], length, &buffer))
		return 1;
	BOOL nameIsAllowed = LMResponseConsumeInteger(&buffer) != 0;
	// Lookup service port
	mach_port_t servicePort = MACH_PORT_NULL;
	mach_port_t selfTask = mach_task_self();
	kern_return_t err;
	if (nameIsAllowed) {
		mach_port_t bootstrap = MACH_PORT_NULL;
		err = task_get_bootstrap_port(selfTask, &bootstrap);
		if (!err) {
			char *buffer = malloc(length + 1);
			if (buffer) {
				memcpy(buffer, lookup_message->name, length);
				buffer[length] = '\0';
				err = bootstrap_look_up(bootstrap, buffer, &servicePort);
				free(buffer);
			}
		}
	}
	// Generate response
	_rocketbootstrap_lookup_response_t response;
	response.head.msgh_id = 0;
	response.head.msgh_size = (sizeof(_rocketbootstrap_lookup_response_t) + 3) & ~3;
	response.head.msgh_remote_port = request->msgh_remote_port;
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
		if (servicePort != MACH_PORT_NULL) {
			mach_port_mod_refs(selfTask, servicePort, MACH_PORT_RIGHT_SEND, -1);
		}
	}
	return err;
}

mach_msg_return_t mach_msg_server_once(boolean_t (*demux)(mach_msg_header_t *, mach_msg_header_t *), mach_msg_size_t max_size, mach_port_t rcv_name, mach_msg_options_t options);

static mach_msg_return_t (*_mach_msg_server_once)(boolean_t (*demux)(mach_msg_header_t *, mach_msg_header_t *), mach_msg_size_t max_size, mach_port_t rcv_name, mach_msg_options_t options);

static unfair_lock server_once_lock;
static boolean_t (*server_once_demux_orig)(mach_msg_header_t *, mach_msg_header_t *);
static bool continue_server_once;

static boolean_t new_demux(mach_msg_header_t *request, mach_msg_header_t *reply)
{
#ifdef DEBUG
	NSLog(@"RocketBootstrap: new_demux(%lld)", (long long)request->msgh_id);
#endif
	// Highjack ROCKETBOOTSTRAP_LOOKUP_ID from the com.apple.ReportCrash.SimulateCrash demuxer
	if (request->msgh_id == ROCKETBOOTSTRAP_LOOKUP_ID) {
		continue_server_once = true;
		kern_return_t err = handle_bootstrap_lookup_msg(request);
		if (err) {
			mach_port_mod_refs(mach_task_self(), reply->msgh_remote_port, MACH_PORT_RIGHT_SEND_ONCE, -1);
		}
		return true;
	}
	return server_once_demux_orig(request, reply);
}

static mach_msg_return_t $mach_msg_server_once(boolean_t (*demux)(mach_msg_header_t *, mach_msg_header_t *), mach_msg_size_t max_size, mach_port_t rcv_name, mach_msg_options_t options)
{
#ifdef DEBUG
	NSLog(@"RocketBootstrap: mach_msg_server_once(%p, %llu, %llu, 0x%llx)", demux, (unsigned long long)max_size, (unsigned long long)rcv_name, (long long)options);
#endif
	// Highjack com.apple.ReportCrash.SimulateCrash's use of mach_msg_server_once
	unfair_lock_lock(&server_once_lock);
	if (!server_once_demux_orig) {
		server_once_demux_orig = demux;
		demux = new_demux;
	} else if (server_once_demux_orig == demux) {
		demux = new_demux;
	} else {
		unfair_lock_unlock(&server_once_lock);
		mach_msg_return_t result = _mach_msg_server_once(demux, max_size, rcv_name, options);
		return result;
	}
	unfair_lock_unlock(&server_once_lock);
	mach_msg_return_t result;
	do {
		continue_server_once = false;
		result = _mach_msg_server_once(demux, max_size, rcv_name, options);
	} while (continue_server_once);
	return result;
}

#ifdef __clang__

static void *interceptedConnection;

static void *(*_xpc_connection_create_mach_service)(const char *name, dispatch_queue_t targetq, uint64_t flags);
static void *$xpc_connection_create_mach_service(const char *name, dispatch_queue_t targetq, uint64_t flags)
{
#ifdef DEBUG
	NSLog(@"RocketBootstrap: xpc_connection_create_mach_service(%s, %p, %lld)", name, targetq, (unsigned long long)flags);
#endif
	if (name && strcmp(name, "com.apple.ReportCrash.SimulateCrash") == 0) {
		void *result = _xpc_connection_create_mach_service(name, targetq, flags);
		interceptedConnection = result;
		return result;
	}
	return _xpc_connection_create_mach_service(name, targetq, flags);
}

static void (*__xpc_connection_mach_event)(void *context, dispatch_mach_reason_t reason, dispatch_mach_msg_t message, mach_error_t error);
static void $_xpc_connection_mach_event(void *context, dispatch_mach_reason_t reason, dispatch_mach_msg_t message, mach_error_t error)
{
#ifdef DEBUG
	NSLog(@"RocketBootstrap: _xpc_connection_mach_event(%p, %lu, %p, 0x%x)", context, reason, message, error);
#endif
	// Highjack ROCKETBOOTSTRAP_LOOKUP_ID from the com.apple.ReportCrash.SimulateCrash XPC service
	if ((reason == DISPATCH_MACH_MESSAGE_RECEIVED) && (context == interceptedConnection)) {
		size_t size;
		mach_msg_header_t *header = dispatch_mach_msg_get_msg(message, &size);
		if (header->msgh_id == ROCKETBOOTSTRAP_LOOKUP_ID) {
			handle_bootstrap_lookup_msg(header);
			return;
		}
	}
	return __xpc_connection_mach_event(context, reason, message, error);
}

#endif

static pid_t pid_of_process(const char *process_name)
{
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
	size_t miblen = 4;

	size_t size;
	int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
	
	struct kinfo_proc * process = NULL;
	struct kinfo_proc * newprocess = NULL;

	do {
		size += size / 10;
		newprocess = (struct kinfo_proc *)realloc(process, size);
		
		if (!newprocess) {
			if (process) {
				free(process);
			}
			return 0;
		}
		
		process = newprocess;
		st = sysctl(mib, miblen, process, &size, NULL, 0);
		
	} while (st == -1 && errno == ENOMEM);
	
	if (st == 0) {
		if (size % sizeof(struct kinfo_proc) == 0) {
			int nprocess = size / sizeof(struct kinfo_proc);
			if (nprocess) {
				for (int i = nprocess - 1; i >= 0; i--) {
					if (strcmp(process[i].kp_proc.p_comm, process_name) == 0) {
						pid_t result = process[i].kp_proc.p_pid;
						free(process);
						return result;
					}
				}
			}
		}
	}

	free(process);
	return 0;
}

static int daemon_die_queue;
static CFFileDescriptorRef daemon_die_fd;
static CFRunLoopSourceRef daemon_die_source;

static void process_terminate_callback(CFFileDescriptorRef fd, CFOptionFlags callBackTypes, void *info);

static void observe_rocketd(void)
{
	// Force the daemon to load
	mach_port_t bootstrap = MACH_PORT_NULL;
	mach_port_t self = mach_task_self();
	task_get_bootstrap_port(self, &bootstrap);
	mach_port_t servicesPort = MACH_PORT_NULL;
	kern_return_t err = bootstrap_look_up(bootstrap, "com.rpetrich.rocketbootstrapd", &servicesPort);
	if (err) {
#if __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wavailability"
#endif
		pid_t pid;
		char *const argv[] = { "/usr/libexec/_rocketd_reenable", NULL };
		if (posix_spawn(&pid, "/usr/libexec/_rocketd_reenable", NULL, NULL, argv, NULL) == 0) {
			waitpid(pid, NULL, 0);
		}
#if __clang__
#pragma clang diagnostic pop
#endif
		err = bootstrap_look_up(bootstrap, "com.rpetrich.rocketbootstrapd", &servicesPort);
	}
	if (err) {
#ifdef DEBUG
		NSLog(@"RocketBootstrap: failed to launch rocketd!");
#endif
	} else {
		mach_port_name_t replyPort = MACH_PORT_NULL;
		err = mach_port_allocate(self, MACH_PORT_RIGHT_RECEIVE, &replyPort);
		if (err == 0) {
			LMResponseBuffer buffer;
			uint32_t size = LMBufferSizeForLength(0);
			memset(&buffer.message, 0, sizeof(LMMessage));
			buffer.message.head.msgh_id = 2;
			buffer.message.head.msgh_size = size;
			buffer.message.head.msgh_local_port = replyPort;
			buffer.message.head.msgh_reserved = 0;
			buffer.message.head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
			buffer.message.head.msgh_remote_port = servicesPort;
			buffer.message.body.msgh_descriptor_count = 0;
			buffer.message.data.in_line.length = 0;
			err = mach_msg(&buffer.message.head, MACH_SEND_MSG | MACH_RCV_MSG | _LIGHTMESSAGING_TIMEOUT_FLAGS, size, sizeof(LMResponseBuffer), replyPort, LIGHTMESSAGING_TIMEOUT, MACH_PORT_NULL);
			if (err) {
			}
			// Cleanup
			mach_port_mod_refs(self, replyPort, MACH_PORT_RIGHT_RECEIVE, -1);
		}
		mach_port_mod_refs(self, servicesPort, MACH_PORT_RIGHT_SEND, -1);
	}
	// Find it
	pid_t pid = pid_of_process("rocketd");
	if (pid) {
#ifdef DEBUG
		NSLog(@"RocketBootstrap: rocketd found: %d", pid);
#endif
		daemon_die_queue = kqueue();
		struct kevent changes;
		EV_SET(&changes, pid, EVFILT_PROC, EV_ADD | EV_RECEIPT, NOTE_EXIT, 0, NULL);
		(void)kevent(daemon_die_queue, &changes, 1, &changes, 1, NULL);
		daemon_die_fd = CFFileDescriptorCreate(NULL, daemon_die_queue, true, process_terminate_callback, NULL);
		daemon_die_source = CFFileDescriptorCreateRunLoopSource(NULL, daemon_die_fd, 0);
	    CFRunLoopAddSource(CFRunLoopGetCurrent(), daemon_die_source, kCFRunLoopDefaultMode);
		CFFileDescriptorEnableCallBacks(daemon_die_fd, kCFFileDescriptorReadCallBack);
	} else {
		NSLog(@"RocketBootstrap: unable to find rocketd!");
	}
}

static void process_terminate_callback(CFFileDescriptorRef fd, CFOptionFlags callBackTypes, void *info)
{
	struct kevent event;
	(void)kevent(daemon_die_queue, NULL, 0, &event, 1, NULL);
	NSLog(@"RocketBootstrap: rocketd terminated: %d, relaunching", (int)(pid_t)event.ident);
	// Cleanup
	CFRunLoopRemoveSource(CFRunLoopGetCurrent(), daemon_die_source, kCFRunLoopDefaultMode);
	CFRelease(daemon_die_source);
	CFRelease(daemon_die_fd);
	close(daemon_die_queue);
	observe_rocketd();
}

static void SanityCheckNotificationCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags)
{
}

%ctor
{
	%init();
	// Attach rockets when in the com.apple.ReportCrash.SimulateCrash job
	// (can't check in using the launchd APIs because it hates more than one checkin; this will do)
	const char **_argv = *_NSGetArgv();
	if (strcmp(_argv[0], "/System/Library/CoreServices/ReportCrash") == 0 && _argv[1]) {
		if (strcmp(_argv[1], "-f") == 0) {
			isDaemon = YES;
#ifdef DEBUG
			NSLog(@"RocketBootstrap: Initializing ReportCrash using mach_msg_server");
#endif
			MSHookFunction(mach_msg_server_once, $mach_msg_server_once, (void **)&_mach_msg_server_once);
#ifdef __clang__
		} else if (strcmp(_argv[1], "com.apple.ReportCrash.SimulateCrash") == 0) {
			isDaemon = YES;
#ifdef DEBUG
			NSLog(@"RocketBootstrap: Initializing ReportCrash using XPC");
#endif
			MSImageRef libxpc = MSGetImageByName("/usr/lib/system/libxpc.dylib");
			if (libxpc) {
				void *xpc_connection_create_mach_service = MSFindSymbol(libxpc, "_xpc_connection_create_mach_service");
				if (xpc_connection_create_mach_service) {
					MSHookFunction(xpc_connection_create_mach_service, $xpc_connection_create_mach_service, (void **)&_xpc_connection_create_mach_service);
				} else {
#ifdef DEBUG
					NSLog(@"RocketBootstrap: Could not find xpc_connection_create_mach_service symbol!");
#endif
				}
				void *_xpc_connection_mach_event = MSFindSymbol(libxpc, "__xpc_connection_mach_event");
				if (_xpc_connection_mach_event) {
					MSHookFunction(_xpc_connection_mach_event, $_xpc_connection_mach_event, (void **)&__xpc_connection_mach_event);
				} else {
#ifdef DEBUG
					NSLog(@"RocketBootstrap: Could not find _xpc_connection_mach_event symbol!");
#endif
				}
			} else {
#ifdef DEBUG
				NSLog(@"RocketBootstrap: Could not find libxpc.dylib image!");
#endif
			}
#endif
		}
	} else if (strcmp(argv[0], "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0) {
#ifdef DEBUG
		NSLog(@"RocketBootstrap: Initializing SpringBoard");
#endif
		if (kCFCoreFoundationVersionNumber < 847.20) {
			return;
		}
		// Sanity check on the SimulateCrash service
		mach_port_t bootstrap = MACH_PORT_NULL;
		mach_port_t self = mach_task_self();
		task_get_bootstrap_port(self, &bootstrap);
		mach_port_t servicesPort = MACH_PORT_NULL;
		kern_return_t err = bootstrap_look_up(bootstrap, "com.apple.ReportCrash.SimulateCrash", &servicesPort);
		//bool has_simulate_crash;
		if (err) {
			//has_simulate_crash = false;
		} else {
			mach_port_mod_refs(self, servicesPort, MACH_PORT_RIGHT_SEND, -1);
			//has_simulate_crash = true;
			//servicesPort = MACH_PORT_NULL;
			//err = bootstrap_look_up(bootstrap, "com.rpetrich.rocketbootstrapd", &servicesPort);
		}
		if (err == 0) {
			mach_port_mod_refs(self, servicesPort, MACH_PORT_RIGHT_SEND, -1);
			observe_rocketd();
		} else {
			const CFTypeRef keys[] = {
				kCFUserNotificationAlertHeaderKey,
				kCFUserNotificationAlertMessageKey,
				kCFUserNotificationDefaultButtonTitleKey,
			};
			const CFTypeRef valuesCrash[] = {
				CFSTR("System files missing!"),
				CFSTR("RocketBootstrap has detected that your SimulateCrash crash reporting daemon is missing or disabled.\nThis daemon is required for proper operation of packages that depend on RocketBootstrap."),
				CFSTR("OK"),
			};
			/*const CFTypeRef valuesRocket[] = {
				CFSTR("System files missing!"),
				CFSTR("RocketBootstrap has detected that your rocketbootstrap daemon is missing or disabled.\nThis daemon is required for proper operation of packages that depend on RocketBootstrap."),
				CFSTR("OK"),
			};*/
			CFDictionaryRef dict = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, /*has_simulate_crash ? (const void **)valuesRocket :*/ (const void **)valuesCrash, sizeof(keys) / sizeof(*keys), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			SInt32 err = 0;
			CFUserNotificationRef notification = CFUserNotificationCreate(kCFAllocatorDefault, 0.0, kCFUserNotificationPlainAlertLevel, &err, dict);
			CFRunLoopSourceRef runLoopSource = CFUserNotificationCreateRunLoopSource(kCFAllocatorDefault, notification, SanityCheckNotificationCallback, 0);
			CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
			CFRelease(dict);
		}
	}
}
