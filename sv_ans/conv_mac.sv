module conv_mac_array #(
    parameter int unsigned P_ICH = 4,
    parameter int unsigned A_BIT = 8,
    parameter int unsigned W_BIT = 8,
    parameter int unsigned B_BIT = 32
    ) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic                    dat_vld,
    input  logic                    clr,
    input  logic        [A_BIT-1:0] x_vec[P_ICH],
    input  logic signed [W_BIT-1:0] w_vec[P_ICH],
    output logic signed [B_BIT-1:0] acc
    );

    /* 内部连线及延迟线信号定义 */
    logic        [A_BIT-1:0] x_dly      [P_ICH];
    logic signed [W_BIT-1:0] w_dly      [P_ICH];
    logic                    dat_vld_dly[P_ICH];
    logic                    clr_dly    [P_ICH];
    logic signed [B_BIT-1:0] mac_cascade[P_ICH+1];

    // 级联起点置零
    assign mac_cascade[0] = '0;

    /* 1. 输入数据 (x) 和 权重 (w) 的延迟线逻辑 (完全替代原 delayline 模块) */
    generate
        for (genvar i = 0; i < P_ICH; i++) begin : gen_delayline
            // 分别声明深度为 i+1 的移位寄存器
            logic        [A_BIT-1:0] x_shift[i+1];
            logic signed [W_BIT-1:0] w_shift [i+1];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int j = 0; j <= i; j++) begin
                        x_shift[j] <= '0;
                        w_shift[j] <= '0;
                    end
                end else if (en) begin
                    x_shift[0] <= x_vec[i];
                    w_shift[0] <= w_vec[i];
                    for (int j = 1; j <= i; j++) begin
                        x_shift[j] <= x_shift[j-1];
                        w_shift[j] <= w_shift[j-1];
                    end
                end
            end

            assign x_dly[i] = x_shift[i];
            assign w_dly[i] = w_shift[i];
        end
    endgenerate

    /* 2. 控制信号的流水线打拍逻辑 */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 修正：将 i=1 修正为 i=0 开始，避免 [0] 缺少复位生成锁存/未复位寄存器
            for (int i = 0; i < P_ICH; i++) begin
                clr_dly[i]     <= 1'b0;
                dat_vld_dly[i] <= 1'b0;
            end
        end else if (en) begin
            clr_dly[0]     <= clr;
            dat_vld_dly[0] <= dat_vld;
            for (int i = 1; i < P_ICH; i++) begin
                clr_dly[i]     <= clr_dly[i-1];
                dat_vld_dly[i] <= dat_vld_dly[i-1];
            end
        end
    end

    /* 3. 乘加阵列 (MAC Array) 乘法运算逻辑 */
    logic signed [B_BIT-1:0] prod [P_ICH];

    always_comb begin
        for (int i = 0; i < P_ICH; i++) begin
            prod[i] = $signed({1'b0, x_dly[i]}) * w_dly[i];
        end
    end

    /* 4. 乘加阵列 (MAC Array) 累加与级联更新逻辑 */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 1; i <= P_ICH; i++) begin
                mac_cascade[i] <= '0;
            end
        end else begin
            // (索引 0 ~ P_ICH-2)
            for (int i = 0; i < P_ICH - 1; i++) begin
                if (en && dat_vld_dly[i]) begin
                    mac_cascade[i+1] <= prod[i] + mac_cascade[i];
                end
            end
            
            // (索引 P_ICH-1)
            if (en) begin
                case ({clr_dly[P_ICH-1], dat_vld_dly[P_ICH-1]})
                    2'b00: mac_cascade[P_ICH] <= mac_cascade[P_ICH];
                    2'b01: mac_cascade[P_ICH] <= mac_cascade[P_ICH-1] + prod[P_ICH-1] + mac_cascade[P_ICH];
                    2'b10: mac_cascade[P_ICH] <= mac_cascade[P_ICH-1];
                    2'b11: mac_cascade[P_ICH] <= mac_cascade[P_ICH-1] + prod[P_ICH-1];
                endcase
            end
        end
    end

    // 最终累加输出
    assign acc = mac_cascade[P_ICH];

endmodule