// Standard library
const std = @import("std");

// Sokol
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;

// Dear ImGUI for UI
const ig = @import("cimgui");

// 3D maths library
const zmath = @import("zmath");

// Engine
const cam = @import("camera.zig");

// Shaders
const testShadersSrc = @import("./shaders/build/test-shader.glsl.zig");

// Settings
const winTitle = "LearningSokol";
const winDefaultIcon: bool = true;
const winWidth: u16 = 800;
const winHeight: u16 = 600;
const sampleCount: u16 = 4;

// Render state
const RenderState = struct {
    passAction: sg.PassAction,
    pipeline: sg.Pipeline,
    bindings: sg.Bindings,
    camera: cam.Camera3D,
};
var renderState: RenderState = undefined;

// Model, view and projection matrices
var modelMatrix: zmath.Mat = zmath.identity();
var projectionMatrix: zmath.Mat = zmath.identity();
var pvm: zmath.Mat = zmath.identity();

// Initialize everything
export fn init() void {
    // Initialize Sokol
    sokol.time.setup();
    sg.setup(.{
        .logger = .{ .func = sokol.log.func },
        .environment = sokol.glue.environment(),
    });
    simgui.setup(.{
        .logger = .{ .func = sokol.log.func },
        .sample_count = sampleCount,
    });

    // Initialize render pass action
    renderState.passAction.colors[0] = .{
        .load_action = sg.LoadAction.CLEAR,
        .clear_value = sg.Color{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 },
    };

    // Lock the mouse and create the camera
    renderState.camera = .{
        .position = zmath.Vec{ 0, 0, 5, 0 },
        .front = zmath.Vec{ 0, 0, -1, 0 },

        .fov = 60,
        .minFov = 0.1,
        .maxFov = 120,

        .moveSpeed = 5,
        .lookSpeed = 0.3,
    };

    // Test object with vertex positions and colors
    const vertices: [168]f32 = [168]f32{
        -1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
        1.0,  -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
        1.0,  1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,
        -1.0, 1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,

        -1.0, -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
        1.0,  -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
        1.0,  1.0,  1.0,  0.0, 1.0, 0.0, 1.0,
        -1.0, 1.0,  1.0,  0.0, 1.0, 0.0, 1.0,

        -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0,
        -1.0, 1.0,  -1.0, 0.0, 0.0, 1.0, 1.0,
        -1.0, 1.0,  1.0,  0.0, 0.0, 1.0, 1.0,
        -1.0, -1.0, 1.0,  0.0, 0.0, 1.0, 1.0,

        1.0,  -1.0, -1.0, 1.0, 0.5, 0.0, 1.0,
        1.0,  1.0,  -1.0, 1.0, 0.5, 0.0, 1.0,
        1.0,  1.0,  1.0,  1.0, 0.5, 0.0, 1.0,
        1.0,  -1.0, 1.0,  1.0, 0.5, 0.0, 1.0,

        -1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,
        -1.0, -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
        1.0,  -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
        1.0,  -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,

        -1.0, 1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
        -1.0, 1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
        1.0,  1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
        1.0,  1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
    };
    const indices: [36]u16 = [36]u16{
        0,  1,  2,  0,  2,  3,
        6,  5,  4,  7,  6,  4,
        8,  9,  10, 8,  10, 11,
        14, 13, 12, 15, 14, 12,
        16, 17, 18, 16, 18, 19,
        22, 21, 20, 23, 22, 20,
    };

    // Vertex buffers
    var bufferDesc = std.mem.zeroes(sg.BufferDesc);
    bufferDesc.type = sg.BufferType.VERTEXBUFFER;
    bufferDesc.size = vertices.len * @sizeOf(f32);
    bufferDesc.data = .{ .ptr = &vertices[0], .size = bufferDesc.size };
    renderState.bindings.vertex_buffers[0] = sg.makeBuffer(bufferDesc);

    // Index/Element buffers
    bufferDesc = std.mem.zeroes(sg.BufferDesc);
    bufferDesc.type = sg.BufferType.INDEXBUFFER;
    bufferDesc.size = indices.len * @sizeOf(u16);
    bufferDesc.data = .{ .ptr = &indices[0], .size = bufferDesc.size };
    renderState.bindings.index_buffer = sg.makeBuffer(bufferDesc);

    // Shaders
    const testShaders = sg.makeShader(testShadersSrc.triangleShaderDesc(sg.queryBackend()));

    // Pipeline
    var pipelineDesc: sg.PipelineDesc = .{
        .shader = testShaders,
        .index_type = sg.IndexType.UINT16,
        .cull_mode = sg.CullMode.BACK,
        .depth = .{
            .compare = sg.CompareFunc.LESS_EQUAL,
            .write_enabled = true,
        },
    };
    pipelineDesc.layout.attrs[testShadersSrc.ATTR_triangle_position].format = sg.VertexFormat.FLOAT3;
    pipelineDesc.layout.attrs[testShadersSrc.ATTR_triangle_color0].format = sg.VertexFormat.FLOAT4;
    pipelineDesc.layout.buffers[0].stride = 28;
    renderState.pipeline = sg.makePipeline(pipelineDesc);
}

// Update and render everything
export fn event(ev: [*c]const sokol.app.Event) void {
    // Forward input events to Sokol ImGUI
    _ = simgui.handleEvent(ev.*);

    // Handle keyboard input for input
    renderState.camera.processKb(ev.*, @as(f32, @floatCast(sokol.app.frameDuration())));

    // Handle mouse movement to look around
    renderState.camera.processMouse(ev.*);

    // Handle mouse scroll to zoom in/out
    renderState.camera.processMouseScroll(ev.*);

    // Quit application when Escape key pressed
    if (ev.*.key_code == sokol.app.Keycode.ESCAPE) sokol.app.requestQuit();
}
export fn update() void {
    // Update the projection matrix
    projectionMatrix = zmath.perspectiveFovRhGl(
        std.math.degreesToRadians(renderState.camera.fov),
        sokol.app.widthf() / sokol.app.heightf(),
        0.1,
        100,
    );

    // Calculate the product of the projection, view and model matrices in the respective order
    // We multiply the model matrix again whenever it's changed in some way
    pvm = zmath.mul(renderState.camera.getViewMat(), projectionMatrix);

    // UI
    {
        // Create new ImGUI frame
        simgui.newFrame(.{
            .width = sokol.app.width(),
            .height = sokol.app.height(),
            .delta_time = sokol.app.frameDuration(),
            .dpi_scale = sokol.app.dpiScale(),
        });

        // Window settings
        ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);

        // Settings window
        {
            // Begin/End new window
            _ = ig.igBegin("Settings", 0, ig.ImGuiWindowFlags_None);
            defer ig.igEnd();

            // Color picker
            _ = ig.igColorEdit3(
                "Background",
                &renderState.passAction.colors[0].clear_value.r,
                ig.ImGuiColorEditFlags_None,
            );
        }
    }

    // Begin/End render pass and submit frame
    sg.beginPass(.{ .swapchain = sokol.glue.swapchain(), .action = renderState.passAction });
    defer sg.commit();
    defer sg.endPass();

    // Render the UI - Deferred to render on top of everyting else because, it's the UI
    defer simgui.render();

    // Render test object
    {
        // Transoformations
        modelMatrix = zmath.identity();
        pvm = zmath.mul(pvm, modelMatrix);

        // Prepare to render test object
        sg.applyPipeline(renderState.pipeline);
        sg.applyBindings(renderState.bindings);
        sg.applyUniforms(0, sg.Range{
            .size = @sizeOf(testShadersSrc.VsParams),
            .ptr = &testShadersSrc.VsParams{ .pvm = pvm },
        });

        // Render test object
        sg.draw(0, 36, 1);
    }
}

// Deinitialize everything
export fn deinit() void {
    simgui.shutdown();
    sg.shutdown();
}

// Main - Run the application
pub fn main() void {
    sokol.app.run(.{
        // Window configuration
        .icon = .{ .sokol_default = winDefaultIcon },
        .window_title = winTitle,
        .width = winWidth,
        .height = winHeight,
        .fullscreen = true,
        .sample_count = sampleCount,

        // Provide function pointers for various things
        .init_cb = init,
        .frame_cb = update,
        .event_cb = event,
        .cleanup_cb = deinit,

        // Configure extras
        .enable_clipboard = true,
    });
}
