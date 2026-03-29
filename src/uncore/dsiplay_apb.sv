`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: display_apb
// Description: APB Slave that controls a solid-color VGA output.
//              Writing bit [0] to offsets 0x0, 0x4, and 0x8 toggles
//              the Red, Green, and Blue channels for the entire screen.
//////////////////////////////////////////////////////////////////////////////////

module display_apb import cvw::*; #(parameter cvw_t P) (
    // -------------------------------------------------------------------------
    // APB Bus Interface
    // -------------------------------------------------------------------------
    input  logic                PCLK,
    input  logic                PRESETn,
    input  logic                PSEL,
    input  logic [3:0]          PADDR,
    input  logic [P.XLEN-1:0]   PWDATA,
    input  logic [P.XLEN/8-1:0] PSTRB,
    input  logic                PWRITE,
    input  logic                PENABLE,
    output logic [P.XLEN-1:0]   PRDATA,
    output logic                PREADY,

    // -------------------------------------------------------------------------
    // VGA Physical Interface
    // -------------------------------------------------------------------------
    input  logic                VGA_CLK,    // VGA clock
    output logic                VGA_HS_O, // Horizontal Sync
    output logic                VGA_VS_O, // Vertical Sync
    output logic [3:0]          VGA_R,    // Red Channel
    output logic [3:0]          VGA_G,    // Green Channel
    output logic [3:0]          VGA_B     // Blue Channel
);

    // -------------------------------------------------------------------------
    // APB Logic & Registers (PCLK Domain)
    // -------------------------------------------------------------------------
    logic [2:0] color_registers; // [2] = Blue, [1] = Green, [0] = Red

    localparam RED_ADDR   = 4'h0;
    localparam GREEN_ADDR = 4'h4;
    localparam BLUE_ADDR  = 4'h8;

    logic [3:0] entry;
    assign entry = {PADDR[3:2], 2'b00}; // Word-aligned address decoding

    // Read operations
    always_ff @(posedge PCLK) begin: read_register
        if (~PRESETn) begin
            PRDATA <= '0;
        end else begin
            case(entry)
                RED_ADDR:   PRDATA <= { {(P.XLEN-1){1'b0}}, color_registers[0] };
                GREEN_ADDR: PRDATA <= { {(P.XLEN-1){1'b0}}, color_registers[1] };
                BLUE_ADDR:  PRDATA <= { {(P.XLEN-1){1'b0}}, color_registers[2] };
                default:    PRDATA <= '0;
            endcase
        end
    end

    // Write operations
    logic memwrite;
    assign memwrite = PWRITE & PENABLE & PSEL;

    always_ff @(posedge PCLK) begin: write_register
        if (~PRESETn) begin
            color_registers <= 3'b100;
        end else if (memwrite) begin
            case(entry)
                RED_ADDR:   color_registers[0] <= PWDATA[0];
                GREEN_ADDR: color_registers[1] <= PWDATA[0];
                BLUE_ADDR:  color_registers[2] <= PWDATA[0];
            endcase
        end
    end

    // Zero wait-state APB slave
    assign PREADY = 1'b1;

// -------------------------------------------------------------------------
    // VGA Constants (640x480@60Hz)
    // Pixel Clock required: ~25.0 MHz (25.175 MHz exact)
    // -------------------------------------------------------------------------
    localparam int FRAME_WIDTH  = 640;
    localparam int FRAME_HEIGHT = 480;

    localparam int H_FP  = 16;   // H front porch width (pixels)
    localparam int H_PW  = 96;   // H sync pulse width (pixels)
    localparam int H_BP  = 48;   // H back porch (pixels) - (Nota: H_MAX = WIDTH+FP+PW+BP)
    localparam int H_MAX = 800;  // H total period (pixels)

    localparam int V_FP  = 10;   // V front porch width (lines)
    localparam int V_PW  = 2;    // V sync pulse width (lines)
    localparam int V_BP  = 33;   // V back porch (lines)
    localparam int V_MAX = 525;  // V total period (lines)

    localparam logic H_POL = 1'b0;
    localparam logic V_POL = 1'b0;

    // -------------------------------------------------------------------------
    // VGA Signals
    // -------------------------------------------------------------------------
    logic pxl_clk;
    logic active;

    logic [11:0] h_cntr_reg = '0;
    logic [11:0] v_cntr_reg = '0;

    logic h_sync_reg = ~H_POL;
    logic v_sync_reg = ~V_POL;

    logic h_sync_dly_reg = ~H_POL;
    logic v_sync_dly_reg = ~V_POL;

    logic [3:0] vga_red_reg   = '0;
    logic [3:0] vga_green_reg = '0;
    logic [3:0] vga_blue_reg  = '0;

    logic [3:0] vga_red;
    logic [3:0] vga_green;
    logic [3:0] vga_blue;

    // Clock Domain Crossing (CDC) Synchronization
    // Synchronize APB color_registers (PCLK) into the VGA clock domain (pxl_clk)
    logic [2:0] color_sync;
    always_ff @(posedge VGA_CLK) begin
        color_sync <= color_registers;
    end

    // -------------------------------------------------------------------------
    // Solid Color Generation Logic
    // -------------------------------------------------------------------------
    always_comb begin
        if (active) begin
            // If in active display area, use the synchronized APB register values
            vga_red   = color_sync[0] ? 4'hF : 4'h0;
            vga_green = color_sync[1] ? 4'hF : 4'h0;
            vga_blue  = color_sync[2] ? 4'hF : 4'h0;
        end else begin
            // Blanking intervals must be completely dark
            vga_red   = 4'h0;
            vga_green = 4'h0;
            vga_blue  = 4'h0;
        end
    end

    // -------------------------------------------------------------------------
    // Sync Generation
    // -------------------------------------------------------------------------
    // Horizontal Counter
    always_ff @(posedge VGA_CLK) begin
        if (h_cntr_reg == (H_MAX - 1)) begin
            h_cntr_reg <= '0;
        end else begin
            h_cntr_reg <= h_cntr_reg + 1;
        end
    end

    // Vertical Counter
    always_ff @(posedge VGA_CLK) begin
        if ((h_cntr_reg == (H_MAX - 1)) && (v_cntr_reg == (V_MAX - 1))) begin
            v_cntr_reg <= '0;
        end else if (h_cntr_reg == (H_MAX - 1)) begin
            v_cntr_reg <= v_cntr_reg + 1;
        end
    end

    // Horizontal Sync
    always_ff @(posedge VGA_CLK) begin
        if ((h_cntr_reg >= (H_FP + FRAME_WIDTH - 1)) && (h_cntr_reg < (H_FP + FRAME_WIDTH + H_PW - 1))) begin
            h_sync_reg <= H_POL;
        end else begin
            h_sync_reg <= ~H_POL;
        end
    end

    // Vertical Sync
    always_ff @(posedge VGA_CLK) begin
        if ((v_cntr_reg >= (V_FP + FRAME_HEIGHT - 1)) && (v_cntr_reg < (V_FP + FRAME_HEIGHT + V_PW - 1))) begin
            v_sync_reg <= V_POL;
        end else begin
            v_sync_reg <= ~V_POL;
        end
    end

    // Active Region Flag
    assign active = ((h_cntr_reg < FRAME_WIDTH) && (v_cntr_reg < FRAME_HEIGHT));

    // Output Registers (Buffering to improve timing)
    always_ff @(posedge VGA_CLK) begin
        v_sync_dly_reg <= v_sync_reg;
        h_sync_dly_reg <= h_sync_reg;
        vga_red_reg    <= vga_red;
        vga_green_reg  <= vga_green;
        vga_blue_reg   <= vga_blue;
    end

    // Final Output Assignments
    assign VGA_HS_O = h_sync_dly_reg;
    assign VGA_VS_O = v_sync_dly_reg;
    assign VGA_R    = vga_red_reg;
    assign VGA_G    = vga_green_reg;
    assign VGA_B    = vga_blue_reg;

endmodule
