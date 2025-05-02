param (
    [Parameter(Mandatory=$false)]
    [Alias("i")]
    [string]$InputFile,

    [Parameter(Mandatory=$false)]
    [Alias("s")]
    [int]$StartTime,

    [Parameter(Mandatory=$false)]
    [Alias("d")]
    [int]$Duration,

    [Parameter(Mandatory=$false)]
    [Alias("speed")]
    [double]$SpeedModifier = 1.0,

    [Parameter(Mandatory=$false)]
    [Alias("r")]
    [int]$Rotation,

    [Parameter(Mandatory=$false)]
    [string]$CropRatio,

    [Parameter(Mandatory=$false)]
    [string]$TargetSize,

    [Parameter(Mandatory=$false)]
    [Alias("q")]
    [string]$Quality = "medium",

    [Parameter(Mandatory=$false)]
    [Alias("small")]
    [switch]$SmallestFile,

    [Parameter(Mandatory=$false)]
    [switch]$y
)

# Define target size presets
$SizePresets = @{
    "original" = "original" # Added "original"
    "256x256"  = "256x256"   # Added some square sizes
    "512x512"  = "512x512"
    "640x640"  = "640x640"
    "720x720"  = "720x720"
    "1024x1024" = "1024x1024"
    "nHD" = "640x360"
    "qHD" = "960x540"
    "HD" = "1280x720"
    "FHD" = "1920x1080"
    "2K" = "2048x1080"
    "UHD" = "3840x2160"
    "4K" = "4096x2160"
}

# Define quality presets with CRF values (lower = better quality, higher = smaller file)
$QualityPresets = @{
    "high" = 18      # High quality, larger file
    "medium" = 23    # Original default
    "low" = 28       # Lower quality, smaller file
    "verylow" = 35   # Very low quality, very small file
}

# Function to prompt for input if not provided
function Get-UserInput {
    param (
        [string]$Prompt,
        [string]$Default,
        [scriptblock]$Validator = { $true },
        [switch]$Required
    )

    if ($y -and $Default) {
        return $Default
    }

    do {
        $input = Read-Host "$Prompt [default: $Default]"
        if ([string]::IsNullOrEmpty($input)) {
            $input = $Default
        }

        $valid = & $Validator $input
        if (-not $valid) {
            Write-Host "Invalid input. Please try again."
        }
        elseif ($Required -and [string]::IsNullOrEmpty($input)) {
            Write-Host "This field is required. Please provide a value."
            $valid = $false
        }
    } while (-not $valid)

    return $input
}

# Get required input file if not provided
if ([string]::IsNullOrEmpty($InputFile)) {
    $InputFile = Get-UserInput -Prompt "Enter input file path" -Default "" -Required
}

# Check if the input file exists
if (-not (Test-Path $InputFile)) {
    Write-Error "Input file does not exist: $InputFile"
    exit 1
}

# Get the start time if not provided
if (-not $StartTime) {
    $StartTime = [int](Get-UserInput -Prompt "Enter start time (in seconds)" -Default "0" -Validator { param($v) $v -match '^\d+$' })
}

# Get the duration if provided
if (-not $Duration) {
    $DurationInput = Get-UserInput -Prompt "Enter duration in seconds (leave empty for full video)" -Default ""
    if (-not [string]::IsNullOrEmpty($DurationInput)) {
        $Duration = [int]$DurationInput
    }
}

# Get the speed modifier if not provided
if (-not $PSBoundParameters.ContainsKey('SpeedModifier')) {
    $SpeedModifier = [double](Get-UserInput -Prompt "Enter speed modifier (1.0 = normal speed)" -Default "1.0" -Validator { param($v) $v -match '^\d+(\.\d+)?$' })
}

# Get rotation if not provided
if (-not $PSBoundParameters.ContainsKey('Rotation')) {
    $RotationOptions = @{
        "0" = "No rotation"
        "90" = "Rotate 90 degrees right"
        "180" = "Rotate 180 degrees"
        "270" = "Rotate 90 degrees left"
    }
    
    Write-Host "Rotation options:"
    foreach ($key in $RotationOptions.Keys | Sort-Object) {
        Write-Host "$key - $($RotationOptions[$key])"
    }
    
    $RotationInput = Get-UserInput -Prompt "Select rotation angle" -Default "0" -Validator { param($v) $RotationOptions.ContainsKey($v) }
    $Rotation = [int]$RotationInput
}

# Get crop ratio if not provided
if ([string]::IsNullOrEmpty($CropRatio)) {
    $CropOptions = @{
        "none" = "No cropping"
        "1:1" = "Square (1:1)"
        "16:9" = "Widescreen (16:9)"
        "9:16" = "Vertical (9:16)"
    }
    
    Write-Host "Crop ratio options:"
    foreach ($key in $CropOptions.Keys) {
        Write-Host "$key - $($CropOptions[$key])"
    }
    
    $CropRatio = Get-UserInput -Prompt "Select crop ratio" -Default "none" -Validator { param($v) $CropOptions.ContainsKey($v) }
}

# Get target size if not provided
if ([string]::IsNullOrEmpty($TargetSize)) {
    Write-Host "Target size options:"
    foreach ($key in $SizePresets.Keys | Sort-Object) {
        Write-Host "$key - $($SizePresets[$key])"
    }
    
    $TargetSize = Get-UserInput -Prompt "Select target size" -Default "original" -Validator { param($v) $SizePresets.ContainsKey($v) }
}

# Override quality to verylow if SmallestFile is specified
if ($SmallestFile) {
    $Quality = "verylow"
}

# Get quality if not valid
if (-not $QualityPresets.ContainsKey($Quality)) {
    Write-Host "Quality options:"
    foreach ($key in $QualityPresets.Keys) {
        Write-Host "$key - CRF: $($QualityPresets[$key])"
    }
    
    $Quality = Get-UserInput -Prompt "Select quality" -Default "medium" -Validator { param($v) $QualityPresets.ContainsKey($v) }
}

# Get the base name of the input file (without extension)
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)

# Construct the output file name with parameters
$OutputFile = "${BaseName}-edited"
if ($StartTime -gt 0) { $OutputFile += "-s${StartTime}" }
if ($Duration) { $OutputFile += "-d${Duration}" }
if ($SpeedModifier -ne 1.0) { $OutputFile += "-speed${SpeedModifier}" }
if ($Rotation -ne 0) { $OutputFile += "-r${Rotation}" }
if ($CropRatio -ne "none") { $OutputFile += "-crop${CropRatio.Replace(':', '')}" }
if ($TargetSize -ne "original") { $OutputFile += "-${TargetSize}" }
if ($Quality -ne "medium") { $OutputFile += "-q${Quality}" }
$OutputFile += ".mp4"

# Construct the ffmpeg filters
$Filters = @()

# Add rotation filter if needed
$IsVerticalRotation = $false
if ($Rotation -ne 0) {
    $RotateFilter = switch ($Rotation) {
        90 { 
            $IsVerticalRotation = $true
            "transpose=1" 
        } # 90 degrees clockwise
        180 { 
            "transpose=2,transpose=2" 
        } # 180 degrees
        270 { 
            $IsVerticalRotation = $true
            "transpose=2" 
        } # 90 degrees counterclockwise
        default { "" }
    }
    if ($RotateFilter) {
        $Filters += $RotateFilter
    }
}

# Add crop filter if needed
if ($CropRatio -ne "none") {
    # Extract width and height for crop calculations
    $CropFilter = switch ($CropRatio) {
        "1:1" { "crop=min(iw\,ih):min(iw\,ih)" } # Square crop
        "16:9" { "crop=iw:iw*9/16" } # 16:9 crop
        "9:16" { "crop=ih*9/16:ih" } # 9:16 crop
        default { "" }
    }
    if ($CropFilter) {
        $Filters += $CropFilter
    }
}

# Determine the size of the cropped video
if ($CropRatio -eq "1:1") {
    # Get video width and height
    $probe = ffprobe -v error -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 $InputFile
    $width = ($probe[0] -as [int])
    $height = ($probe[1] -as [int])

    # Determine the size of the cropped video
    $croppedSize = [Math]::Min($width, $height)
}

# Add scale filter based on target size
if ($TargetSize -ne "original" -and $CropRatio -eq "1:1") {
    $Dimensions = $SizePresets[$TargetSize] -split 'x'
    $TargetWidth = [int]$Dimensions[0]
    $TargetHeight = [int]$Dimensions[1]

    # If rotated by 90 or 270 degrees, swap width and height for the target
    if ($IsVerticalRotation) {
        $Temp = $TargetWidth
        $TargetWidth = $TargetHeight
        $TargetHeight = $Temp
        Write-Host "Swapping dimensions for vertical rotation: ${TargetWidth}x${TargetHeight}"
    }

    # Add scale filter ONLY if the target size is different from the cropped size
    if ($TargetWidth -ne $croppedSize -or $TargetHeight -ne $croppedSize) {
        $ScaleFilter = "scale=${TargetWidth}:${TargetHeight}:force_original_aspect_ratio=decrease,pad=${TargetWidth}:${TargetHeight}:(ow-iw)/2:(oh-ih)/2"
        $Filters += $ScaleFilter
    }
} elseif ($TargetSize -ne "original") {
     $Dimensions = $SizePresets[$TargetSize] -split 'x'
    $TargetWidth = [int]$Dimensions[0]
    $TargetHeight = [int]$Dimensions[1]
    $ScaleFilter = "scale=${TargetWidth}:${TargetHeight}:force_original_aspect_ratio=decrease,pad=${TargetWidth}:${TargetHeight}:(ow-iw)/2:(oh-ih)/2"
    $Filters += $ScaleFilter
}

# Add FPS and speed filter
$Filters += "fps=24"
if ($SpeedModifier -ne 1.0) {
    $Filters += "setpts=PTS/$SpeedModifier"
}

# Join all filters
$FilterString = $Filters -join ","

# Get CRF value from quality preset
$CRF = $QualityPresets[$Quality]

# Additional compression options for smallest file
$AdditionalOptions = ""
if ($SmallestFile) {
    # For smallest file, we'll reduce bitrate and use simpler encoding options
    $AdditionalOptions = "-b:v 500k -maxrate 500k -bufsize 1000k -preset veryslow"
    Write-Host "Using smallest file settings with maxrate 500k and veryslow preset"
} else {
    # Default to faster preset for normal usage
    $AdditionalOptions = "-preset faster"
}

# Construct the ffmpeg command
$Command = "ffmpeg -ss $StartTime"
if ($Duration) {
    $Command += " -t $Duration"
}
$Command += " -i `"$InputFile`" -vf `"$FilterString`" -c:v libx264 $AdditionalOptions -crf $CRF"

# Add audio settings based on quality
if ($Quality -eq "verylow" -or $SmallestFile) {
    $Command += " -ac 1 -b:a 64k"  # Mono audio at low bitrate
} else {
    $Command += " -c:a aac -b:a 128k"  # Default audio
}

$Command += " `"$OutputFile`""

# Display and execute the command
Write-Host "Executing ffmpeg with quality: $Quality (CRF: $CRF)"
Write-Host "Command: $Command"
Invoke-Expression $Command

# Check if the output file was created
if (Test-Path $OutputFile) {
    $OriginalSize = (Get-Item $InputFile).Length / 1MB
    $NewSize = (Get-Item $OutputFile).Length / 1MB
    $ReductionPercent = [math]::Round((1 - ($NewSize / $OriginalSize)) * 100, 2)
    
    Write-Host "Video created successfully: $OutputFile"
    Write-Host "Original size: $([math]::Round($OriginalSize, 2)) MB"
    Write-Host "New size: $([math]::Round($NewSize, 2)) MB"
    Write-Host "Size reduction: $ReductionPercent%"
} else {
    Write-Error "Failed to create video"
}