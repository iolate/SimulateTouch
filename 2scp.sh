DEV_IP=10.0.1.4
TWEAK_NAME=STServer
TWEAK_NAME=STClient
TWEAK_TARGET_NAME=backboardd
SETTINGS_NAME=ReportTool

make
while [[ "$choice" != 'n' ]] && [[ "$choice" != 's' ]] && [[ "$choice" != 'd' ]] && [[ "$choice" != 'ss' ]] && [[ "$choice" != 'a' ]]
do read -p "Continue ? " choice; done
if [ $choice = "s" ]; then
ssh root@$DEV_IP rm /Library/MobileSubstrate/DynamicLibraries/$TWEAK_NAME.dylib
scp ./.theos/obj/$TWEAK_NAME.dylib root@$DEV_IP:/Library/MobileSubstrate/DynamicLibraries/$TWEAK_NAME.dylib
ssh root@$DEV_IP killall $TWEAK_TARGET_NAME
else 
if [ $choice = "ss" ]; then
ssh root@$DEV_IP killall Preferences
ssh root@$DEV_IP rm /Library/PreferenceBundles/$SETTINGS_NAME.bundle/$SETTINGS_NAME
scp ./.theos/obj/$SETTINGS_NAME.bundle/$SETTINGS_NAME root@$DEV_IP:/Library/PreferenceBundles/$SETTINGS_NAME.bundle/
else echo "===Canceled.==="; fi
fi
