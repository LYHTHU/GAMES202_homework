#ifdef GL_ES
precision mediump float;
#endif

// Phong related variables
uniform sampler2D uSampler;
uniform vec3 uKd;
uniform vec3 uKs;
uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightIntensity;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

// Shadow map related variables
#define NUM_SAMPLES 40
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define PCSS_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

#define EPS 1e-3
#define PI 3.141592653589793
#define PI2 6.283185307179586
#define LIGHT_WIDTH 0.01

uniform sampler2D uShadowMap;

varying vec4 vPositionFromLight;

highp float rand_1to1(highp float x ) { 
  // -1 -1
  return fract(sin(x)*10000.0);
}

highp float rand_2to1(vec2 uv ) { 
  // 0 - 1
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract(sin(sn) * c);
}

float unpack(vec4 rgbaDepth) {
    const vec4 bitShift = vec4(1.0, 1.0/256.0, 1.0/(256.0*256.0), 1.0/(256.0*256.0*256.0));
    return dot(rgbaDepth, bitShift);
}

vec2 poissonDisk[NUM_SAMPLES];

void poissonDiskSamples( const in vec2 randomSeed ) {

  float ANGLE_STEP = PI2 * float( NUM_RINGS ) / float( NUM_SAMPLES );
  float INV_NUM_SAMPLES = 1.0 / float( NUM_SAMPLES );

  float angle = rand_2to1( randomSeed ) * PI2;
  float radius = INV_NUM_SAMPLES;
  float radiusStep = radius;

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( cos( angle ), sin( angle ) ) * pow( radius, 0.75 );
    radius += radiusStep;
    angle += ANGLE_STEP;
  }
}

void uniformDiskSamples( const in vec2 randomSeed ) {

  float randNum = rand_2to1(randomSeed);
  float sampleX = rand_1to1( randNum ) ;
  float sampleY = rand_1to1( sampleX ) ;

  float angle = sampleX * PI2;
  float radius = sqrt(sampleY);

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( radius * cos(angle) , radius * sin(angle)  );

    sampleX = rand_1to1( sampleY ) ;
    sampleY = rand_1to1( sampleX ) ;

    angle = sampleX * PI2;
    radius = sqrt(sampleY);
  }
}

float findBlocker( sampler2D shadowMap,  vec2 uv, float zReceiver) {
  // find the average blocker depth
  uniformDiskSamples(vTextureCoord);
  int count = 0;
  float sum_depth_blocker = 0.;
  float center_depth_shadow_map = unpack(texture2D(shadowMap, uv));
  float search_radius = LIGHT_WIDTH / 2.0;
  // For the places where is real be blocked(instead of on the surface or not block at all)
  if ((center_depth_shadow_map - EPS > 0.) && (center_depth_shadow_map + EPS < zReceiver)) {
    search_radius = (zReceiver - center_depth_shadow_map) / zReceiver * LIGHT_WIDTH / 2.0;
  }
  for (int i = 0; i < PCSS_NUM_SAMPLES; ++i) {
    vec2 rand_coord = uv + search_radius * poissonDisk[i];
    float blocker_depth = unpack(texture2D(shadowMap, rand_coord));
    if (blocker_depth > EPS) {
      sum_depth_blocker += blocker_depth;
      count += 1;
    }
  }
	return sum_depth_blocker / float(count);
}

float PCF(sampler2D shadowMap, vec4 coords) {
  uniformDiskSamples(vTextureCoord);
  float viz = 0.;
  vec4 depth_rgba;
  float depth;
  for (int i = 0; i < PCF_NUM_SAMPLES; ++i) {
    vec2 rand_coord = coords.xy + 0.0005 * poissonDisk[i];
    depth_rgba = texture2D(shadowMap, rand_coord);
    depth = unpack(depth_rgba);
    viz += step(coords.z - EPS, depth);
  }
  viz = viz / float(PCF_NUM_SAMPLES);
  return viz;
}

float PCSS(sampler2D shadowMap, vec4 coords){

  // STEP 1: avgblocker depth
  float avg_blocker_depth = findBlocker(shadowMap, coords.xy, coords.z);
  if(avg_blocker_depth <= EPS)
    return 1.0;
  // STEP 2: penumbra size
  float pernumbra_size;
  pernumbra_size = (coords.z - avg_blocker_depth) * LIGHT_WIDTH / avg_blocker_depth;
  // STEP 3: filtering
  uniformDiskSamples(vTextureCoord + 0.5);
  float depth_shadow_map;
  float viz = 0.0;
  for (int i = 0; i < PCSS_NUM_SAMPLES; ++i) {
    vec2 rand_coord = coords.xy + pernumbra_size * poissonDisk[i];
    depth_shadow_map = unpack(texture2D(shadowMap, rand_coord));
    if(abs(depth_shadow_map) < 1e-5) 
      depth_shadow_map = 1.0;
    viz += step(coords.z - EPS, depth_shadow_map);
  }
  viz = viz / float(PCSS_NUM_SAMPLES);
  return viz;
}


float useShadowMap(sampler2D shadowMap, vec4 shadowCoord){  
  vec4 depth_rgba = texture2D(shadowMap, shadowCoord.xy);
  float depth = unpack(depth_rgba);
  if (shadowCoord.z - EPS <= depth)
    return 1.0;
  else
    return 0.0;  
}

vec3 blinnPhong() {
  vec3 color = texture2D(uSampler, vTextureCoord).rgb;
  color = pow(color, vec3(2.2));

  vec3 ambient = 0.05 * color;

  vec3 lightDir = normalize(uLightPos);
  vec3 normal = normalize(vNormal);
  float diff = max(dot(lightDir, normal), 0.0);
  vec3 light_atten_coff =
      uLightIntensity / pow(length(uLightPos - vFragPos), 2.0);
  vec3 diffuse = diff * light_atten_coff * color;

  vec3 viewDir = normalize(uCameraPos - vFragPos);
  vec3 halfDir = normalize((lightDir + viewDir));
  float spec = pow(max(dot(halfDir, normal), 0.0), 32.0);
  vec3 specular = uKs * light_atten_coff * spec;

  vec3 radiance = (ambient + diffuse + specular);
  vec3 phongColor = pow(radiance, vec3(1.0 / 2.2));
  return phongColor;
}

void main(void) {
  // poissonDiskSamples(vTextureCoord);
  float visibility;
  vec3 projCoords = vPositionFromLight.xyz / vPositionFromLight.w;
  vec3 shadowCoord = projCoords * 0.5 + 0.5;
  // visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0));
  // visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0));
  visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0));

  vec3 phongColor = blinnPhong();
  gl_FragColor = vec4(phongColor * visibility, 1.0);
  // gl_FragColor = vec4(phongColor, 1.0);
}