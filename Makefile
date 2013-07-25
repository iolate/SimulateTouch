FW_DEVICE_IP=10.0.1.4

#ARCHS = armv7 armv7s

include theos/makefiles/common.mk

TWEAK_NAME = STClient STServer
STClient_FILES = Tweak.xm
STClient_FRAMEWORKS = CoreGraphics

STServer_FILES = SimulateTouch.mm
STServer_PRIVATE_FRAMEWORKS = GraphicsServices
STServer_LDFLAGS = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk