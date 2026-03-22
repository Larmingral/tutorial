import numpy as np

def ceil_div(x, y):
    return (x + y - 1) // y

def test_matmul():
    M = np.random.randint(3, 100)
    K = np.random.randint(3, 100)
    N = np.random.randint(3, 100)
    M0 = 3
    N0 = 4
    K0 = 5    
    M1 = ceil_div(M, M0)
    N1 = ceil_div(N, N0)
    K1 = ceil_div(K, K0)
    # 定义矩阵乘法参数
    layer = {
        'M': M,
        'N': N,
        'K': K,
        'M1': M1,
        'N1': N1,
        'K1': K1
    }
    print(layer)

    left_mk = np.random.randint(-128, 127, size=(M, K))
    right_nk = np.random.randint(-128, 127, size=(N, K))
    result_m1n1m0n0 = np.zeros((M1, N1, M0, N0))

    left_m1m0k1k0 = np.zeros((M1*M0, K1*K0))
    left_m1m0k1k0[:M, :K] = left_mk
    left_m1k1m0k0 = left_m1m0k1k0.reshape(M1, M0, K1, K0).transpose(0, 2, 1, 3)

    right_n1n0k1k0 = np.zeros((N1*N0, K1*K0))
    right_n1n0k1k0[:N, :K] = right_nk
    right_n1k1n0k0 = right_n1n0k1k0.reshape(N1, N0, K1, K0).transpose(0, 2, 1, 3)

    for m1 in range(M1):
        for n1 in range(N1):
            temp = np.zeros((M0, N0))
            for k1 in range(K1):

                for m0 in range(M0):
                    for n0 in range(N0):
                        for k0 in range(K0):
                            # 核心公式：结果 += 左边矩阵的块 * 右边矩阵的块
                            temp[m0][n0] += left_m1k1m0k0[m1][k1][m0][k0] * right_n1k1n0k0[n1][k1][n0][k0]
            result_m1n1m0n0[m1][n1] = temp

    result_m1m0n1n0 = result_m1n1m0n0.transpose(0, 2, 1, 3).reshape(M1*M0, N1*N0)
    result_mn = result_m1m0n1n0[:M, :N]
    result_golden = np.matmul(left_mk, right_nk.transpose())
    diff = np.abs(result_golden - result_mn)
    if(diff.sum() == 0):
        print('Pass')

for i in range(10):
    test_matmul()