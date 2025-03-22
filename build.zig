const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");

// Project settings
const PROJECT_NAME = "LearningSokol";
const SOKOL_TOOLS_BIN_DIR = "./tools/sokol-tools-bin/bin/";
const SLANG = "glsl410:glsl300es:metal_macos:hlsl5:wgsl";
const SHADERS_SRC_DIR = "./src/shaders/";
const SHADERS_BUILD_DIR = "./src/shaders/build/";
const SHADERS = .{
    .{ .src = "test-shader.glsl" },
};

// Declaratively construct a build graph that will be executed by an external runner
pub fn build(b: *std.Build) void {
    // Allow the person running `zig build` to choose target platform and optimization mode
    // Optimization modes - `Debug, `ReleaseSafe`, `ReleaseFast`, and `ReleaseSmall`
    // Default target is native platform with no optimizations
    const target: std.Build.ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});

    // Dependencies
    const sokolDep: *std.Build.Dependency = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });
    const cimguiDep: *std.Build.Dependency = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });
    const zmathDep: *std.Build.Dependency = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });

    // Inject the Cimgui header search path into the Sokol C library compile step
    sokolDep.artifact("sokol_clib").addIncludePath(cimguiDep.path("src"));

    // Modules
    const mainMod: *std.Build.Module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = sokolDep.module("sokol") },
            .{ .name = "cimgui", .module = cimguiDep.module("cimgui") },
            .{ .name = "zmath", .module = zmathDep.module("root") },
        },
    });

    // A manually invoked build step to compile all shaders
    buildShaders(b, target);

    // Handle native and web builds
    if (target.result.cpu.arch.isWasm()) {
        try buildWeb(b, mainMod, sokolDep, cimguiDep);
    } else {
        try buildNative(b, mainMod);
    }
}

// Build for native platform
fn buildNative(b: *std.Build, mainMod: *std.Build.Module) !void {
    // Build an executable
    const exe = b.addExecutable(.{
        .name = PROJECT_NAME,
        .root_module = mainMod,
    });

    // Install the executable into the standard location when `install` step is invoked
    b.installArtifact(exe);

    // Run step
    const runCmd = b.addRunArtifact(exe);
    runCmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        runCmd.addArgs(args);
    }
    const runStep = b.step("run", "Run program");
    runStep.dependOn(&runCmd.step);
}

// Build for web - The Zig code needs to be built into a library and linked with the Emscripten linker
fn buildWeb(b: *std.Build, mainMod: *std.Build.Module, sokolDep: *std.Build.Dependency, cimguiDep: *std.Build.Dependency) !void {
    // Build a static library
    const lib = b.addStaticLibrary(.{
        .name = PROJECT_NAME,
        .root_module = mainMod,
    });

    // Dependencies
    const emsdkDep: *std.Build.Dependency = sokolDep.builder.dependency("emsdk", .{});

    // Inject the Emscripten system header include path into the Cimgui C library
    // Else the C/C++ code won't find the C stdlib headers
    const emsdkIncludePath = emsdkDep.path("upstream/emscripten/cache/sysroot/include");
    cimguiDep.artifact("cimgui_clib").addSystemIncludePath(emsdkIncludePath);

    // All C libraries must depend on the Sokol library
    // Ensures that the Emscripten SDK has been set up before C compilation is attempted
    // since the Sokol C library depends on the Emscripten SDK setup step
    cimguiDep.artifact("cimgui_clib").step.dependOn(&sokolDep.artifact("sokol_clib").step);

    // Build step invoking the Emscripten linker
    const linkStep = try sokol.emLinkStep(b, .{
        .lib_main = lib,
        .target = mainMod.resolved_target.?,
        .optimize = mainMod.optimize.?,
        .emsdk = emsdkDep,
        .use_webgpu = true,
        .use_webgl2 = false,
        .use_emmalloc = true,
        .use_filesystem = false,
        .shell_file_path = sokolDep.path("src/sokol/web/shell.html"),
    });

    // Special run step to start the web build output via `emrun`
    const run = sokol.emRunStep(b, .{ .name = "lib", .emsdk = emsdkDep });
    run.step.dependOn(&linkStep.step);
    b.step("run", "Run lib").dependOn(&run.step);
}

// Build step to compile all shaders
fn buildShaders(b: *std.Build, target: std.Build.ResolvedTarget) void {
    // Figure out which Sokol SHDC binary to use
    const optionalShdc: ?[:0]const u8 = comptime switch (builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => if (target.result.cpu.arch.isX86()) "linux/sokol-shdc" else "linux_arm64/sokol-shdc",
        .macos => if (target.result.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => null,
    };

    // If there's no Sokol SHDC binary for the host platform
    if (optionalShdc == null) {
        std.log.warn("Unsupported host platform, skipping shader compilation", .{});
        return;
    }

    // Compile all shaders
    const shdcPath = SOKOL_TOOLS_BIN_DIR ++ optionalShdc.?;
    const shdcStep = b.step("shaders", "Compile shaders");
    inline for (SHADERS) |shader| {
        const cmd = b.addSystemCommand(&.{
            shdcPath,
            "--input=",
            SHADERS_SRC_DIR ++ shader.src,
            "--output=",
            SHADERS_BUILD_DIR ++ shader.src ++ ".zig",
            "--SLANG=",
            SLANG,
            "--format=sokol_zig",
            "--reflection",
        });
        shdcStep.dependOn(&cmd.step);
    }
}
