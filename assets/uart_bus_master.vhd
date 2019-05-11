library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_bus_master is
  generic(
    ADDR_WIDTH : natural :=8;
    DATA_WIDTH : natural :=32
    );
  port(
    reset_n : in  std_logic;
    clk     : in  std_logic;
    -- UART side
    rx      : in  std_logic;
    tx      : out std_logic;
    -- Bus side
    ce      : out std_logic;
    we      : out std_logic;
    address : out unsigned(7 downto 0);
    datain  : out std_logic_vector(DATA_WIDTH-1 downto 0);
    dataout : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    debug   : out std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of uart_bus_master is
  --
   constant NB_BYTES_PER_ADDR : natural := ADDR_WIDTH/8;
   subtype byte_a_type is natural range 0 to NB_BYTES_PER_ADDR;
   signal byte_a,byte_a_c : byte_a_type;

   constant NB_BYTES_PER_DATA : natural := DATA_WIDTH/8;
   subtype byte_d_type is natural range 0 to NB_BYTES_PER_DATA;
   signal byte_d,byte_d_c : byte_d_type;
  --
  signal rd_uart, wr_uart, wr_uart_c : std_logic;
  signal w_data, w_data_c            : std_logic_vector(7 downto 0);
  signal tx_full, rx_empty           : std_logic;
  signal r_data                      : std_logic_vector(7 downto 0);
  --
  signal data_from_pc_r              : std_logic_vector(7 downto 0);
  signal data_from_pc_valid_r        : std_logic;
  --
  type state_type is (
    IDLE, WRITING_RCV_ADDR, WRITING_RCV_DATA, WRITING_APPLY_PULSE,
    READING_RCV_ADDR, READING_APPLY_PULSE_WS, READING_APPLY_PULSE);
  signal state, state_c           : state_type;
  --
  signal sreset                   : std_logic;
  signal ce_r,ce_c                 : std_logic;
  signal we_r,we_c                 : std_logic;
  signal addr_r,addr_c             : std_logic_vector(7 downto 0);
  signal datain_r,data_c           : std_logic_vector(DATA_WIDTH-1 downto 0);
  -- debug
  signal slow_clk, slow_tick      : std_logic;
  signal done_read, done_read_c   : std_logic;
  signal done_write, done_write_c : std_logic;
  signal debug_idle : std_logic;
begin

  uart_1 : entity work.uart
    generic map (
      DBIT     => 8,
      SB_TICK  => 16,
      DVSR     => 325,
      DVSR_BIT => 9,
      FIFO_W   => 3)
    port map (
      clk      => clk,
      reset_n  => reset_n,
      rd_uart  => rd_uart,
      wr_uart  => wr_uart,
      rx       => rx,
      w_data   => w_data,
      tx_full  => tx_full,
      rx_empty => rx_empty,
      r_data   => r_data,
      tx       => tx);

  -- pump the internal UART FIFO *systematically* (when something is written in it)
  -- no accumulation in the FIFO
  rd_uart <= not(rx_empty);

  sampling_data_p : process(reset_n, clk)
  begin
    if reset_n = '0' then
      data_from_pc_r       <= (others => '0');
      data_from_pc_valid_r <= '0';
    elsif rising_edge(clk) then
      data_from_pc_valid_r <= '0';
      if rd_uart = '1' then
        data_from_pc_r <= r_data;
        data_from_pc_valid_r <= '1';
      end if;
    end if;
  end process;

  debug_idle <= '1' when state=IDLE else '0';
  debug <= "00000000" & data_from_pc_r(7 downto 0);
  --================= BUS bridge =================
  -- protocol using 8 bits UART :
  -- for write :
  -- byte 0 : 00010001=0x11
  -- byte 1 : address
  -- byte 2 : data
  -- for read :
  -- byte 0 : 00010000=0x10
  -- byte 1 : address
  -- =============================================
  tick : process(reset_n, clk)
  begin
    if reset_n = '0' then
      state      <= IDLE;
      ce_r       <= '0';
      we_r       <= '0';
      addr_r     <= (others => '0');
      datain_r   <= (others => '0');
      wr_uart    <= '0';
      w_data     <= (others => '0');
      done_read  <= '0';
      done_write <= '0';
      byte_a     <= NB_BYTES_PER_ADDR-1;
      byte_d     <= NB_BYTES_PER_DATA-1;
    elsif rising_edge(clk) then
      state      <= state_c;
      ce_r       <= ce_c;
      we_r       <= we_c;
      addr_r     <= addr_c;
      datain_r   <= data_c;
      wr_uart    <= wr_uart_c;
      w_data     <= w_data_c;
      done_read  <= done_read_c;
      done_write <= done_write_c;
      byte_a    <= byte_a_c;
      byte_d    <= byte_d_c;
    end if;
  end process;

  ce <= ce_r;
  we <= we_r;
  address <= unsigned(addr_r);
  datain  <= datain_r;

  comb : process(addr_r, data_from_pc_r, data_from_pc_valid_r, datain_r,
                 dataout, state, w_data, done_read, done_write,
                 byte_a,byte_d)
    variable state_v      : state_type;
    variable ce_v         : std_logic;
    variable we_v         : std_logic;
    variable addr_v       : std_logic_vector(7 downto 0);
    variable data_v       : std_logic_vector(DATA_WIDTH-1 downto 0);
    variable wr_uart_v    : std_logic;
    variable w_data_v     : std_logic_vector(7 downto 0);
    --debug
    variable done_read_v  : std_logic;
    variable done_write_v : std_logic;
    variable byte_a_v : byte_a_type;
    variable byte_d_v : byte_d_type;
  begin
    state_v      := state;
    --
    ce_v         := '0';
    we_v         := '0';
    addr_v       := addr_r;
    data_v       := datain_r;
    --
    wr_uart_v    := '0';
    w_data_v     := w_data;
    done_read_v  := done_read;
    done_write_v := done_write;
    byte_a_v     := byte_a;
    byte_d_v     := byte_d;

    case state_v is

      when IDLE =>
        if data_from_pc_valid_r = '1' then
          if data_from_pc_r = x"11" then
            state_v := WRITING_RCV_ADDR;
          elsif data_from_pc_r = x"10" then
            state_v := READING_RCV_ADDR;
          end if;
        end if;

      when WRITING_RCV_ADDR =>
        if data_from_pc_valid_r = '1' then
          addr_v((byte_a_v+1)*8-1 downto byte_a_v*8) := data_from_pc_r;--WHEN addr is 8 bits
          if byte_a_v/=0 then
            byte_a_v:=byte_a_v-1;
          else
            byte_a_v:=NB_BYTES_PER_ADDR-1;
            state_v := WRITING_RCV_DATA;
          end if;
        end if;

      when WRITING_RCV_DATA =>
        if data_from_pc_valid_r = '1' then
          data_v((byte_d_v+1)*8-1 downto byte_d_v*8) := data_from_pc_r;
          if byte_d_v /=0 then
            byte_d_v := byte_d_v-1;
          else
            ce_v    := '1';
            we_v    := '1';
            byte_d_v   := NB_BYTES_PER_DATA-1;
            state_v     := IDLE;
            done_read_v := '1';
          end if;
        end if;

      when READING_RCV_ADDR =>
        if data_from_pc_valid_r = '1' then
          addr_v((byte_a_v+1)*8-1 downto byte_a_v*8) := data_from_pc_r;--WHEN addr is 8 bits
          if byte_a_v/=0 then
            byte_a_v:=byte_a_v-1;
          else
            ce_v    := '1';
            we_v    := '0';
            byte_a_v:=NB_BYTES_PER_ADDR-1;
            state_v := READING_APPLY_PULSE_WS;
          end if;
        end if;

      when READING_APPLY_PULSE_WS =>
        state_v := READING_APPLY_PULSE;

      when READING_APPLY_PULSE =>
        wr_uart_v   := '1';
        w_data_v    := dataout((byte_d_v+1)*8-1 downto (byte_d_v*8));
        if byte_d_v /=0 then
          byte_d_v := byte_d_v-1;
        else
          byte_d_v   := NB_BYTES_PER_DATA-1;
          state_v     := IDLE;
          done_read_v := '1';
        end if;
      when others =>
        null;
    end case;

    state_c     <= state_v;
    --
    ce_c        <= ce_v;
    we_c        <= we_v;
    addr_c      <= addr_v;
    data_c      <= data_v;
    --
    wr_uart_c   <= wr_uart_v;
    w_data_c    <= w_data_v;
    done_read_c <= done_read_v;
    done_read_c <= done_write_v;
    byte_a_c   <= byte_a_v;
    byte_d_c   <= byte_d_v;

  end process;

end rtl;
