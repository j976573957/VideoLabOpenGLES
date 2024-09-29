attribute vec3 position;
attribute vec4 inputTextureCoordinate;
attribute vec4 inputTextureCoordinate2;

varying vec2 textureCoordinate;
varying vec2 textureCoordinate2;

uniform mat4 projection;
uniform mat4 modelView;

void main()
{
    gl_Position = projection * modelView * vec4(position, 1.0);
    textureCoordinate = inputTextureCoordinate.xy;
    textureCoordinate2 = inputTextureCoordinate2.xy;
}
