#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

#import "rocketbootstrap.h"

#define kRocketBootstrapUnlockService "com.rpetrich.rocketbootstrapd"

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

#import "LightMessaging/LightMessaging.h"

__attribute__((unused))
static LMConnection connection = {
	MACH_PORT_NULL,
	kRocketBootstrapUnlockService
};

__attribute__((unused))
static inline bool rocketbootstrap_is_passthrough(void)
{
	return kCFCoreFoundationVersionNumber < 800.0;
}

__attribute__((unused))
static inline bool rocketbootstrap_uses_name_redirection(void)
{
	if (kCFCoreFoundationVersionNumber >= 1556.00) {
		static int state;
		int currentState = state;
		if (currentState == 0) {
			currentState = state = dlsym(RTLD_DEFAULT, "substitute_hook_functions") ? 1 : 2;
		}
		return currentState - 1;
	}
	return false;
}

kern_return_t _rocketbootstrap_is_unlocked(const name_t service_name); // Errors if not in a privileged process such as SpringBoard or backboardd
