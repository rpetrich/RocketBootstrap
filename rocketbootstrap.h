#include <mach/mach.h>
#include <bootstrap.h>

#ifndef ROCKETBOOTSTRAP_LOAD_DYNAMIC

kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp);

// SpringBoard-only
kern_return_t rocketbootstrap_unlock(const name_t service_name);

#else

#include <dlfcn.h>

__attribute__((unused))
static kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp)
{
	static kern_return_t (*impl)(mach_port_t bp, const name_t service_name, mach_port_t *sp);
	if (!impl) {
		void *handle = dlopen("/usr/lib/librocketbootstrap.dylib", RTLD_LAZY);
		if (handle)
			impl = dlsym(handle, "rocketbootstrap_look_up");
		if (!impl)
			impl = bootstrap_look_up;
	}
	return impl(bp, service_name, sp);
}

__attribute__((unused))
static kern_return_t rocketbootstrap_unlock(const name_t service_name)
{
	static kern_return_t (*impl)(const name_t service_name);
	if (!impl) {
		void *handle = dlopen("/usr/lib/librocketbootstrap.dylib", RTLD_LAZY);
		if (handle)
			impl = dlsym(handle, "rocketbootstrap_unlock");
		if (!impl)
			return -1;
	}
	return impl(service_name);
}

#endif