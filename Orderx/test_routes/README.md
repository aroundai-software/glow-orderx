# Location Testing Guide for VK Traders

This folder contains tools and routes for testing the location tracking system without physical movement.

## 🎯 Quick Start

### Option 1: In-App Simulator (Recommended for Daily Development)

**Best for:** Quick filter testing, algorithm changes, UI development

1. Run app in debug mode: `flutter run`
2. Open **Salesman Trail Map** screen
3. Tap **purple 📍 button** (bottom-right corner)
4. Select scenario → Toggle **"Feed to Background Service"** → **Start**
5. Refresh trail map to see results

### Option 2: ADB/Emulator GPS Mocking (For Full E2E Testing)

**Best for:** Testing actual Geolocator plugin, real device behavior

---

## 📱 Method A: Android Emulator (Easiest)

1. Open **Android Studio → Tools → Device Manager**
2. Start any emulator
3. Click **"..." (Extended Controls)** on emulator sidebar
4. Go to **Location** tab
5. Either:
   - **Set single point:** Enter lat/lng and click "Set Location"
   - **Load GPX route:** Click "Load GPX/KML" → select `kerala_ghat_road.gpx`
   - **Play route:** Click "Play Route" to simulate movement

---

## 📱 Method B: PowerShell Script (For Emulator)

```powershell
# Navigate to test_routes folder
cd c:\Users\user\StudioProjects\vk_traders\test_routes

# Run Kochi urban route
.\adb_gps_test.ps1 -Route kochi

# Run Munnar ghat road (hairpin bends)
.\adb_gps_test.ps1 -Route munnar

# Run highway route
.\adb_gps_test.ps1 -Route highway

# Run stationary (test jitter filtering)
.\adb_gps_test.ps1 -Route stationary

# Custom single location
.\adb_gps_test.ps1 -Route custom -CustomLat 9.9312 -CustomLng 76.2673

# Change interval between points
.\adb_gps_test.ps1 -Route kochi -IntervalSeconds 3
```

---

## 📱 Method C: Physical Device Mock Location

### Step 1: Enable Developer Options
1. Go to **Settings → About Phone**
2. Tap **Build Number** 7 times
3. Go back to **Settings → Developer Options**

### Step 2: Enable Mock Locations
1. In **Developer Options**, find **"Select mock location app"**
2. Install a mock location app (e.g., "Fake GPS Location" from Play Store)
3. Select that app as the mock location provider

### Step 3: Use the Mock Location App
1. Open the mock location app
2. Set coordinates or load a route
3. Start mocking
4. Open VK Traders app - it will receive fake locations

---

## 📁 Test Route Files

| File | Description | Use Case |
|------|-------------|----------|
| `kerala_ghat_road.gpx` | Munnar ghat with 170° hairpin bends | Test bearing filter |
| `kochi_urban.gpx` | City route with shop stops | Test stop detection |
| `adb_gps_test.ps1` | PowerShell script for ADB | Automated testing |

---

## 🔬 What Each Method Tests

| Component | In-App Simulator | ADB/Emulator |
|-----------|------------------|--------------|
| GPS Filter pipeline | ✅ | ✅ |
| Kalman smoothing | ✅ | ✅ |
| Bearing filter (hairpins) | ✅ | ✅ |
| Map matching | ✅ | ✅ |
| Snap-to-road | ✅ | ✅ |
| Geolocator plugin | ❌ (bypassed) | ✅ |
| Background service | ✅ | ✅ |
| Supabase upload | ✅ | ✅ |
| Foreground notification | ❌ | ✅ |
| Battery level | Fake (0%) | Real |

---

## 🧪 Testing Checklist

### After GPS Filter Changes:
- [ ] Run **Munnar Ghat** preset - verify hairpin bends appear
- [ ] Run **Stationary** preset - verify no false movement
- [ ] Run **Kochi Urban** - verify stops are detected
- [ ] Check console logs for filter statistics

### After Map Matching Changes:
- [ ] Run any route with **"Feed to Background Service"** ON
- [ ] Refresh trail map
- [ ] Verify polyline follows roads (not straight lines)

### After Snap-to-Road Changes:
- [ ] Load a route with many points
- [ ] Check console for "chunk-based snapToRoad" messages
- [ ] Verify smooth road-following polyline

---

## 💡 Tips

1. **Always use debug mode** - Simulator FAB is hidden in release builds
2. **Check Logcat/Console** - Look for 🎮 and 📍 emoji prefixed logs
3. **Refresh trail map** after simulation to see results
4. **Use emulator** for GPX route replay - physical devices need mock apps
5. **Test Kerala-specific scenarios** - Ghat roads, backwaters, urban

---

## ⚠️ Troubleshooting

### "No device connected" error in ADB script
- Start Android Studio emulator first
- Or connect physical device with USB debugging enabled

### Simulator FAB not visible
- Make sure you're running in **debug mode** (`flutter run`), not release
- FAB appears on **Salesman Trail Map** screen only

### Simulated locations not appearing in trail
- Toggle **"Feed to Background Service"** ON
- Make sure tracking is started for the salesman
- Check console for "Cannot inject position: tracking not started"

### GPX route not loading in emulator
- Use the "Load GPX/KML" button in emulator's Extended Controls → Location
- Make sure GPX file is valid XML
