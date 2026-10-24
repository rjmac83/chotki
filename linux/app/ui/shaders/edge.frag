// Baked with qsb --qt6 --qsbversion 64 so the Ubuntu 24.04 CI (Qt 6.4) can load it.
#version 440

// Fades the scroll viewport into the real backdrop. A painted gradient cannot
// match the radial wash, and a stop named "transparent" fades through black.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float edge;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float band = edge;
    if (!(band > 0.008 && band < 0.16))
        band = 0.035;
    float y = qt_TexCoord0.y;
    float fade = smoothstep(0.0, band, y) * (1.0 - smoothstep(1.0 - band, 1.0, y));
    fragColor = texture(source, qt_TexCoord0) * fade * qt_Opacity;
}
