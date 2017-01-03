LIBRARY_NAME = librocketbootstrap
librocketbootstrap_FILES = Tweak.x Shims.x
librocketbootstrap_LIBRARIES = substrate
librocketbootstrap_FRAMEWORKS = Foundation

TOOL_NAME = rocketd
rocketd_FILES = rocketd.c
rocketd_CFLAGS = -fblocks
rocketd_FRAMEWORKS = CoreFoundation
rocketd_INSTALL_PATH = /usr/libexec

ADDITIONAL_CFLAGS = -std=c99 -Ioverlayheaders

# Support targeting 3.0 in packaged builds, but allow testing packages/builds to be missing support for old iOS versions
LEGACY_XCODE_PATH ?= /Applications/Xcode_Legacy.app

ifeq ($(wildcard $(LEGACY_XCODE_PATH)/.*),)
IPHONE_ARCHS = armv7 armv7s arm64
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 7.0
ifeq ($(FINALPACKAGE),1)
$(error Building final package requires a legacy Xcode install!)
endif
else
rocketd_IPHONE_ARCHS = armv6 arm64
IPHONE_ARCHS = armv6 armv7 armv7s arm64
SDKVERSION_armv6 = 5.1
INCLUDE_SDKVERSION_armv6 = 8.4
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 4.0
TARGET_IPHONEOS_DEPLOYMENT_VERSION_arm64 = 7.0
TARGET_IPHONEOS_DEPLOYMENT_VERSION_armv6 = 3.0
THEOS_PLATFORM_SDK_ROOT_armv6 = $(LEGACY_XCODE_PATH)/Contents/Developer
endif

include framework/makefiles/common.mk
include framework/makefiles/library.mk
include framework/makefiles/tool.mk

stage::
	mkdir -p "$(THEOS_STAGING_DIR)/usr/include"
	cp -a rocketbootstrap.h rocketbootstrap_dynamic.h "$(THEOS_STAGING_DIR)/usr/include"
	plutil -convert binary1 "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/RocketBootstrap.plist"
	plutil -convert binary1 "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.rpetrich.rocketbootstrapd.plist"
