#import <xpc/xpc.h>
#import <rocketbootstrap.h>

int service_main() {
	xpc_connection_t listener = xpc_connection_create_mach_service(
		"com.rpetrich.rocketbootstrap.tests.xpcserver",
		NULL,
		XPC_CONNECTION_MACH_SERVICE_LISTENER
		);
	if (listener) {
		rocketbootstrap_xpc_unlock(listener);
		xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
			NSLog(@"client connected");
			xpc_connection_set_event_handler(peer, ^(xpc_object_t object) {
				xpc_type_t type = xpc_get_type(object);
				if (type == XPC_TYPE_DICTIONARY) {
					char *desc = xpc_copy_description(object);
					NSLog(@"client sent a message: %s", desc);
					free(desc);
					xpc_object_t reply = xpc_dictionary_create_reply(object);
					if (reply) {
						xpc_dictionary_set_int64(reply, "universe", 42);
						xpc_connection_send_message(peer, reply);
						xpc_release(reply);
					} else {
						NSLog(@"xpc_dictionary_create_reply failed");
					}
				} else if (type == XPC_TYPE_ERROR) {
					NSLog(@"client disconnected");
				} else {
					NSLog(@"received unexpected XPC object");
				}
			});
			xpc_connection_resume(peer);
		});
		xpc_connection_resume(listener);
		dispatch_main();
		return 0; // never reached
	} else {
		NSLog(@"Failed to create socket service");
		return 1;
	}
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		return service_main();
	}
}
