TARGET := iphone:clang:latest:13.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard MobileGestaltHelper rocketd _rocketd_reenable

LIBRARY_NAME := librocketbootstrap
librocketbootstrap_FILES += Tweak.x Shims.x
librocketbootstrap_LIBRARIES += substrate
librocketbootstrap_WEAK_LIBRARIES += libs/TweakInject.tbd
librocketbootstrap_FRAMEWORKS += Foundation
librocketbootstrap_USE_MODULES += 0

TOOL_NAME := rocketd _rocketd_reenable
rocketd_FILES += rocketd.c
rocketd_CFLAGS += -fblocks
rocketd_FRAMEWORKS += CoreFoundation
rocketd_INSTALL_PATH += /usr/libexec
rocketd_USE_MODULES += 0
rocketd_CODESIGN_FLAGS += -Sentitlements.xml

_rocketd_reenable_FILES += rocketd_reenable.c
_rocketd_reenable_INSTALL_PATH += /usr/libexec
_rocketd_reenable_USE_MODULES += 0
_rocketd_reenable_CODESIGN_FLAGS += -Sentitlements.xml

ADDITIONAL_CFLAGS += -std=c99 -Idefaultheaders -include prefix.pch
ADDITIONAL_LDFLAGS += -Wl,-no_warn_inits

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/library.mk
include $(THEOS_MAKE_PATH)/tool.mk

stage::
	mkdir -p "$(THEOS_STAGING_DIR)/usr/include"
	cp -a rocketbootstrap.h rocketbootstrap_dynamic.h "$(THEOS_STAGING_DIR)/usr/include"
	plutil -convert binary1 "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/RocketBootstrap.plist"
	plutil -convert binary1 "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.rpetrich.rocketbootstrapd.plist"
