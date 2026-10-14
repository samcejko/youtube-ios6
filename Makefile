# Tubie - YouTube client for jailbroken iOS with its own TLS stack. One source tree, two packages (Theos):
#   make package                               armv7 for iOS 6.x (the iOS 9.3 SDK, deployment target 6.0)
#   make package THEOS_PACKAGE_SCHEME=rootless arm64 for iOS 14-17 (the iOS 16.5 SDK, deployment target 14.0):
#                                              the .deb for rootless jailbreaks, the IPA for TrollStore
# (`make clean` between the two; CI builds both, see .github/workflows/build.yml)

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:16.5:14.0
ARCHS := arm64
else
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
endif
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

# The OAuth client secret of the Google sign-in (TV device flow) is not in the repository: CI takes it from the
# repository secret TUBIE_GOOGLE_CLIENT_SECRET (Settings -> Secrets and variables -> Actions) and compiles it in as a
# default; Settings -> Account can always override it. Without the variable the app builds and asks for the secret.
TUBIE_GOOGLE_CLIENT_SECRET ?=
Tubie_CFLAGS += -DTB_GOOGLE_CLIENT_SECRET=\"$(strip $(TUBIE_GOOGLE_CLIENT_SECRET))\"

# Objective-C only: ARC; APIs newer than the deployment target are warnings here and turned into errors for our
# own sources by the pragma in src/TBCommon.h (vendored code only warns). src/Util/TBModern.m bridges the newer
# iOS on its own terms and opts out.
Tubie_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

Tubie_LDFLAGS := -lz

include $(THEOS)/makefiles/application.mk

TUBIE_STAGED_APP := $(THEOS_STAGING_DIR)/Applications/Tubie.app
TUBIE_STAGED_BIN := $(TUBIE_STAGED_APP)/Tubie

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
# The arm64 bundle: iOS 14.0+, arm64 required, a launch screen the system draws instead of the iOS 6 launch
# images (tools/modern_bundle.py), signed again with the entitlements afterwards.
after-stage::
	python3 "$(THEOS_PROJECT_DIR)/tools/modern_bundle.py" "$(TUBIE_STAGED_APP)"
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(TUBIE_STAGED_BIN)"
# The .deb is for rootless jailbreaks (iOS 15 and newer; Theos sets Architecture: iphoneos-arm64 and the /var/jb
# prefix itself) and tells the home screen about the app when installed or removed.
before-package::
	sed -i -e 's/^Depends: firmware (>= 6.0)/Depends: firmware (>= 15.0)/' "$(THEOS_STAGING_DIR)/DEBIAN/control"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = configure ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && { uicache -p /var/jb/Applications/Tubie.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1; }' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = remove ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && uicache -a >/dev/null 2>&1' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
else
# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them. The app avoids those classes, but should the linker still record
# CFNetwork, the load command is pointed at Foundation (harmless when there is none), then the binary is signed again.
after-stage::
	install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(TUBIE_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(TUBIE_STAGED_BIN)"
endif
