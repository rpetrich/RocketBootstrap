#include <mach/mach.h>
#include <bootstrap.h>

kern_return_t rocketbootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp);
