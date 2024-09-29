precision highp float;
varying highp vec2 textureCoordinate;
varying highp vec2 textureCoordinate2;

uniform sampler2D inputImageTexture;
uniform sampler2D inputImageTexture2;
uniform float blendOpacity;

vec4 normalBlend(vec3 Sca, vec3 Dca, float Sa, float Da) {
    vec4 blendColor;
    blendColor.rgb = Sca + Dca * (1.0 - Sa);
    blendColor.a = Sa + Da - Sa * Da;
    return blendColor;
}

void main()
{
    lowp vec4 sourceColor = texture2D(inputImageTexture, textureCoordinate);
    lowp vec4 outputColor = texture2D(inputImageTexture2, textureCoordinate2);
    lowp vec4 blendColor;

    blendColor = normalBlend(sourceColor.rgb, outputColor.rgb, sourceColor.a, outputColor.a);
    
    gl_FragColor = mix(outputColor, blendColor, blendOpacity);
}
