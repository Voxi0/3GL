# Variables
$toolsDir = ".\tools"

# Check if folder exists, then delete it before recreating it
if (Test-Path $toolsDir) {
    Remove-Item -Path $toolsDir -Recurse -Force
    Write-Output "Folder deleted: $toolsDir"
	New-Item -ItemType Directory -Path $toolsDir
	Write-Output "Folder recreated: $toolsDir"
} else {
    Write-Output "Folder not found: $toolsDir"
}

# Fetch dependencies
Set-Location -Path $toolsDir
git clone https://github.com/floooh/sokol-tools-bin

# Finished fetching all dependencies
Write-Output "Fetched all dependencies..."
