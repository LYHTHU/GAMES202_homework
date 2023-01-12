class PRTMaterial extends Material {
    constructor(vertexShader, fragmentShader) {
        let precomputeL_mat = getMat3ValueFromRGB(precomputeL[guiParams.envmapId]);
        // super({ 
        //     'aPrecomputeLR': { type: 'matrix3fv', value: precomputeL_mat[0]},
        //     'aPrecomputeLG': { type: 'matrix3fv', value: precomputeL_mat[1]},
        //     'aPrecomputeLB': { type: 'matrix3fv', value: precomputeL_mat[2]}
        //     }, [
        //         'aPrecomputeLT'
        //     ], vertexShader, fragmentShader, null);

        super({                    
            'aPrecomputeLR': { type: 'updatedInRealTime', value: null },   
            'aPrecomputeLG': { type: 'updatedInRealTime', value: null },   
            'aPrecomputeLB': { type: 'updatedInRealTime', value: null },   
        }, ['aPrecomputeLT'], vertexShader, fragmentShader, null);
    }
} 


async function buildPRTMaterial(vertexPath, fragmentPath) {
    let vertexShader = await getShaderString(vertexPath);
    let fragmentShader = await getShaderString(fragmentPath);
    return new PRTMaterial(vertexShader, fragmentShader);
}