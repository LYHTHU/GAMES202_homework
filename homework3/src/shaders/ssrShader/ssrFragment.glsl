#ifdef GL_ES
precision highp float;
#endif

uniform vec3 uLightDir;
uniform vec3 uCameraPos; // camera position
uniform vec3 uLightRadiance;
uniform sampler2D uGDiffuse;
uniform sampler2D uGDepth;
uniform sampler2D uGNormalWorld;
uniform sampler2D uGShadow;
uniform sampler2D uGPosWorld;

varying mat4 vWorldToScreen;
varying highp vec4 vPosWorld;

#define M_PI 3.1415926535897932384626433832795
#define TWO_PI 6.283185307
#define INV_PI 0.31830988618
#define INV_TWO_PI 0.15915494309
#define MAX_STEP 100

float Rand1(inout float p) {
  p = fract(p * .1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

vec2 Rand2(inout float p) {
  return vec2(Rand1(p), Rand1(p));
}

float InitRand(vec2 uv) {
	vec3 p3  = fract(vec3(uv.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 SampleHemisphereUniform(inout float s, out float pdf) {
  vec2 uv = Rand2(s);
  float z = uv.x;
  float phi = uv.y * TWO_PI;
  float sinTheta = sqrt(1.0 - z*z);
  vec3 dir = vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
  pdf = INV_TWO_PI;
  return dir;
}

vec3 SampleHemisphereCos(inout float s, out float pdf) {
  vec2 uv = Rand2(s);
  float z = sqrt(1.0 - uv.x);
  float phi = uv.y * TWO_PI;
  float sinTheta = sqrt(uv.x);
  vec3 dir = vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
  pdf = z * INV_PI;
  return dir;
}

void LocalBasis(vec3 n, out vec3 b1, out vec3 b2) {
  float sign_ = sign(n.z);
  if (n.z == 0.0) {
    sign_ = 1.0;
  }
  float a = -1.0 / (sign_ + n.z);
  float b = n.x * n.y * a;
  b1 = vec3(1.0 + sign_ * n.x * n.x * a, sign_ * b, -sign_ * n.x);
  b2 = vec3(b, sign_ + n.y * n.y * a, -n.y);
}

vec4 Project(vec4 a) {
  return a / a.w;
}

float GetDepth(vec3 posWorld) {
  float depth = (vWorldToScreen * vec4(posWorld, 1.0)).w;
  return depth;
}

/*
 * Transform point from world space to screen space([0, 1] x [0, 1])
 *
 */
vec2 GetScreenCoordinate(vec3 posWorld) {
  vec2 uv = Project(vWorldToScreen * vec4(posWorld, 1.0)).xy * 0.5 + 0.5;
  return uv;
}

float GetGBufferDepth(vec2 uv) {
  float depth = texture2D(uGDepth, uv).x;
  if (depth < 1e-2) {
    depth = 1000.0;
  }
  return depth;
}

vec3 GetGBufferNormalWorld(vec2 uv) {
  vec3 normal = texture2D(uGNormalWorld, uv).xyz;
  return normalize(normal);
}

vec3 GetGBufferPosWorld(vec2 uv) {
  vec3 posWorld = texture2D(uGPosWorld, uv).xyz;
  return posWorld;
}

float GetGBufferuShadow(vec2 uv) {
  float visibility = texture2D(uGShadow, uv).x;
  return visibility;
}

vec3 GetGBufferDiffuse(vec2 uv) {
  vec3 diffuse = texture2D(uGDiffuse, uv).xyz;
  diffuse = pow(diffuse, vec3(2.2));
  return diffuse;
}

/*
 * Evaluate diffuse bsdf value.
 *
 * wi, wo are all in world space.
 * uv is in screen space, [0, 1] x [0, 1].
 *
 */

// Lambertian
vec3 EvalDiffuse(vec3 wi, vec3 wo, vec2 uv) {
  vec3 diffuse = GetGBufferDiffuse(uv);
  vec3 normal = GetGBufferNormalWorld(uv);
  vec3 L = diffuse * max(dot(normalize(wi), normal), 0.0);
  return L;
}

/*
 * Evaluate directional light with shadow map
 * uv is in screen space, [0, 1] x [0, 1].
 *
 */
vec3 EvalDirectionalLight(vec2 uv) {
  float visibility = GetGBufferuShadow(uv);
  vec3 wo = normalize(uCameraPos - GetGBufferPosWorld(uv));
  vec3 Le = uLightRadiance * EvalDiffuse(normalize(uLightDir), wo, uv);
  return Le * visibility;
}


bool RayMarch(vec3 ori, vec3 dir, out vec3 hitPos) {
  float cur_step_length = 0.05;
  vec3 cur_pos = ori;
  float cur_depth;
  float surface_depth;
  float eps = 1e-5;
  vec2 cur_uv = vec2(0.);
  for (int i = 0; i < MAX_STEP; i++) {
    cur_pos = cur_pos + dir * cur_step_length;
    cur_depth = GetDepth(cur_pos);
    cur_uv = GetScreenCoordinate(cur_pos.xyz);
    surface_depth = GetGBufferDepth(cur_uv);
    // The depth is the distance between the scene and camera, positive. The
    // larger, the farther. At first, the ray point should be shallower than
    // scene, which means depth is smaller. The first time cur_depth is larger
    // than scene depth is the intersection.
    if (cur_depth - surface_depth > eps) {
      hitPos = cur_pos;
      return true;
    }
  }
  return false;
}

vec3 reflection(vec3 in_vec, vec3 normal) {
  float coeff = 2. * dot(in_vec, normal);
  return coeff * normal - in_vec;
}

#define SAMPLE_NUM 1
void main() {
  float s = InitRand(gl_FragCoord.xy);

  vec3 L_indirect = vec3(0.0);
  vec3 L = vec3(0.0);
  // original ocde
  vec2 uv0 = GetScreenCoordinate(vPosWorld.xyz);
  vec3 L_direct = EvalDirectionalLight(uv0);
  float pdf = 1.0;
  vec3 direction;
  vec3 wo_0 = normalize(uCameraPos - vPosWorld.xyz);
  bool hit;
  vec3 hitPos;
  vec3 normal0 = GetGBufferNormalWorld(uv0);
  vec3 b1, b2;
  LocalBasis(normal0, b1, b2);
  mat3 local2world = mat3(b1, b2, normal0);
  for (int i = 0; i < SAMPLE_NUM; ++i) {
    direction = SampleHemisphereCos(s, pdf);
    // direction = SampleHemisphereUniform(s, pdf);
    direction = local2world * direction;
    // direction = reflection(wo_0, normal0);
    hit = RayMarch(vPosWorld.xyz, direction, hitPos);
    if (hit) {
      vec2 hit_uv = GetScreenCoordinate(hitPos.xyz);
      float visibility = GetGBufferuShadow(hit_uv);
      vec3 Le = EvalDiffuse(normalize(uLightDir), -direction, hit_uv) * EvalDirectionalLight(hit_uv);
      L_indirect += EvalDiffuse(wo_0, direction, uv0) / pdf * Le;
    }
  }
  L_indirect = L_indirect / float(SAMPLE_NUM);
  L = L_direct + L_indirect;

  // float depth = GetGBufferDepth(uv0);
  // float depth = GetDepth(vPosWorld.xyz);
  // L = vec3(depth / 255.);
  // L = L_indirect;
  vec3 color = pow(clamp(L, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
  gl_FragColor = vec4(vec3(color.rgb), 1.0);
}
