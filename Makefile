# Tubie - YouTube client for jailbroken iOS 6.x (armv7) with its own TLS stack.
# Built with Theos. Deployment target iOS 6.0, compiled against the iOS 9.3 SDK.

TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
DEBUG ?= 0

# Device used by `make install` (Theos) - overridden by tools/ipad.ps1 anyway
THEOS_DEVICE_IP ?= 192.168.137.17
THEOS_DEVICE_USER ?= root

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Tubie

Tubie_FILES := $(wildcard src/*.m) $(wildcard src/*/*.m) \
                  vendor/mbedtls_glue.c \
                  $(wildcard vendor/mbedtls/library/*.c)

Tubie_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore CoreText Security ImageIO AVFoundation CoreMedia MediaPlayer AudioToolbox

# Flags for every C-family file (also the vendored mbedTLS sources)
Tubie_CFLAGS := -Isrc -Isrc/Net -Isrc/YouTube -Isrc/UI -Isrc/Util \
                   -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library \
                   -Os -fvisibility=hidden \
                   -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                   -Wno-deprecated-declarations -Wno-unknown-warning-option \
                   -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

# Objective-C only: ARC; APIs newer than iOS 6.0 are warnings here and turned into errors for our own
# sources by the pragma in src/TBCommon.h (vendored code only warns).
Tubie_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

Tubie_LDFLAGS := -lz

include $(THEOS)/makefiles/application.mk

# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them. The app avoids those classes, but should the linker still record
# CFNetwork, the load command is pointed at Foundation (harmless when there is none), then the binary is signed again.
TUBIE_STAGED_BIN := $(THEOS_STAGING_DIR)/Applications/Tubie.app/Tubie
after-stage::
	install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(TUBIE_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(TUBIE_STAGED_BIN)"
