# ADB GPS Testing Script for VK Traders
# Run this script in PowerShell with a connected Android device/emulator

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("kochi", "munnar", "highway", "stationary", "custom")]
    [string]$Route = "kochi",
    
    [Parameter(Mandatory=$false)]
    [int]$IntervalSeconds = 5,
    
    [Parameter(Mandatory=$false)]
    [double]$CustomLat = 9.9312,
    
    [Parameter(Mandatory=$false)]
    [double]$CustomLng = 76.2673
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   VK Traders GPS Simulation via ADB   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check ADB connection
$devices = adb devices
if ($devices -notmatch "device$") {
    Write-Host "ERROR: No device connected. Please connect a device or start an emulator." -ForegroundColor Red
    Write-Host "For emulator: Use Android Studio's AVD Manager" -ForegroundColor Yellow
    exit 1
}

Write-Host "Device connected!" -ForegroundColor Green

# Define routes
$routes = @{
    "kochi" = @(
        @{lat=9.9716; lng=76.2850},
        @{lat=9.9720; lng=76.2855},
        @{lat=9.9725; lng=76.2860},
        @{lat=9.9730; lng=76.2865},  # Stop 1
        @{lat=9.9730; lng=76.2865},
        @{lat=9.9735; lng=76.2870},
        @{lat=9.9742; lng=76.2878},
        @{lat=9.9750; lng=76.2885},
        @{lat=9.9755; lng=76.2890},
        @{lat=9.9755; lng=76.2900},
        @{lat=9.9755; lng=76.2915},  # Stop 2
        @{lat=9.9755; lng=76.2915},
        @{lat=9.9760; lng=76.2920},
        @{lat=9.9768; lng=76.2925},
        @{lat=9.9775; lng=76.2930}
    )
    "munnar" = @(
        @{lat=10.0889; lng=77.0595},
        @{lat=10.0895; lng=77.0600},
        @{lat=10.0902; lng=77.0608},
        @{lat=10.0910; lng=77.0615},  # Hairpin 1
        @{lat=10.0905; lng=77.0620},
        @{lat=10.0898; lng=77.0618},
        @{lat=10.0890; lng=77.0625},
        @{lat=10.0885; lng=77.0635},
        @{lat=10.0880; lng=77.0645},
        @{lat=10.0875; lng=77.0655},  # Hairpin 2
        @{lat=10.0880; lng=77.0660},
        @{lat=10.0888; lng=77.0658},
        @{lat=10.0895; lng=77.0665},
        @{lat=10.0905; lng=77.0675},
        @{lat=10.0915; lng=77.0680}
    )
    "highway" = @(
        @{lat=9.9312; lng=76.2673},
        @{lat=9.9320; lng=76.2700},
        @{lat=9.9328; lng=76.2730},
        @{lat=9.9335; lng=76.2760},
        @{lat=9.9342; lng=76.2790},
        @{lat=9.9350; lng=76.2820},
        @{lat=9.9358; lng=76.2850},
        @{lat=9.9365; lng=76.2880},
        @{lat=9.9372; lng=76.2910},
        @{lat=9.9380; lng=76.2940}
    )
    "stationary" = @(
        @{lat=9.9312; lng=76.2673},
        @{lat=9.9312; lng=76.2673},
        @{lat=9.9313; lng=76.2674},  # Minor jitter
        @{lat=9.9312; lng=76.2673},
        @{lat=9.9311; lng=76.2672},  # Minor jitter
        @{lat=9.9312; lng=76.2673}
    )
}

# Select route
if ($Route -eq "custom") {
    $selectedRoute = @(@{lat=$CustomLat; lng=$CustomLng})
    Write-Host "Using custom location: $CustomLat, $CustomLng" -ForegroundColor Yellow
} else {
    $selectedRoute = $routes[$Route]
    Write-Host "Selected route: $Route ($($selectedRoute.Count) points)" -ForegroundColor Yellow
}

Write-Host "Interval: $IntervalSeconds seconds between points" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Ctrl+C to stop simulation" -ForegroundColor Magenta
Write-Host ""

# Run simulation
$pointIndex = 0
$loopCount = 0

try {
    while ($true) {
        $point = $selectedRoute[$pointIndex]
        $lat = $point.lat
        $lng = $point.lng
        
        # ADB geo fix format: longitude latitude [altitude [satellites]]
        # Note: ADB uses longitude FIRST, then latitude
        $cmd = "adb emu geo fix $lng $lat"
        
        Write-Host "[$loopCount.$pointIndex] Sending: lat=$lat, lng=$lng" -ForegroundColor Green
        Invoke-Expression $cmd 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            # Try alternative method for physical devices with mock location apps
            Write-Host "  (emu geo fix failed - use a mock location app for physical devices)" -ForegroundColor Yellow
        }
        
        # Move to next point
        $pointIndex++
        if ($pointIndex -ge $selectedRoute.Count) {
            $pointIndex = 0
            $loopCount++
            Write-Host "--- Route complete, looping (loop $loopCount) ---" -ForegroundColor Cyan
        }
        
        Start-Sleep -Seconds $IntervalSeconds
    }
}
catch {
    Write-Host "`nSimulation stopped." -ForegroundColor Yellow
}

Write-Host "Done!" -ForegroundColor Green
