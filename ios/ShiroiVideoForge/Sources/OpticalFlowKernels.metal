#include <metal_stdlib>
using namespace metal;

kernel void opticalFlowWarpBlend(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::sample> target [[texture(1)]],
    texture2d<float, access::sample> flow [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    constant float &progress [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    constexpr sampler imageSampler(coord::pixel, address::clamp_to_edge, filter::linear);
    constexpr sampler flowSampler(coord::pixel, address::clamp_to_edge, filter::linear);

    const float t = clamp(progress, 0.0f, 1.0f);
    const float2 pixel = float2(gid) + 0.5f;
    const float2 motion = flow.sample(flowSampler, pixel).xy;

    // Vision optical flow is measured in pixels. Approximate a bidirectional
    // intermediate by warping each endpoint toward the same temporal position.
    const float2 sourceCoordinate = pixel - motion * t;
    const float2 targetCoordinate = pixel + motion * (1.0f - t);

    const float4 a = source.sample(imageSampler, sourceCoordinate);
    const float4 b = target.sample(imageSampler, targetCoordinate);
    const float smoothT = t * t * (3.0f - 2.0f * t);
    output.write(mix(a, b, smoothT), gid);
}
