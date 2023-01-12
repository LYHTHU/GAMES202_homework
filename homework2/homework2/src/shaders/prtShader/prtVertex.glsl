attribute vec3 aVertexPosition;
attribute vec3 aNormalPosition;
attribute vec2 aTextureCoord;

uniform mat4 uModelMatrix;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;
uniform mat4 uLightMVP;

attribute mat3 aPrecomputeLT;
uniform mat3 aPrecomputeLR;
uniform mat3 aPrecomputeLG;
uniform mat3 aPrecomputeLB;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;
varying highp vec3 vColor;

const float kd = 2.0;
const float pi = 3.14159;

float mat_element_dot(mat3 a, mat3 b) {
    return dot(a[0], b[0]) + dot(a[1], b[1]) + dot(a[2], b[2]);
}


void main(void) {
    vFragPos = (uModelMatrix * vec4(aVertexPosition, 1.0)).xyz;
    vNormal = (uModelMatrix * vec4(aNormalPosition, 0.0)).xyz;
    // Calc vColor via aPrecomputeL* and SH cooefs(aPrecomputeLT).
    float r = mat_element_dot(aPrecomputeLR, aPrecomputeLT);
    float g = mat_element_dot(aPrecomputeLG, aPrecomputeLT);
    float b = mat_element_dot(aPrecomputeLB, aPrecomputeLT);
    // vColor = vec3(r, g, b) * kd / pi;
    vColor = vec3(r, g, b);
    vTextureCoord = aTextureCoord;
    gl_Position = uProjectionMatrix * uViewMatrix * uModelMatrix *
                vec4(aVertexPosition, 1.0);
}