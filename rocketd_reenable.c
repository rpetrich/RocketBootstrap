#import <unistd.h>

int main(int argc, char *argv[])
{
	close(0);
	close(1);
	close(2);
	setuid(0);
	setgid(0);
	seteuid(0);
	setegid(0);
	return execlp("launchctl", "launchctl", "load", "/Library/LaunchDaemons/com.rpetrich.rocketbootstrapd.plist", NULL);
}
