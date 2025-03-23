const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");

// Project settings
const PROJECT_NAME = "LearningSokol";
const PROJECT_VERSION: std.SemanticVersion = .{
    .major = 0,
    .minor = 1,
    .patch = 0,
};
const PROJECT_ZIG_DEPENDENCIES = .{
    .{ .name = "sokol", .src = "git+https://github.com/floooh/sokol-zig.git" },
    .{ .name = "zmath", .src = "git+https://github.com/zig-gamedev/zmath.git" },
    .{ .name = "cimgui", .src = "git+https://github.com/floooh/dcimgui.git" },
};

// Shaders
const SOKOL_TOOLS_BIN_DIR = "./sokol-tools-bin/";
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

    // Options
    const options: *std.Build.Step.Options = b.addOptions();
    options.addOption([]const u8, "PROJECT_NAME", PROJECT_NAME);
    mainMod.addOptions("config", options);

    // Add manually invoked build steps
    buildShaders(b, target);
    fetchDeps(b);
    clean(b);

    // Handle native and web builds
    if (target.result.cpu.arch.isWasm()) {
        try buildWeb(b, mainMod, sokolDep, cimguiDep);
    } else try buildNative(b, mainMod);

    // Run unit tests
    const unitTests = b.addTest(.{ .root_module = mainMod });
    const runUnitTests = b.addRunArtifact(unitTests);
    const testStep = b.step("tests", "Run unit tests");
    testStep.dependOn(&runUnitTests.step);
}

// Build for native platform
fn buildNative(b: *std.Build, mainMod: *std.Build.Module) !void {
    // Build an executable
    const exe = b.addExecutable(.{
        .name = PROJECT_NAME,
        .version = PROJECT_VERSION,
        .root_module = mainMod,
    });

    // Install the executable into the standard location when `install` step is invoked
    b.installArtifact(exe);

    // Run step
    const runCmd = b.addRunArtifact(exe);
    runCmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| runCmd.addArgs(args);
    const runStep = b.step("run", "Run program");
    runStep.dependOn(&runCmd.step);
}

// Build for web - The Zig code needs to be built into a library and linked with the Emscripten linker
fn buildWeb(b: *std.Build, mainMod: *std.Build.Module, sokolDep: *std.Build.Dependency, cimguiDep: *std.Build.Dependency) !void {
    // Build a static library
    const lib = b.addStaticLibrary(.{
        .name = PROJECT_NAME,
        .version = PROJECT_VERSION,
        .root_module = mainMod,
    });

    // Dependencies
    const emsdkDep: *std.Build.Dependency = sokolDep.builder.dependency("emsdk", .{});

    // Inject the Emscripten system header include path into the Cimgui C library
    // Or else the C/C++ code won't find the C stdlib headers
    const emsdkIncludePath = emsdkDep.path("upstream/emscripten/cache/sysroot/include");
    cimguiDep.artifact("cimgui_clib").addSystemIncludePath(emsdkIncludePath);

    // All C libraries must depend on the Sokol library
    // Ensures that the Emscripten SDK has been set up before C compilation is attempted
    // Since the Sokol C library depends on the Emscripten SDK setup step
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
    const run = sokol.emRunStep(b, .{
        .name = "lib",
        .emsdk = emsdkDep,
    });
    run.step.dependOn(&linkStep.step);
    b.step("run", "Run lib").dependOn(&run.step);
}

// Build steps
// To compile all shaders
fn buildShaders(b: *std.Build, target: std.Build.ResolvedTarget) void {
    // Figure out which Sokol SHDC binary to use
    const optionalShdc: ?[:0]const u8 = comptime switch (builtin.os.tag) {
        .windows => "bin/win32/sokol-shdc.exe",
        .linux => if (target.result.cpu.arch.isX86()) "bin/linux/sokol-shdc" else "bin/linux_arm64/sokol-shdc",
        .macos => if (target.result.cpu.arch.isX86()) "bin/osx/sokol-shdc" else "bin/osx_arm64/sokol-shdc",
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
            "--slang=",
            SLANG,
            "--format=sokol_zig",
            "--reflection",
        });
        shdcStep.dependOn(&cmd.step);
    }
}

// To fetch all dependencies
fn fetchDeps(b: *std.Build) void {
    // Fetch all Zig dependencies
    const fetchDepsStep = b.step("fetchDeps", "Fetch all dependencies");
    inline for (PROJECT_ZIG_DEPENDENCIES) |dependency| {
        const cmd = b.addSystemCommand(&.{
            "zig", "fetch", "--save=" ++ dependency.name, dependency.src,
        });
        fetchDepsStep.dependOn(&cmd.step);
    }

    // Fetch Sokol SHDC (Shader compiler) if it doesn't exist, update it if otherwise
    const fetchSokolShdcCmd = b.addSystemCommand(&.{
        "git", "clone", "https://github.com/floooh/sokol-tools-bin", SOKOL_TOOLS_BIN_DIR,
    });
    const updateSokolShdcCmd = b.addSystemCommand(&.{
        "git", "-C", SOKOL_TOOLS_BIN_DIR, "pull", "--ff-only",
    });
    if (std.fs.cwd().openDir(SOKOL_TOOLS_BIN_DIR, .{})) |_| {
        fetchDepsStep.dependOn(&updateSokolShdcCmd.step);
    } else |_| fetchDepsStep.dependOn(&fetchSokolShdcCmd.step);
}
