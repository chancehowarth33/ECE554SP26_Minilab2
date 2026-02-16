// image_proc.sv
// 3x3 convolution filter for 12-bit grayscale streaming video (640-wide assumed by line buffer)
// - Uses Gray_Line_Buffer_640 (two taps @ 640) to access y-1 and y-2 rows
// - Builds full 3x3 window with 2 horizontal delays per row
// - Does signed filter multiply with UNSIGNED pixel handling (no bad sign-extension)
// - Computes magnitude as absolute value of convolution sum
// - Clamps to 12'hFFF
// - oDVAL is a pipelined version of iDVAL (3 cycles here, matching the internal regs)
//
// Added: iCONV_EN
//   - iCONV_EN = 0: output the CENTER of the 3x3 window (no convolution math)
//                 (center pixel is r11 = (x-1,y-1) after the window/pipeline regs)
//   - iCONV_EN = 1: output the convolution magnitude (existing behavior)

module image_proc (
    input  logic        iCLK,
    input  logic        iRST,       // active-LOW reset (async, negedge)
    input  logic [11:0] iPIX12,     // input grayscale pixel (12-bit)
    input  logic        iDVAL,      // input valid (pixel enable)
    input  logic        iMODE,      // 0/1 selects filter kernel
    input  logic        iCONV_EN,   // 0 = window-only (center pixel), 1 = convolution

    output logic [11:0] oPIX12,     // output grayscale pixel (12-bit)
    output logic        oDVAL       // output valid
);

    // ----------------------------
    // 3x3 filter coefficients
    // ----------------------------
    logic signed [11:0] k00, k01, k02;
    logic signed [11:0] k10, k11, k12;
    logic signed [11:0] k20, k21, k22;

    always_comb begin
        k00 = -12'sd1;
        k01 = iMODE ?  12'sd0 : -12'sd2;
        k02 = iMODE ?  12'sd1 : -12'sd1;

        k10 = iMODE ? -12'sd2 :  12'sd0;
        k11 =  12'sd0;
        k12 = iMODE ?  12'sd2 :  12'sd0;

        k20 = iMODE ? -12'sd1 :  12'sd1;
        k21 = iMODE ?  12'sd0 :  12'sd2;
        k22 =  12'sd1;
    end

    // ----------------------------
    // Line buffer: vertical neighbors at same x
    // pix_y1 = (x, y-1), pix_y2 = (x, y-2)
    // ----------------------------
    logic [11:0] pix_y1;
    logic [11:0] pix_y2;
    logic [11:0] unused_shiftout;

    Gray_Line_Buffer_640 u_linebuf (
        .clken   (iDVAL),
        .clock   (iCLK),
        .shiftin (iPIX12),
        .shiftout(unused_shiftout),
        .taps0x  (pix_y1), // [11:0]
        .taps1x  (pix_y2) // [12:23]
    );

    // ----------------------------
    // Horizontal delays (x-1, x-2) for each row stream
    // ----------------------------
    logic [11:0] y2_d1, y2_d2;
    logic [11:0] y1_d1, y1_d2;
    logic [11:0] y0_d1, y0_d2;

    always_ff @(posedge iCLK or negedge iRST) begin
        if (!iRST) begin
            y2_d1 <= 12'd0; y2_d2 <= 12'd0;
            y1_d1 <= 12'd0; y1_d2 <= 12'd0;
            y0_d1 <= 12'd0; y0_d2 <= 12'd0;
        end else if (iDVAL) begin
            // row y-2 stream
            y2_d2 <= y2_d1;
            y2_d1 <= pix_y2;

            // row y-1 stream
            y1_d2 <= y1_d1;
            y1_d1 <= pix_y1;

            // current row y stream
            y0_d2 <= y0_d1;
            y0_d1 <= iPIX12;
        end
    end

    // ----------------------------
    // 3x3 window signals
    // ----------------------------
    logic [11:0] p00, p01, p02;
    logic [11:0] p10, p11, p12;
    logic [11:0] p20, p21, p22;

    always_comb begin
        p00 = y2_d2;  p01 = y2_d1;  p02 = pix_y2;
        p10 = y1_d2;  p11 = y1_d1;  p12 = pix_y1;
        p20 = y0_d2;  p21 = y0_d1;  p22 = iPIX12;
    end

    // ----------------------------
    // Pipeline registers for pixels + DVAL
    // ----------------------------
    logic [11:0] r00, r01, r02, r10, r11, r12, r20, r21, r22;
    logic        v1, v2, v3;

    always_ff @(posedge iCLK or negedge iRST) begin
        if (!iRST) begin
            r00 <= 12'd0; r01 <= 12'd0; r02 <= 12'd0;
            r10 <= 12'd0; r11 <= 12'd0; r12 <= 12'd0;
            r20 <= 12'd0; r21 <= 12'd0; r22 <= 12'd0;
            v1  <= 1'b0;  v2  <= 1'b0;  v3  <= 1'b0;
        end else begin
            // DVAL pipeline always advances so cadence matches the stream
            v1 <= iDVAL;
            v2 <= v1;
            v3 <= v2;

            // Only capture new pixels when iDVAL=1 (matches linebuf shifting)
            if (iDVAL) begin
                r00 <= p00; r01 <= p01; r02 <= p02;
                r10 <= p10; r11 <= p11; r12 <= p12;
                r20 <= p20; r21 <= p21; r22 <= p22;
            end
        end
    end

    assign oDVAL = v3;

    // ----------------------------
    // Multiply-accumulate (pixels forced unsigned before signed multiply)
    // ----------------------------
    logic signed [19:0] m00, m01, m02, m10, m11, m12, m20, m21, m22;
    logic signed [23:0] acc;
    logic signed [23:0] acc_abs;

    always_comb begin
        m00 = $signed({1'b0, r00}) * k00;
        m01 = $signed({1'b0, r01}) * k01;
        m02 = $signed({1'b0, r02}) * k02;

        m10 = $signed({1'b0, r10}) * k10;
        m11 = $signed({1'b0, r11}) * k11;
        m12 = $signed({1'b0, r12}) * k12;

        m20 = $signed({1'b0, r20}) * k20;
        m21 = $signed({1'b0, r21}) * k21;
        m22 = $signed({1'b0, r22}) * k22;

        acc = m00 + m01 + m02 + m10 + m11 + m12 + m20 + m21 + m22;

        // magnitude output
        acc_abs = (acc < 0) ? -acc : acc;
    end

    // ----------------------------
    // Output register:
    //   iCONV_EN=0 -> output center of 3x3 window (r11)
    //   iCONV_EN=1 -> output convolution magnitude (clamped)
    // ----------------------------
    always_ff @(posedge iCLK or negedge iRST) begin
        if (!iRST) begin
            oPIX12 <= 12'd0;
        end else if (v3) begin
            if (!iCONV_EN) begin
                // window-only: center pixel of the 3x3 neighborhood
                oPIX12 <= r11;
            end else begin
                // convolution output (existing behavior)
                if (acc_abs > 24'sd4095)
                    oPIX12 <= 12'hFFF;
                else
                    oPIX12 <= acc_abs[11:0];
            end
        end
    end

endmodule
