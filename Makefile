LIBRARY_NAME = librocketbootstrap
librocketbootstrap_FILES = Tweak.x Shims.x
librocketbootstrap_LIBRARIES = substrate
librocketbootstrap_FRAMEWORKS = Foundation

ADDITIONAL_CFLAGS = -std=c99

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
include framework/makefiles/tweak.mk
include framework/makefiles/library.mk

stage::
	mkdir -p "$(THEOS_STAGING_DIR)/usr/include"
	cp -a rocketbootstrap.h rocketbootstrap_dynamic.h "$(THEOS_STAGING_DIR)/usr/include"
	plutil -convert binary1 "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/RocketBootstrap.plist"
