# Constants
$SOKOL_SHDC = ".\tools\sokol-tools-bin\bin\win32\sokol-shdc.exe"
$SHADER_SRC_DIR = ".\src\shaders"
$SHADER_BUILD_DIR = ".\src\shaders\build"
$SHADER_LANG = "glsl430:wgsl:hlsl5:metal_macos"
$SHADER_EXTENSION = "*.glsl"

# Create shader build directory if it doesn't exist
if(-not (Test-Path $SHADER_BUILD_DIR)) {
    New-Item -ItemType Directory -Path $SHADER_BUILD_DIR
    Write-Output "Created output directory: $SHADER_BUILD_DIR"
}

# Compile all shaders
$shaderFiles = Get-ChildItem -Path $SHADER_SRC_DIR -Filter $SHADER_EXTENSION
foreach ($shader in $shaderFiles) {
    $inputFile = $shader.FullName
    $outputFile = Join-Path -Path $SHADER_BUILD_DIR -ChildPath ($shader.BaseName + ".zig")

    # Compile shader
	& "$SOKOL_SHDC" `
		--input="$inputFile" `
		--output="$outputFile" `
		--slang="$SHADER_LANG" `
		--format=sokol_zig `
		--bytecode

    Write-Output "Compiling $inputFile..."
}

# Finished compiling shaders
Write-Output "All shaders compiled"
