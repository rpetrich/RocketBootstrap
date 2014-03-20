#import <xpc/xpc.h>
#import <rocketbootstrap.h>
#import <sandbox.h>
#import <stdbool.h>

bool start_appstore_sandbox() {
	char *errMessage;
	int err;
	if ((err = sandbox_init("container", SANDBOX_NAMED, &errMessage))) {
		printf("error: sandbox_init failed with error %d: %s\n", err, errMessage);
		sandbox_free_error(errMessage);
		return false;
	}
	return true;
}

int main(int argc, char *argv[]) {
	if (!start_appstore_sandbox()) {
		return 1;
	}
	int ret = 1;
	xpc_connection_t connection = xpc_connection_create_mach_service(
		"com.rpetrich.rocketbootstrap.tests.xpcserver",
		NULL,
		XPC_CONNECTION_MACH_SERVICE_PRIVILEGED
		);
	if (connection) {
		rocketbootstrap_xpc_connection_apply(connection);
		// For testing, we will use an empty event handler and sync. requests.
		xpc_connection_set_event_handler(connection, ^(xpc_object_t event){});
		xpc_connection_resume(connection);
		xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
		if (request) {
			xpc_dictionary_set_string(request, "hello", "world");
			xpc_object_t response = xpc_connection_send_message_with_reply_sync(connection, request);
			if (response) {
				xpc_type_t responseType = xpc_get_type(response);
				if (responseType == XPC_TYPE_DICTIONARY) {
					int universe = (int)xpc_dictionary_get_int64(response, "universe");
					if (universe == 42) {
						printf("client test succeeded\n");
						ret = 0;
					} else {
						printf("client test failed\n");
					}
				} else if (responseType == XPC_TYPE_ERROR) {
					printf("error: received XPC error: %s\n", xpc_dictionary_get_string(response, XPC_ERROR_KEY_DESCRIPTION));
				} else {
					printf("error: received invalid XPC response.\n");
				}
				xpc_release(response);
			} else {
				printf("error: xpc_connection_send_message_with_reply_sync failed\n");
			}
			xpc_release(request);
		} else {
			printf("error: xpc_dictionary_create failed\n");
		}
		xpc_connection_cancel(connection);
	} else {
		printf("error: failed to connect to XPC service\n");
	}
	return ret;
}
