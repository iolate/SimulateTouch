export SDKVERSION=5.1
export FW_DEVICE_IP=10.0.1.4

#ARCHS = armv7 armv7s

include theos/makefiles/common.mk

TWEAK_NAME = SimulateTouch
SimulateTouch_FILES = Tweak.xm
SimulateTouch_FRAMEWORKS = UIKit
SimulateTouch_PRIVATE_FRAMEWORKS = GraphicsServices
SimulateTouch_LDFLAGS = -lsubstrate


include $(THEOS_MAKE_PATH)/tweak.mk
