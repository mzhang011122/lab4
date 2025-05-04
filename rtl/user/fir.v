module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 10 //actually Tape_Num is Tape_Num+1
)
(
    output  wire                     awready, // coefficients address ready to accept from tb, not used
    output  wire                      wready,  // coefficients ready to accept from tb
    input   wire                     awvalid, // coefficients address valid
    input   wire [(pADDR_WIDTH-1):0] awaddr,  // coefficients address
    input   wire                     wvalid, // coefficients valid
    input   wire [(pDATA_WIDTH-1):0] wdata,  //coefficients comes from here

    //can be either check coefficients or ap_done/ap_idle
    output  wire                     arready, // data address ready to accept from tb, not used
    input   wire                     rready, // tb is ready to accept data
    input   wire                     arvalid, // read address from tb is valid
    input   wire [(pADDR_WIDTH-1):0] araddr, // read address from tb
    output  reg                      rvalid, // data to tb valid
    output  reg  [(pDATA_WIDTH-1):0] rdata,  // data to tb

    input   wire                     ss_tvalid, //data stream in valid
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, //data stream in
    input   wire                     ss_tlast, //data stream in last
    output  reg                      ss_tready, //ready to accept data stream in

    input   wire                     sm_tready, //tb ready to accept data stream out
    output  reg                      sm_tvalid, //data stream out valid
    output  reg  [(pDATA_WIDTH-1):0] sm_tdata, //data stream out
    output  reg                      sm_tlast, //data stream out last
    
    // bram for tap RAM
    output  reg  [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  reg  [(pDATA_WIDTH-1):0] tap_Di,
    output  wire   [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg  [3:0]               data_WE,
    output  wire                     data_EN,
    output  reg  [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
// states
localparam S_RESET_RAM = 0;
localparam S_COMPUTE = 1;
localparam S_READY = 2;
localparam S_DONE = 3;
localparam S_FIN = 4;
localparam S_WAIT_START = 5;

// regs and wires declaration
reg ap_done_w, ap_done_r;
reg ap_idle_w, ap_idle_r;
reg ap_start_w, ap_start_r;
reg rvalid_w;
reg [(pDATA_WIDTH-1):0] rdata_w;
reg read_axil_wait_w, read_axil_wait_r;
reg tap_A_read, tap_A_write;
reg [(pDATA_WIDTH-1):0] data_len_w,data_len_r;
wire [31:0] addr_map_0_data;
reg [3:0] data_A_byte;

reg [3:0] state_w, state_r;


reg [3:0] data_addr_cnt_w, data_addr_cnt_r;
reg [3:0] data_addr_base_w, data_addr_base_r;
reg [(pDATA_WIDTH-1):0] res_w,res_r;

reg last_one_w, last_one_r;

wire [31:0] mac_result;

// assignment
assign addr_map_0_data = {{29{1'b0}},ap_idle_r,ap_done_r,ap_start_r};
assign tap_EN = 1'b1;
assign data_EN = 1'b1;
assign tap_A =  tap_A_write ? awaddr-64 : 
                tap_A_read ? araddr-64 : data_addr_cnt_r<<2;
assign wready = awvalid && wvalid;
assign awready = awvalid && wvalid;
assign data_A = data_A_byte << 2;

assign arready = 1;

assign mac_result = $signed(res_r) + $signed($signed(data_Do) * $signed(tap_Do));
//module instances

// reg [64:0] cycle_cnt;
// always @(posedge axis_clk or negedge axis_rst_n) begin
//     if(!axis_rst_n) begin
//         cycle_cnt <= 0;
//     end 
//     else begin
//         cycle_cnt <= cycle_cnt + 1;
//     end
// end



// combinational block

//state machine
always @(*) begin
    state_w = state_r;
    case (state_r)
        S_RESET_RAM:begin
            if(data_addr_cnt_r == Tape_Num)begin
                //$display("RESET_RAM DONE");
                state_w = S_WAIT_START;
            end
        end
        S_WAIT_START:begin
            if(ap_start_r)begin
                //$display("AP START RECEIVED");
                state_w = S_READY;
            end
        end
        S_READY:begin
            if(ss_tvalid)begin
                state_w = S_COMPUTE;
            end
        end
        S_COMPUTE:begin
            if(data_addr_cnt_r == Tape_Num)begin
                state_w = S_DONE;
            end
        end
        S_DONE:begin
            if(sm_tready)begin
                //$display("sm_tdata = %d", $signed(res_r));
                if(last_one_r) 
                    state_w = S_FIN;
                else
                    state_w = S_READY;
            end
        end
        
    endcase
end

//debug

// always @(posedge axis_clk)begin
//     case (state_r)
//         S_COMPUTE:begin
//             $display("---------------------------------------");
//             $display("tap_Do = %d", $signed(tap_Do));
//             $display("data_Do = %d", $signed(data_Do));
//             $display("data_addr_cnt_r = %d", data_addr_cnt_r);
//             $display("mac_result = %d", $signed(mac_result));
//             $display("---------------------------------------");
//         end
//     endcase
// end

//computation part
always @(*) begin
    data_addr_cnt_w = data_addr_cnt_r;
    data_WE = 4'b0000;
    data_Di = 0;
    data_A_byte = 0;
    ap_done_w = ap_done_r;
    ap_idle_w = ap_idle_r;
    data_addr_base_w = data_addr_base_r;
    last_one_w = last_one_r;

    ss_tready = 0;
    sm_tvalid = 0;
    sm_tdata = 0;
    res_w = res_r;
    case (state_r)
        S_RESET_RAM:begin
            data_WE = 4'b1111;
            data_Di = 0;
            data_A_byte = data_addr_cnt_r;
            if (data_addr_cnt_r == Tape_Num)begin
                data_addr_cnt_w = data_addr_cnt_r;
                ap_idle_w = 0;
            end
            else begin
                data_addr_cnt_w = data_addr_cnt_r + 1;
            end
        end

        S_WAIT_START:begin
            data_addr_cnt_w = 0;
        end

        S_READY:begin
            ss_tready = 1;
            res_w = 0;

            if(ss_tvalid)begin
                //$display("ss_tdata = %d", $signed(ss_tdata));
                data_Di = ss_tdata;
                data_WE = 4'b1111;
                data_A_byte = data_addr_base_r;
            end
        end
        S_COMPUTE:begin
            res_w = mac_result;
            data_A_byte = (data_addr_base_r + data_addr_cnt_r > Tape_Num) ? 
                        data_addr_base_r + data_addr_cnt_r - Tape_Num - 1 : 
                        data_addr_base_r + data_addr_cnt_r;
            if(data_addr_cnt_r == Tape_Num)begin
                data_addr_cnt_w = 0;
                if(data_addr_base_r == 0)begin
                    data_addr_base_w = Tape_Num;
                end
                else begin
                    data_addr_base_w = data_addr_base_r - 1;
                end
                if(ss_tlast)begin
                    ap_done_w = 1;
                    ap_idle_w = 1;
                end
            end
            else begin
                data_addr_cnt_w = data_addr_cnt_r + 1;
            end
        end
        S_DONE:begin
            sm_tvalid = 1;
            sm_tdata = res_r;
            if(sm_tready)begin
                res_w = 0;
                last_one_w = ss_tlast;
            end
        end
        S_FIN:begin
        end

    endcase
end

//write axil
always @(*) begin
    tap_A_write = 0;
    tap_Di = 0;
    tap_WE = 0;
    ap_start_w = 0;
    data_len_w = data_len_r;
    if(awvalid && wvalid)begin
        // $display("awaddr = %d",awaddr);
        // $display("wdata = %d, at cycle = %d",$signed(wdata),cycle_cnt);
        if(awaddr >= 64)begin
            tap_A_write = 1;
            tap_Di = wdata;
            tap_WE = 4'b1111;
        end
        else begin
            if (awaddr == 0)begin
                ap_start_w = 1;
            end
            else begin // write data length
                data_len_w = wdata;
            end
        end
    end
end

//read axil
always @(*) begin
    rvalid_w = 0;
    rdata_w = 0;
    read_axil_wait_w = 0;
    tap_A_read = 0;
    if(arvalid)begin
        //$display("araddr = %d",araddr);
        if(araddr == 0)begin
            rdata_w = addr_map_0_data;
            rvalid_w = 1;
            //$display("rdata = %b, at cycle = %d",addr_map_0_data[5:0],cycle_cnt);
        end
        else begin
            if(read_axil_wait_r == 0) begin
                read_axil_wait_w = 1;
                tap_A_read = 1;
            end
            else begin
                rdata_w = tap_Do;
                rvalid_w = 1;
            end
            
        end
    end
end


// sequencial block
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
        // reset
        //$display("-----------reset-----------");
        ap_done_r <= 1'b0;
        ap_idle_r <= 1'b1; //not sure
        ap_start_r <= 1'b0;
        rdata <= 0;
        rvalid <= 0;
        read_axil_wait_r <= 0;
        data_len_r <= 0;
        data_addr_cnt_r <= 0;
        state_r <= S_RESET_RAM;
        data_addr_base_r <= Tape_Num;
        res_r <= 0;
        last_one_r <= 0;
    end 
    else begin
        // normal
        ap_done_r <= ap_done_w;
        ap_idle_r <= ap_idle_w;
        ap_start_r <= ap_start_w;
        rdata <= rdata_w;
        rvalid <= rvalid_w;
        read_axil_wait_r <= read_axil_wait_w;
        data_len_r <= data_len_w;
        data_addr_cnt_r <= data_addr_cnt_w;
        state_r <= state_w;
        data_addr_base_r <= data_addr_base_w;
        res_r <= res_w;
        last_one_r <= last_one_w;
    end
end
endmodule

