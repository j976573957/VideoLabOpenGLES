precision highp float;

uniform sampler2D inputImageTexture;
varying vec2 textureCoordinate;

void main (void) {
    vec4 mask = texture2D(inputImageTexture, textureCoordinate);
    gl_FragColor = vec4(mask.rgb, 1.0);
}
