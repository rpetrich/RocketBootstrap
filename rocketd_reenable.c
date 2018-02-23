#import <unistd.h>
#import <dlfcn.h>
#import <stdio.h>

#ifdef __arm64__
#import "libjailbreak_xpc.h"
static int fix_setuid(void)
{
	void *libjailbreak = dlopen("/usr/lib/libjailbreak.dylib", RTLD_LAZY);
	if (libjailbreak) {
		jb_connection_t (*jb_connect)(void) = dlsym(libjailbreak, "jb_connect");
		int (*jb_fix_setuid_now)(jb_connection_t connection, pid_t pid) = dlsym(libjailbreak, "jb_fix_setuid_now");
		void (*jb_disconnect)(jb_connection_t connection) = dlsym(libjailbreak, "jb_disconnect");
		if (jb_connect && jb_fix_setuid_now && jb_disconnect) {
			jb_connection_t connection = jb_connect();
			if (connection) {
				int result = jb_fix_setuid_now(connection, getpid());
				jb_disconnect(connection);
				return result;
			}
		}
	}
	return 1;
}
#else
static int fix_setuid(void)
{
	// Does not apply to older iOS versions
	return 1;
}
#endif

int main(int argc, char *argv[])
{
	close(0);
	close(1);
	close(2);
	fix_setuid();
	setuid(0);
	setgid(0);
	seteuid(0);
	setegid(0);
	return execlp("launchctl", "launchctl", "load", "/Library/LaunchDaemons/com.rpetrich.rocketbootstrapd.plist", NULL);
}
