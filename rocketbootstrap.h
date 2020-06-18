#ifndef ROCKETBOOTSTRAP_H
#define ROCKETBOOTSTRAP_H

#include <sys/cdefs.h>
#include <mach/mach.h>
#include "bootstrap.h"

__BEGIN_DECLS
#ifndef ROCKETBOOTSTRAP_LOAD_DYNAMIC

// Look up a port by service name
kern_return_t rocketbootstrap_look_up(mach_port_t bootstrap_port, const name_t service_name, mach_port_t *out_service_port);

// Grant system-wide access to a particular service name
// Note: Will return an error if called from within a sandboxed process
kern_return_t rocketbootstrap_unlock(const name_t service_name);
// Register a port with and grant system-wide access to a particular service name
// Note: Will return an error if called from within a sandboxed process
kern_return_t rocketbootstrap_register(mach_port_t bootstrap_port, name_t service_name, mach_port_t service_port);


// CFMessagePort helpers

#ifdef __COREFOUNDATION_CFMESSAGEPORT__
// Acquire access to a system-wide CFMessagePort service
CFMessagePortRef rocketbootstrap_cfmessageportcreateremote(CFAllocatorRef allocator, CFStringRef name);
// Expose access to a CFMessagePort service
// Note: Will return an error if called from within a sandboxed process
kern_return_t rocketbootstrap_cfmessageportexposelocal(CFMessagePortRef messagePort);
#endif


// CPDistributedMessagingCenter helpers

#ifdef __OBJC__
// Unlock access to a system-wide CPDistributedMessagingCenter service
// Note: Server processes may only run inside privileged processes
@class CPDistributedMessagingCenter;
void rocketbootstrap_distributedmessagingcenter_apply(CPDistributedMessagingCenter *messaging_center);
#endif


// XPC helpers

#ifdef __XPC_CONNECTION_H__
// Create an XPC connection representing a system-wide service
// flags should be XPC_CONNECTION_MACH_SERVICE_LISTENER for a listener connection, and 0 for a client client connection
// XPC_CONNECTION_MACH_SERVICE_LISTENER will return an error if called from within a sandboxed process
// 0 will return an error if the service name hasn't been registered
xpc_connection_t rocketbootstrap_xpc_connection_create(const char *name, dispatch_queue_t targetq, uint64_t flags);
// Copy the application bundle identifier of the peer connection
xpc_object_t rocketbootstrap_xpc_connection_copy_application_identifier(xpc_connection_t connection);
#endif


#else
#include "rocketbootstrap_dynamic.h"
#endif
__END_DECLS

#endif
