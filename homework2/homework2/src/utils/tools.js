function getRotationPrecomputeL(precompute_L, rotationMatrix){
	let rot_mat4 = mat4Matrix2mathMatrix(rotationMatrix);
	let mat_3x3 = computeSquareMatrix_3by3(rot_mat4);
	let mat_5x5 = computeSquareMatrix_5by5(rot_mat4);
	// Because precompute_L is 9x3, we need to make each RGB a column.
	let cooefs_l1 = math.matrix(precompute_L.slice(1, 4));
	let cooefs_l2 = math.matrix(precompute_L.slice(4, 9));
	let rotated_coeffs_l1 = math.multiply(math.transpose(mat_3x3), cooefs_l1)._data;
	let rotated_coeffs_l2 = math.multiply(math.transpose(mat_5x5), cooefs_l2)._data;
	let result = [precompute_L[0]].concat(rotated_coeffs_l1).concat(rotated_coeffs_l2);
	return result;
}


function computeSquareMatrix_3by3(rotationMatrix){ // 计算方阵SA(-1) 3*3 
	
	// 1、pick ni - {ni}
	let n1 = [1, 0, 0, 0]; let n2 = [0, 0, 1, 0]; let n3 = [0, 1, 0, 0];
	let n_lst = [n1, n2, n3]
	let n_mat = math.transpose(math.matrix(n_lst));
	let order = 1;
	// 2、{P(ni)} - A  A_inverse
	let coeef_lst = [];

	for(let i = 0; i < 2*order + 1; ++i) {
		let n_i = math.column(n_mat, i);
		let cooefs_i = SHEval(n_i._data[0], n_i._data[1], n_i._data[2], 3);
		coeef_lst.push(cooefs_i.slice(1, 4));
	}
	let A = math.transpose(math.matrix(coeef_lst));
	let A_inv = math.inv(A);
	// 3、用 R 旋转 ni - {R(ni)}
	let rotate_n_mat = math.multiply(rotationMatrix, n_mat);
	// 4、R(ni) SH投影 - Ss
	let S_lst = [];
	for(let i = 0; i < 2*order + 1; ++i) {
		let rn_i = math.column(rotate_n_mat, i);
		let cooefs_rn_i = SHEval(rn_i._data[0], rn_i._data[1], rn_i._data[2], 3);
		S_lst.push(cooefs_rn_i.slice(1, 4));
	}
	let S = math.transpose(math.matrix(S_lst));
	// 5、S*A_inverse
	return math.multiply(S, A_inv);
}

function computeSquareMatrix_5by5(rotationMatrix){ // 计算方阵SA(-1) 5*5
	
	// 1、pick ni - {ni}
	let k = 1 / math.sqrt(2);
	let n1 = [1, 0, 0, 0]; let n2 = [0, 0, 1, 0]; let n3 = [k, k, 0, 0]; 
	let n4 = [k, 0, k, 0]; let n5 = [0, k, k, 0];

	let n_lst = [n1, n2, n3, n4, n5];
	let n_mat = math.transpose(math.matrix(n_lst));
	let order = 2;

	// 2、{P(ni)} - A  A_inverse

	let coeef_lst = [];
	for(let i = 0; i < 2*order + 1; ++i) {
		let n_i = math.column(n_mat, i);
		let cooefs_i = SHEval(n_i._data[0], n_i._data[1], n_i._data[2], 3);
		coeef_lst.push(cooefs_i.slice(4, 9));
	}
	let A = math.transpose(math.matrix(coeef_lst));
	let A_inv = math.inv(A);

	// 3、用 R 旋转 ni - {R(ni)}
	let rotate_n_mat = math.multiply(rotationMatrix, n_mat);

	// 4、R(ni) SH投影 - S
	let S_lst = [];
	for(let i = 0; i < 2*order + 1; ++i) {
		let rn_i = math.column(rotate_n_mat, i);
		let cooefs_rn_i = SHEval(rn_i._data[0], rn_i._data[1], rn_i._data[2], 3);
		S_lst.push(cooefs_rn_i.slice(4, 9));
	}
	let S = math.transpose(math.matrix(S_lst));
	// 5、S*A_inverse
	return math.multiply(S, A_inv);
}

function mat4Matrix2mathMatrix(rotationMatrix){

	let mathMatrix = [];
	for(let i = 0; i < 4; i++){
		let r = [];
		for(let j = 0; j < 4; j++){
			r.push(rotationMatrix[i*4+j]);
		}
		mathMatrix.push(r);
	}
	return math.matrix(mathMatrix)

}

function getMat3ValueFromRGB(precomputeL){

    let colorMat3 = [];
    for(var i = 0; i<3; i++){
        colorMat3[i] = mat3.fromValues( precomputeL[0][i], precomputeL[1][i], precomputeL[2][i],
										precomputeL[3][i], precomputeL[4][i], precomputeL[5][i],
										precomputeL[6][i], precomputeL[7][i], precomputeL[8][i] ); 
	}
    return colorMat3;
}