// DONT INCLUDE DIRECTLY
// Set ROCKETBOOTSTRAP_LOAD_DYNAMIC and then include rocketbootstrap.h
#include <dlfcn.h>

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>

__attribute__((unused))
static void *_rocketbootstrap_dlsym_func(const char *name) {
	void *handle = dlopen("/usr/lib/librocketbootstrap.dylib", RTLD_LAZY);
	if (handle) {
		void *result = dlsym(handle, name);
		if (result) {
			return ptrauth_sign_unauthenticated(ptrauth_strip(result, ptrauth_key_function_pointer), ptrauth_key_function_pointer, 0);
		}
	}
	return NULL;
}

#else

__attribute__((unused))
static void *_rocketbootstrap_dlsym_func(const char *name) {
	void *handle = dlopen("/usr/lib/librocketbootstrap.dylib", RTLD_LAZY);
	if (handle) {
		return dlsym(handle, name);
	}
	return NULL;
}

#endif

__attribute__((unused))
static kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp)
{
	static kern_return_t (*impl)(mach_port_t bp, const name_t service_name, mach_port_t *sp);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_look_up");
		if (!impl) {
			impl = bootstrap_look_up;
		}
	}
	return impl(bp, service_name, sp);
}

__attribute__((unused))
static kern_return_t rocketbootstrap_unlock(const name_t service_name)
{
	static kern_return_t (*impl)(const name_t service_name);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_unlock");
		if (!impl) {
			return -1;
		}
	}
	return impl(service_name);
}

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
__attribute__((unused))
static kern_return_t rocketbootstrap_register(mach_port_t bp, name_t service_name, mach_port_t sp)
{
	static kern_return_t (*impl)(mach_port_t bp, name_t service_name, mach_port_t sp);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_register");
		if (!impl) {
			impl = bootstrap_register;
		}
	}
	return impl(bp, service_name, sp);
}
#pragma GCC diagnostic warning "-Wdeprecated-declarations"

#ifdef __COREFOUNDATION_CFMESSAGEPORT__
__attribute__((unused))
static CFMessagePortRef rocketbootstrap_cfmessageportcreateremote(CFAllocatorRef allocator, CFStringRef name)
{
	static CFMessagePortRef (*impl)(CFAllocatorRef allocator, CFStringRef name);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_cfmessageportcreateremote");
		if (!impl) {
			impl = CFMessagePortCreateRemote;
		}
	}
	return impl(allocator, name);
}
__attribute__((unused))
static kern_return_t rocketbootstrap_cfmessageportexposelocal(CFMessagePortRef messagePort)
{
	static kern_return_t (*impl)(CFMessagePortRef messagePort);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_cfmessageportexposelocal");
		if (!impl) {
			return -1;
		}
	}
	return impl(messagePort);
}
#endif

#ifdef __OBJC__
@class CPDistributedMessagingCenter;
__attribute__((unused))
static void rocketbootstrap_distributedmessagingcenter_apply(CPDistributedMessagingCenter *messaging_center)
{
	static void (*impl)(CPDistributedMessagingCenter *messagingCenter);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_distributedmessagingcenter_apply");
		if (!impl)
			return;
	}
	impl(messaging_center);
}
#endif

#ifdef __XPC_CONNECTION_H__
__attribute__((unused))
static xpc_connection_t rocketbootstrap_xpc_connection_create(const char *name, dispatch_queue_t targetq, uint64_t flags)
{
	static xpc_connection_t (*impl)(const char *name, dispatch_queue_t targetq, uint64_t flags);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_xpc_connection_create");
		if (!impl)
			return NULL;
	}
	return impl(name, targetq, flags);
}

__attribute__((unused))
static xpc_object_t rocketbootstrap_xpc_connection_copy_application_identifier(xpc_connection_t connection)
{
	static xpc_object_t (*impl)(xpc_connection_t connection);
	if (!impl) {
		impl = _rocketbootstrap_dlsym_func("rocketbootstrap_xpc_connection_copy_application_identifier");
		if (!impl)
			return NULL;
	}
	return impl(connection);
}
#endif
