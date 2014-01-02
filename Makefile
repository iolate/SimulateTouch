FW_DEVICE_IP=10.0.1.4

#ARCHS = armv7 armv7s

include theos/makefiles/common.mk

TWEAK_NAME = SimulateTouch #STPoseWindow
SimulateTouch_FILES = SimulateTouch.xm
SimulateTouch_PRIVATE_FRAMEWORKS = GraphicsServices IOKit
SimulateTouch_LDFLAGS = -lsubstrate

STPoseWindow_FILES = Tweak.xm
STPoseWindow_FRAMEWORKS = UIKit

LIBRARY_NAME = libsimulatetouch
libsimulatetouch_FILES = STLibrary.mm
libsimulatetouch_INSTALL_PATH = /usr/lib/
libsimulatetouch_FRAMEWORKS = UIKit CoreGraphics

TOOL_NAME = stouch
stouch_FILES = main.mm
stouch_FRAMEWORKS = UIKit
stouch_INSTALL_PATH = /usr/bin/
stouch_LDFLAGS = -lsimulatetouch

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk
include $(THEOS_MAKE_PATH)/tool.mk