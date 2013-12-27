#include <mach/mach.h>

#ifndef __BOOTSTRAP_H__
// Borrowed from bootstrap.h, so you can import this header without having bootstrap
#define	BOOTSTRAP_MAX_NAME_LEN			128
typedef char name_t[BOOTSTRAP_MAX_NAME_LEN];
#endif

kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp);

// SpringBoard-only
kern_return_t rocketbootstrap_unlock(const name_t service_name);
