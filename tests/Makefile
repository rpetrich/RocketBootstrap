LIBRARY_NAME = librocketbootstrap_messageport_test
librocketbootstrap_messageport_test_FILES = messageport_test.m
librocketbootstrap_messageport_test_LIBRARIES = rocketbootstrap
librocketbootstrap_messageport_test_FRAMEWORKS = Foundation UIKit

TOOL_NAME = librocketbootstrap_xpc_server_test
librocketbootstrap_xpc_server_test_FILES = xpc_server_test.m
librocketbootstrap_xpc_server_test_LIBRARIES = rocketbootstrap
librocketbootstrap_xpc_server_test_INSTALL_PATH = /usr/libexec

TOOL_NAME += librocketbootstrap_xpc_client_test
librocketbootstrap_xpc_client_test_FILES = xpc_client_test.m
librocketbootstrap_xpc_client_test_LIBRARIES = rocketbootstrap

ADDITIONAL_CFLAGS = -std=c99 -I../ -I../headers/
ADDITIONAL_LDFLAGS = -L../.theos/obj

NOLEGACY ?= 0
ifeq ($(NOLEGACY), 0)
	IPHONE_ARCHS = armv6 armv7 armv7s arm64
	SDKVERSION_armv6 = 5.1
	INCLUDE_SDKVERSION_armv6 = 7.0
	TARGET_IPHONEOS_DEPLOYMENT_VERSION = 4.0
	TARGET_IPHONEOS_DEPLOYMENT_VERSION_armv6 = 3.0
	THEOS_PLATFORM_SDK_ROOT_armv6 = /Applications/Xcode_Legacy.app/Contents/Developer
else
	IPHONE_ARCHS = armv7 armv7s arm64
	TARGET_IPHONEOS_DEPLOYMENT_VERSION = 5.0
endif

include framework/makefiles/common.mk
include framework/makefiles/library.mk
include framework/makefiles/tool.mk

after-stage::
	$(ECHO_NOTHING)echo "Applying file permissions..."$(ECHO_END)
	$(ECHO_NOTHING)$(FAKEROOT) find "$(THEOS_STAGING_DIR)/Library/LaunchDaemons" -iname '*.plist' -exec chown root:wheel "{}" \\\;$(ECHO_END)
