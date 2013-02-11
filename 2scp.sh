make
while [[ "$choice" != 'n' ]] && [[ "$choice" != 's' ]] && [[ "$choice" != 'd' ]] && [[ "$choice" != 'ss' ]] && [[ "$choice" != 'a' ]]
do read -p "Continue ? " choice; done
if [ $choice = "s" ]; then
ssh root@10.0.1.4 rm /Library/MobileSubstrate/DynamicLibraries/SimulateTouch.dylib
scp ./.theos/obj/SimulateTouch.dylib root@10.0.1.4:/Library/MobileSubstrate/DynamicLibraries/SimulateTouch.dylib
ssh root@10.0.1.4 killall SketchTime
fi
