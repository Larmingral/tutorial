module mac_array #(
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
    input  logic        [A_BIT-1:0] x_vec  [P_ICH],
    input  logic signed [W_BIT-1:0] w_vec  [P_ICH],
    output logic signed [B_BIT-1:0] acc
);

    logic signed [B_BIT-1:0] spatial_sum;

    always_comb begin
        spatial_sum = 0; 
        for (int i = 0; i < P_ICH; i++) begin
            spatial_sum = spatial_sum + ($signed({1'b0, x_vec[i]}) * $signed(w_vec[i]));
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 0; 
        end else if (en) begin
            if (dat_vld) begin
                if (clr) acc <= spatial_sum;
                else     acc <= acc + spatial_sum;
            end else begin
                if (clr) acc <= 0;
            end
        end
    end

endmodule