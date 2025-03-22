// Standard library
const std = @import("std");

// Sokol
const sokol = @import("sokol");
const keycode = @import("sokol").app.Keycode;

// 3D maths library
const zmath = @import("zmath");

// Private variables
var yaw: f32 = -90;
var pitch: f32 = 0;

// Camera
pub const Camera3D = struct {
    // Properties
    position: zmath.Vec,
    front: zmath.Vec,
    up: zmath.Vec = .{ 0, 1, 0, 0 },

    fov: f32,
    minFov: f32,
    maxFov: f32,

    moveSpeed: f32,
    lookSpeed: f32,

    // Methods
    // Get view matrix
    pub fn getViewMat(self: *Camera3D) zmath.Mat {
        return zmath.lookAtRh(
            self.position,
            self.position + self.front,
            self.up,
        );
    }

    // Process keyboard input to move around
    pub fn processKb(self: *Camera3D, event: sokol.app.Event, deltaTime: f32) void {
        if (event.type == sokol.app.EventType.KEY_DOWN) {
            if (event.key_code == keycode.W) {
                self.position += self.front * zmath.f32x4s(self.moveSpeed * deltaTime);
            }
            if (event.key_code == keycode.S) {
                self.position -= self.front * zmath.f32x4s(self.moveSpeed * deltaTime);
            }
            if (event.key_code == keycode.A) {
                self.position -= zmath.normalize4(zmath.cross3(self.front, self.up)) *
                    zmath.f32x4s(self.moveSpeed * deltaTime);
            }
            if (event.key_code == keycode.D) {
                self.position += zmath.normalize4(zmath.cross3(self.front, self.up)) *
                    zmath.f32x4s(self.moveSpeed * deltaTime);
            }
        }
    }

    // Process mouse movement to look around
    pub fn processMouse(self: *Camera3D, event: sokol.app.Event) void {
        if (event.type == sokol.app.EventType.MOUSE_MOVE) {
            // Update camera yaw and pitch
            yaw += event.mouse_dx * self.lookSpeed;
            pitch += -event.mouse_dy * self.lookSpeed;

            // Constrain camera pitch to stop it from rotating 360 degrees vertically
            if (pitch < -89) pitch = -89;
            if (pitch > 89) pitch = 89;

            // Calculate and set new camera direction
            const dir: zmath.Vec = .{
                zmath.cos(std.math.degreesToRadians(yaw)) * zmath.cos(std.math.degreesToRadians(pitch)),
                zmath.sin(std.math.degreesToRadians(pitch)),
                zmath.sin(std.math.degreesToRadians(yaw)) * zmath.cos(std.math.degreesToRadians(pitch)),
                0,
            };
            self.front = zmath.normalize4(dir);
        }
    }

    // Process mouse scroll to zoom in/out
    pub fn processMouseScroll(self: *Camera3D, event: sokol.app.Event) void {
        if (event.type == sokol.app.EventType.MOUSE_SCROLL) {
            self.fov += event.scroll_y;
            if (self.fov < self.minFov) self.fov = self.minFov;
            if (self.fov > self.maxFov) self.fov = self.maxFov;
        }
    }
};
