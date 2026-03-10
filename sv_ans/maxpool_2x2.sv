module maxpool_2x2 #(
    parameter int unsigned P_CH  = 4,
    parameter int unsigned N_CH  = 16,
    parameter int unsigned N_IW  = 64,
    parameter int unsigned A_BIT = 8
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [P_CH*A_BIT-1:0] in_data,
    input  logic                  in_valid,
    output logic                  in_ready,
    output logic [P_CH*A_BIT-1:0] out_data,
    output logic                  out_valid,
    input  logic                  out_ready
);

    localparam int unsigned FOLD = N_CH / P_CH;
    localparam int unsigned N_OW = N_IW / 2;
    localparam int unsigned LB_DEPTH = N_OW * FOLD;
    localparam int unsigned LB_AWIDTH = $clog2(LB_DEPTH);

    logic handshake_in;
    logic handshake_out;

    logic                      cntr_h;
    logic [$clog2(N_IW+1)-1:0] cntr_w;
    logic [$clog2(FOLD+1)-1:0] cntr_f;

    logic                      lb_we;
    logic [     LB_AWIDTH-1:0] lb_waddr;
    logic [    P_CH*A_BIT-1:0] lb_wdata;
    logic                      lb_re;
    logic [     LB_AWIDTH-1:0] lb_raddr;
    logic [    P_CH*A_BIT-1:0] lb_rdata;
    
    logic [    P_CH*A_BIT-1:0] pixel_buf [FOLD];
    logic [    P_CH*A_BIT-1:0] temp_max_data;

    logic                  pipe_valid;
    logic [P_CH*A_BIT-1:0] pipe_temp_max;

    logic is_output_cycle;
    assign is_output_cycle = (cntr_h == 1'b1) && (cntr_w[0] == 1'b1);
    assign in_ready        = is_output_cycle ? (!pipe_valid || out_ready) : 1'b1;
    
    assign handshake_in    = in_valid && in_ready;
    assign handshake_out   = out_valid && out_ready;

    // 计数器状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cntr_h <= 1'b0; // 必须从 0 行开始
            cntr_w <= '0;
            cntr_f <= '0;
        end else begin
            if (handshake_in) begin
                if (cntr_f == FOLD - 1) begin
                    cntr_f <= '0;
                    if (cntr_w == N_IW - 1) begin
                        cntr_w <= '0;
                        cntr_h <= ~cntr_h; // 交替处理行：Row0(写缓存) -> Row1(输出)
                    end else begin
                        cntr_w <= cntr_w + 1;
                    end
                end else begin
                    cntr_f <= cntr_f + 1;
                end
            end
        end
    end

    // 水平池化与 Line Buffer 交互
    
    // 将偶数列 (cntr_w[0] == 0) 的像素缓存下来
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < FOLD; i++) begin
                pixel_buf[i] <= '0;
            end
        end else if (handshake_in && (cntr_w[0] == 1'b0)) begin
            pixel_buf[cntr_f] <= in_data;
        end
    end

    // 当前行的水平 Max
    assign temp_max_data = max_vec(pixel_buf[cntr_f], in_data);

    // RAM Write: 偶数行且在奇数列时，将当前行的水平 Max 存入 Line Buffer
    assign lb_we    = handshake_in && (cntr_h == 1'b0) && (cntr_w[0] == 1'b1);
    assign lb_waddr = (cntr_w >> 1) * FOLD + cntr_f;
    assign lb_wdata = temp_max_data;

    // RAM Read: 奇数行且在奇数列时，提前向 RAM 发起读请求（假设 1 cycle read latency）
    assign lb_re    = handshake_in && (cntr_h == 1'b1) && (cntr_w[0] == 1'b1);
    assign lb_raddr = (cntr_w >> 1) * FOLD + cntr_f;

    ram #(
        .DWIDTH  (P_CH * A_BIT),
        .AWIDTH  (LB_AWIDTH),
        .MEM_SIZE(LB_DEPTH)
    ) u_line_buf (
        .clk  (clk),
        .we   (lb_we),
        .waddr(lb_waddr),
        .wdata(lb_wdata),
        .re   (lb_re),
        .raddr(lb_raddr),
        .rdata(lb_rdata)
    );

    //垂直池化与 Valid 0/1 翻转控制

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid    <= 1'b0;
            pipe_temp_max <= '0;
        end else begin
            // 0 -> 1: 前级在输出节拍有效打入了读取请求，将当拍的数据推入流水线
            if (lb_re) begin
                pipe_valid    <= 1'b1;
                pipe_temp_max <= temp_max_data;
            end 
            // 1 -> 0: 数据被下游取走，且前级没有新数据压入
            else if (handshake_out) begin
                pipe_valid    <= 1'b0;
            end
        end
    end

    //利用 RAM 读取出的上一行最大值，和已打一拍的当前行最大值，得出最终结果
    assign out_valid = pipe_valid;
    assign out_data  = max_vec(pipe_temp_max, lb_rdata);

    //池化是求 MAX 而不是求 MIN，转为 signed 适配神经网络特征
    function automatic logic [P_CH*A_BIT-1:0] max_vec(input logic [P_CH*A_BIT-1:0] a, input logic [P_CH*A_BIT-1:0] b);
        logic signed [A_BIT-1:0] a_ch, b_ch;
        for (int i = 0; i < P_CH; i++) begin
            a_ch = a[i*A_BIT +: A_BIT];
            b_ch = b[i*A_BIT +: A_BIT];
            max_vec[i*A_BIT +: A_BIT] = (a_ch > b_ch) ? a_ch : b_ch;
        end
    endfunction

endmodule