#import <Foundation/Foundation.h>
#define LIGHTMESSAGING_USE_ROCKETBOOTSTRAP 0

#import "rocketbootstrap_internal.h"

static NSMutableSet *allowedNames;

static const uint32_t one = 1;

static void machPortCallback(CFMachPortRef port, void *bytes, CFIndex size, void *info)
{
	LMMessage *request = bytes;
	if (!LMDataWithSizeIsValidMessage(bytes, size)) {
		LMSendReply(request->head.msgh_remote_port, NULL, 0);
		LMResponseBufferFree(bytes);
		return;
	}
	// Send Response
	const void *data = LMMessageGetData(request);
	size_t length = LMMessageGetDataLength(request);
	const void *reply_data = NULL;
	uint32_t reply_length = 0;
	if (length) {
		NSString *name = [[NSString alloc] initWithBytes:data length:length encoding:NSUTF8StringEncoding];
		if (name) {
			switch (request->head.msgh_id) {
				case 0: // Register
#ifdef DEBUG
					NSLog(@"Unlocking %@", name);
#endif
					if (!allowedNames)
						allowedNames = [[NSMutableSet alloc] init];
					[allowedNames addObject:name];
					break;
				case 1: // Query
					if ([allowedNames containsObject:name]) {
						reply_data = &one;
						reply_length = sizeof one;
#ifdef DEBUG
						NSLog(@"Queried %@, is unlocked", name);
#endif
					} else {
#ifdef DEBUG
						NSLog(@"Queried %@, is locked!", name);
#endif
					}
					break;
			}
		}
		[name release];
	}
	LMSendReply(request->head.msgh_remote_port, reply_data, reply_length);
	LMResponseBufferFree(bytes);
}

int main(int argc, char *argv[])
{
	LMCheckInService(connection.serverName, CFRunLoopGetCurrent(), machPortCallback, NULL);
	CFRunLoopRun();
	return 0;
}
