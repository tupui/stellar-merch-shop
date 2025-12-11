# Xcode Setup Steps for Chimp NFC App

Follow these steps to complete the Xcode configuration for NFC functionality:

## 1. Open Project in Xcode
- Open `Chimp.xcodeproj` in Xcode

## 2. Add NFC Capability
1. Select the **Chimp** project in the navigator (top item)
2. Select the **Chimp** target
3. Go to the **"Signing & Capabilities"** tab
4. Click the **"+ Capability"** button (top left)
5. Search for and add **"Near Field Communication Tag Reading"**
6. This will automatically add the NFC entitlement to your project

## 3. Link CoreNFC Framework
1. Still in the **Chimp** target settings
2. Go to the **"Build Phases"** tab
3. Expand **"Link Binary With Libraries"**
4. Click the **"+"** button
5. Search for **"CoreNFC.framework"**
6. Add it to the project

## 4. Configure Info.plist
1. The `Info.plist` file has already been created with:
   - `NFCReaderUsageDescription`
   - `com.apple.developer.nfc.readersession.formats` (TAG format)
2. Verify these entries exist in Xcode:
   - Select `Info.plist` in the navigator
   - You should see "Privacy - NFC Scan Usage Description" with the description text
   - You should see "NFC Tag Reader Session Formats" with TAG format

## 5. Configure Entitlements
1. The `Chimp.entitlements` file has already been created
2. In the **"Signing & Capabilities"** tab, verify:
   - The entitlements file is set in **"Code Signing Entitlements"** field
   - The NFC capability shows "Near Field Communication Tag Reading" is enabled

## 6. Set Deployment Target
1. In the **Chimp** target settings, go to **"General"** tab
2. Set **"iOS Deployment Target"** to **iOS 13.0** or later (NFC Tag Reading requires iOS 13+)

## 7. Verify Info.plist Configuration
The project has been configured to use the manual `Info.plist` file instead of auto-generation:
- In **Build Settings**, search for "Info.plist File"
- It should be set to: `Chimp/Chimp/Info.plist`
- If you see "Generate Info.plist File" = YES, change it to NO (this has been done automatically)

If Xcode doesn't automatically recognize the new files:
1. Right-click on the **Chimp** folder in the navigator
2. Select **"Add Files to Chimp..."**
3. Navigate to and select:
   - `ViewController.swift`
   - `Info.plist` (if not already visible)
   - `Chimp.entitlements` (if not already visible)
4. Make sure **"Copy items if needed"** is checked
5. Make sure **"Add to targets: Chimp"** is checked
6. Click **"Add"**

## 8. Build and Run
1. Connect a physical iOS device (NFC does NOT work in the simulator)
2. Select your device as the run destination
3. Build and run the project (⌘R)
4. When you tap "Scan NFC Chip", hold your SECORA chip near the top of the iPhone
5. The app should detect the chip and read the public key

## Troubleshooting

### If NFC capability doesn't appear:
- Make sure you have a paid Apple Developer account (free accounts don't support NFC Tag Reading)
- Try cleaning the build folder (Product → Clean Build Folder, then ⌘⇧K)

### If build errors occur:
- Make sure `ViewController.swift` is added to the target
- Make sure CoreNFC framework is linked
- Check that deployment target is iOS 13.0 or later

### If chip is not detected:
- Make sure you're testing on a physical device (not simulator)
- Hold the chip steady on the back of the iPhone near the top
- Make sure the chip is a SECORA Blockchain Security 2Go chip
- Check that the chip works with other NFC apps to verify hardware

## Notes
- NFC Tag Reading requires iOS 13.0 or later
- NFC does NOT work in the iOS Simulator - you MUST use a physical device
- The app uses ISO 14443 polling to detect SECORA chips
- The AID used is: D2760000041502000100000001 (13 bytes)
