#include <metal_stdlib>
using namespace metal;

// Mathematical test scene, not AI footage or a depiction of canon assets.
// One compute thread produces one output pixel. No external images or services.
static float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float band(float d, float width) { return exp(-abs(d) * width); }
kernel void forgePOCFrame(texture2d<float, access::write> out [[texture(0)]],
                          constant float &time [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    float2 uv = (float2(gid) + 0.5) / float2(out.get_width(), out.get_height());
    float2 p = (uv - 0.5) * float2(float(out.get_width()) / out.get_height(), 1.0);
    float3 color = mix(float3(0.012, 0.025, 0.070), float3(0.022, 0.105, 0.15), uv.y);
    float2 starPos = p + float2(time * 0.005, time * 0.002);
    float2 cell = floor(starPos * 180.0);
    float2 local = fract(starPos * 180.0) - 0.5;
    float seed = hash21(cell);
    if (seed > 0.986) color += float3(0.5, 0.8, 1.0) * exp(-dot(local, local) * 35.0) *
        (0.55 + 0.45 * sin(time * 0.9 + seed * 200.0));
    float2 center = float2(0.16 + 0.025 * sin(time * 0.55), -0.04);
    float2 q = p - center;
    float r = length(q);
    float planetRadius = 0.232;
    if (r < planetRadius) {
        float z = sqrt(max(planetRadius * planetRadius - r * r, 0.0)) / planetRadius;
        float3 normal = normalize(float3(q / planetRadius, z));
        float shade = clamp(dot(normal, normalize(float3(-0.5, -0.5, 0.8))), 0.04, 1.0);
        float stripes = 0.5 + 0.5 * sin(q.y * 135.0 + sin(q.x * 50.0 + time * 0.7) * 2.0);
        color = mix(float3(0.015, 0.12, 0.19), float3(0.06, 0.43, 0.52), stripes) * shade;
        color += pow(1.0 - z, 3.0) * float3(0.08, 0.35, 0.5);
    }
    color += band(r - planetRadius, 160.0) * float3(0.01, 0.23, 0.38);
    float angle = -0.23 + time * 0.027;
    float2 orbit = float2(cos(angle) * q.x - sin(angle) * q.y, sin(angle) * q.x + cos(angle) * q.y);
    float ellipse = length(orbit * float2(1.0, 3.5));
    if (orbit.y > 0.0 || r > planetRadius) {
        color += band(ellipse - 0.40, 200.0) * float3(0.2, 0.85, 0.92);
        color += band(ellipse - 0.43, 170.0) * float3(0.045, 0.28, 0.42);
        float theta = atan2(orbit.y * 3.5, orbit.x);
        float pulse = pow(max(0.0, cos(theta - time * 1.3)), 70.0);
        color += band(ellipse - 0.40, 100.0) * pulse * float3(0.6, 0.85, 0.9);
    }
    float horizon = 0.23;
    if (p.y > horizon) {
        float depth = 0.13 / (p.y - horizon + 0.035);
        float gx = abs(fract(p.x * depth * 4.0 + 0.5) - 0.5);
        float gy = abs(fract(depth - time * 0.5 + 0.5) - 0.5);
        float grid = exp(-gx * 110.0) + exp(-gy * 75.0);
        color += grid * (p.y - horizon) * float3(0.02, 0.36, 0.48);
    }
    float scan = band(uv.x - fract(time * 0.14), 170.0);
    color += scan * 0.08 * float3(0.2, 0.7, 0.85);
    float vignette = 1.0 - 0.30 * smoothstep(0.15, 0.8, length(p));
    out.write(float4(clamp(color * vignette, 0.0, 1.0), 1.0), gid);
}
