precision highp float;

uniform sampler2D inputImageTexture;
uniform sampler2D inputImageTexture2;
uniform mat3 colorConversionMatrix;

varying vec2 textureCoordinate;

void main (void) {
    vec3 yuv = vec3(0.0, 0.0, 0.0);
    vec3 rgb = vec3(0.0, 0.0, 0.0);
    //上周变换后视频颜色变暗的原因是：没有减去 (16.0/255.0)
    yuv.x = texture2D(inputImageTexture, textureCoordinate).r - (16.0/255.0);
    yuv.yz = texture2D(inputImageTexture2, textureCoordinate).ra - vec2(0.5, 0.5);
    rgb = colorConversionMatrix * yuv;
    
    gl_FragColor = vec4(rgb, 1.0);
}
