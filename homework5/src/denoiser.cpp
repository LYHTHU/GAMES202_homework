#include "denoiser.h"

Denoiser::Denoiser() : m_useTemportal(false) {}

void Denoiser::Reprojection(const FrameInfo &frameInfo) {
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    Matrix4x4 preWorldToScreen =
        m_preFrameInfo.m_matrix[m_preFrameInfo.m_matrix.size() - 1];
    Matrix4x4 preWorldToCamera =
        m_preFrameInfo.m_matrix[m_preFrameInfo.m_matrix.size() - 2];
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // Reproject
             int id = int(frameInfo.m_id(x, y));
             m_valid(x, y) = false;
             m_misc(x, y) = Float3(0.f);
             if (id > 0) {
                 Matrix4x4 curObjToWorld = frameInfo.m_matrix[id]; // to inv
                 Matrix4x4 preObjToWorld = m_preFrameInfo.m_matrix[id];
                 Float3 curWorldPos = frameInfo.m_position(x, y);
                 // operator ()
                 // 1. Compute Obj Pos. Use Inverse(curObjToWorld)
                 Float3 objPos = Inverse(curObjToWorld)(curWorldPos, Float3::Point);
                 // 2. Compute preframe world Pos. use `preObjToWorld`.
                 Float3 preWorldPos = preObjToWorld(objPos, Float3::Point);
                 // 3. Comptute preframe screen Pos. Use `preWorldToScreen`. Check valid.
                 Float3 preScreenPos = preWorldToScreen(preWorldPos, Float3::Point);
                 int pre_x = int(preScreenPos.x), pre_y = int(preScreenPos.y);
                 if (pre_x > -1 && pre_x < width && pre_y > -1 && pre_y < height) {
                     int mid_prev = int(m_preFrameInfo.m_id(pre_x, pre_y));
                     if (mid_prev == id) {
                         m_valid(x, y) = true;
                         m_misc(x, y) = m_accColor(pre_x, pre_y);
                     }
                 }
             }
        }
    }
    std::swap(m_misc, m_accColor);
}

void Denoiser::TemporalAccumulation(const Buffer2D<Float3> &curFilteredColor) {
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    int kernelRadius = 3;
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // Temporal clamp
            if (m_valid(x, y)) {
                Float3 color = m_accColor(x, y);
                Float3 mean(0.), sigma(0.), mean2(0.);
                float cnt = 0.;
                for (int i = -kernelRadius; i <= kernelRadius; ++i) {
                    for (int j = -kernelRadius; j <= kernelRadius; ++j) {
                        int cur_x = x + j, cur_y = y + i;
                        if (cur_x > -1 && cur_x < width && cur_y > -1 && cur_y < height) {
                            cnt += 1.;
                            mean += curFilteredColor(x, y);
                            mean2 += Sqr(curFilteredColor(x, y));
                        }
                    }
                }
                mean /= cnt;
                mean2 /= cnt;
                sigma = SafeSqrt(mean2 - Sqr(mean));

                color = Clamp(color, mean - (sigma * m_colorBoxK), mean + sigma * m_colorBoxK);
                // Exponential moving average
                m_misc(x, y) = Lerp(color, curFilteredColor(x, y), m_alpha);
            }
            else {
                m_misc(x, y) = curFilteredColor(x, y);
            }
        }
    }
    std::swap(m_misc, m_accColor);
}

Buffer2D<Float3> Denoiser::Filter(const FrameInfo &frameInfo) {
    int height = frameInfo.m_beauty.m_height;
    int width = frameInfo.m_beauty.m_width;
    Buffer2D<Float3> filteredImage = CreateBuffer2D<Float3>(width, height);
    int kernelRadius = 16;
 #pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            float sum_weight = 0.;
            Float3 denoise_color(0.);
            for (int i = -kernelRadius; i <= kernelRadius; ++i) {
                for (int j = -kernelRadius; j <= kernelRadius; ++j) {
                    int cur_y = y + i;
                    int cur_x = x + j;
                    if(cur_y > -1 && cur_y < height && cur_x > -1 && cur_x < width) {
                        // Joint bilateral filter
                        float value_ij = -(Sqr(x - cur_x) + Sqr(y - cur_y)) / (2. * Sqr(m_sigmaCoord));

                        Float3 color_delta = frameInfo.m_beauty(x, y) - frameInfo.m_beauty(cur_x, cur_y);
                        float value_color = -SqrLength(color_delta) / (2. * Sqr(m_sigmaColor));

                        float d_normal = Dot(frameInfo.m_normal(x, y), frameInfo.m_normal(cur_x, cur_y));
                        float acos_d_norm = SafeAcos(d_normal);
                        float value_normal = -acos_d_norm * acos_d_norm / (2. * Sqr(m_sigmaNormal));

                        float value_plane = 0.;
                        Float3 vec_ij = frameInfo.m_position(cur_x, cur_y) - frameInfo.m_position(x, y);
                        float len_vec_ij = Length(vec_ij);
                        if(len_vec_ij > 0.) {
                            vec_ij = vec_ij / len_vec_ij;
                            float d_plane = Dot(frameInfo.m_normal(x, y), vec_ij);
                            value_plane = -d_plane*d_plane / (2. * Sqr(m_sigmaPlane));
                        }
                        float weight = expf(value_ij + value_color + value_normal + value_plane);
                        denoise_color +=  (frameInfo.m_beauty(cur_x, cur_y) * weight);
                        sum_weight += weight;
                    }
                }
            }
            denoise_color /= (sum_weight);
            filteredImage(x, y) = denoise_color;
        }
    }
    return filteredImage;
}

void Denoiser::Init(const FrameInfo &frameInfo, const Buffer2D<Float3> &filteredColor) {
    m_accColor.Copy(filteredColor);
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    m_misc = CreateBuffer2D<Float3>(width, height);
    m_valid = CreateBuffer2D<bool>(width, height);
}

void Denoiser::Maintain(const FrameInfo &frameInfo) { m_preFrameInfo = frameInfo; }

Buffer2D<Float3> Denoiser::ProcessFrame(const FrameInfo &frameInfo) {
    // Filter current frame
    Buffer2D<Float3> filteredColor;
    filteredColor = Filter(frameInfo);

    // Reproject previous frame color to current
    if (m_useTemportal) {
        Reprojection(frameInfo);
        TemporalAccumulation(filteredColor);
    } else {
        Init(frameInfo, filteredColor);
    }

    // Maintain
    Maintain(frameInfo);
    if (!m_useTemportal) {
        m_useTemportal = true;
    }
    return m_accColor;
}
