# NinebotEnhance iOS — Theos build (dylib for TrollStore injector / TrollFools)
# No .deb: the deliverable is the bare .dylib, self-contained (substrate_shim
# implements MSHookMessageEx — the injected app has no Substrate/ElleKit).
TARGET = iphone:clang:latest:16.0
ARCHS  = arm64

TWEAK_NAME = NinebotEnhance

NinebotEnhance_FILES      = Tweak.x substrate_shim.m
NinebotEnhance_FRAMEWORKS = Foundation CoreGraphics CoreVideo CoreText ImageIO UIKit CoreLocation CallKit Network CoreTelephony AVFoundation AudioToolbox
NinebotEnhance_CFLAGS     = -fobjc-arc -I$(THEOS_PROJECT_DIR)/include
NinebotEnhance_LDFLAGS    = -Wl,-undefined,dynamic_lookup -install_name @executable_path/Frameworks/NinebotEnhance.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
