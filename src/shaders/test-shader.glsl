#version 430 core
@ctype mat4 [4][4]f32

@vs vs
// Uniform variables
layout(binding=0) uniform vs_params {
    mat4 pvm;
};

// Input
in vec4 position, color0;

// Output
out vec4 color;

// Main
void main(void) {
    // Calculate and set final vertex position
    gl_Position = pvm * position;

    // Send vertex color to fragment shader
    color = color0;
}
@end

// Fragment shader
@fs fs
// Input
in vec4 color;

// Output
out vec4 fragColor;

// Main
void main(void) {
    // Set final fragment color
    fragColor = color;
}
@end

// Create shader program
@program triangle vs fs
