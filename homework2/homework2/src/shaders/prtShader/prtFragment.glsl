varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;
varying highp vec3 vColor;

void main(void) {
    gl_FragColor = vec4(vColor, 1.0);
}