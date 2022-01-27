require 'fileutils'

require_relative 'code'

module Reggae

  class VHDLGenerator < Visitor

    def initialize options
      super()
      @options=options
      @verbose=options[:verbose]
      @work=@options[:work]||'work'
      @vhdl_entity_arch=nil
      @vhdl_pkg=nil
      @vhdl_files=[]
    end

    #.......................VHDL.......................
    def generate_from model
      $working_dir||=Dir.pwd
      @dest_dir=$working_dir+"/hdl"
      if !Dir.exists?(@dest_dir)
        FileUtils.mkdir(@dest_dir)
      end
      begin
        inc
        model.accept(self,nil)
        #gen_testbench
        gen_compile_script
        gen_synthesis_script
        gen_ruby_sw_if(model) if @options[:gen_ruby]
        dec
      rescue Exception => e
        puts e.backtrace
        puts e
      end
      return @vhdl_files
    end

    def now
      time = Time.new
      time.ctime
    end

    def header
      code=Code.new
      code << "-"*80
      code << "-- Generated automatically by Reggae compiler "
      code << "-- (c) Jean-Christophe Le Lann - 2011"
      code << "-- date : #{now}"
      code << "-"*80
      #code.newline
      code << "library ieee,std;"
      code << "use ieee.std_logic_1164.all;"
      code << "use ieee.numeric_std.all;"
      code.newline
      code
    end

    def clock_and_reset
      code=Code.new
      code << "reset_n : in  std_logic;"
      code << "clk     : in  std_logic;"
      code << "sreset  : in  std_logic;"
      code
    end

    def visitMemoryMap mm,args=nil
      inc "MemoryMap"
      @model_name=mm.name
      @addr_size=mm.parameters.bus.address_size
      @data_size=mm.parameters.bus.data_size

      mm.parameters.accept(self,nil)
      mm.zones.each{|zone| zone.accept(self,nil)}
      if @options[:gen_system]
        gen_system(mm)
        unless @options[:include_uart]
          puts "WARNING : no uart included. -u to add it if wanted."
        end
      end
      dec
    end

    def visitZone zone,args=nil
      inc "Zone"
      gen_ip_pkg(zone)
      if zone.registers.any?
        gen_ip_regif(zone)
        gen_ip_entity_arch(zone)
      elsif zone.brams.any?
        gen_ip_brams(zone)
      end
      if @options[:gen_xdc]
        gen_xdc(zone)
      end
      dec
    end

    def gen_ip_pkg zone
      filename=zone.name.to_s+"_pkg.vhd"
      puts "   - code for IP package"+(" "+filename).rjust(38,'.')
      code=Code.new
      code << header
      code << "package #{zone.name}_regif_pkg is"
      code.indent=2
      zone.registers.each do |reg|
        code.newline
        code << "type #{reg.name}_reg is record"
        code.indent=4
        tmp_h={}
        reg.bits.each do |bit|
          tmp_h[bit.name]="std_logic;"
        end
        reg.bitfields.each do |bitf|
          min,max=bitf.position.minmax
          nb_bits=(max-min)
          tmp_h[bitf.name]="std_logic_vector(#{nb_bits} downto 0);"
        end
        max_justify=tmp_h.keys.map(&:size).max
        tmp_h.each do |name,type|
          code << "#{name.to_s.ljust(max_justify,' ')} : #{type}"
        end
        code.indent=2
        code << "end record;"
        code.newline
        code << "constant #{reg.name.upcase}_INIT: #{reg.name}_reg :=("
        code.indent=4
        tmp_h={}
        init_reg=reg.init.to_i(16).to_s(2).rjust(@data_size,'0')

        reg.bits.each do |bit|
          pos=bit.position
          init_value=init_reg[@data_size-pos-1]
          tmp_h[bit.name]="'#{init_value}'"
        end

        reg.bitfields.each do |bitf|
          min,max=bitf.position.minmax
          size=(max-min)+1
          bitf.position
          range=(@data_size-max-1)..(@data_size-min-1)
          init_value=init_reg[range]
          init_value=init_value.rjust(size,'0')
          tmp_h[bitf.name]="\"#{init_value}\""
        end

        max_justify=tmp_h.keys.map(&:size).max
        tmp_h.each do |name,value|
          code << "#{name.to_s.ljust(max_justify,' ')} => #{value},"
        end
        code.indent=2

        code << ");"
      end

      if zone.registers.any?
        code.newline
        code << "type registers_type is record"
        code.indent=4
        max_just=zone.registers.map{|reg| reg.name.size}.max
        zone.registers.each do |reg|
          code << "#{reg.name.to_s.ljust(max_just,' ')} : #{reg.name}_reg; -- #{reg.address}"
        end
        code.indent=2
        code << "end record;"

        code.newline
        code << "constant REGS_INIT : registers_type :=("
        code.indent=4
        max_just=zone.registers.map{|reg| reg.name.size}.max
        zone.registers.each do |reg|
          code << "#{reg.name.to_s.ljust(max_just,' ')} => #{reg.name.upcase}_INIT,"
        end
        code.indent=2
        code << ");"
        code.newline

        code << "--sampling values from IPs"
        code << "type sampling_type is record"
        code.indent=4
        zone.registers.each do |reg|

          if reg.sampling
            reg.bits.each do |bit|
              type="std_logic"
              code << "#{reg.name.to_s}_#{bit.name} : #{type};"
            end
            reg.bitfields.each do |bitf|
              min,max=bitf.position.minmax
              nb_bits=(max-min)
              type="std_logic_vector(#{nb_bits} downto 0)"
              code << "#{reg.name.to_s}_#{bitf.name} : #{type};"
            end
          else
            code << "dummy : std_logic;"
          end
        end
        code.indent=2
        code << "end record;"
      end # registers

      code.indent=0
      code.newline
      code << "end package;"
      @vhdl_files << vhdl="#{@dest_dir}/#{zone.name}_regif_pkg.vhd"
      #@vhdl_files << vhdl="#{zone.name}_regif_pkg.vhd"
      code.save_as(vhdl,verbose=false)
    end

    def gen_ip_regif zone
      filename=zone.name.to_s+"_reg.vhd"
      puts "   - code for IP register interface "+(" "+filename).rjust(26,'.')
      code=Code.new
      code << header
      if @work!='work'
        code << "library #{@work};"
      end
      code << "use #{@work}.#{zone.name}_regif_pkg.all;"
      code.newline
      code << "entity #{zone.name}_reg is"
      code.indent=2
      code << "port("
      code.indent=4
      code << clock_and_reset
      code << "ce        : in  std_logic;"
      code << "we        : in  std_logic;"
      code << "address   : in  unsigned(#{@addr_size-1} downto 0);"
      code << "datain    : in  std_logic_vector(#{@data_size-1} downto 0);"
      code << "dataout   : out std_logic_vector(#{@data_size-1} downto 0);"
      code << "registers : out registers_type;"
      code << "sampling  : in sampling_type;"
      code.indent=2
      code << ");"
      code.indent=0
      code << "end #{zone.name}_reg;"
      code.newline
      code << "architecture RTL of #{zone.name}_reg is"
      code.newline
      code.indent=2
      code << "--interface"
      code << "signal regs : registers_type;"
      code.newline
      code << "--addresses are declared here to avoid VHDL93 error /locally static/"
      tmp_h={}
      zone.registers.each do |reg|
        addr_vhdl=reg.address.to_i(16)
        addr_vhdl_b2=addr_vhdl.to_s(2).rjust(@addr_size,'0')
        nb_digits_hex=(@addr_size/4.0).ceil
        addr_vhdl=addr_vhdl.to_s.rjust(nb_digits_hex,'0')
        addr_name="ADDR_#{reg.name.upcase}"
        tmp_code=": unsigned(#{@addr_size-1} downto 0) := \"#{addr_vhdl_b2}\";-- 0x#{addr_vhdl};"
        tmp_h[addr_name]=tmp_code
      end
      max_length_addr_name=(tmp_h.keys.max_by{|e|e.size}||[]).size
      #pp tmp_h

      tmp_h.each do |addr,kode|
        code << "constant #{addr.ljust(max_length_addr_name,' ')} #{kode}"
      end
      code.newline
      code << "--application signals"
      code << declare_application_sampling_signals(zone)
      code.indent=0
      code.newline
      code << "begin"
      code.newline
      code.indent=2
      #---- write process
      code << "write_reg_p : process(reset_n,clk)"
      code << "begin"
      code.indent=4
      code << "if reset_n='0' then"
      code.indent=6
      code << "regs <= REGS_INIT;"
      code.indent=4
      code << "elsif rising_edge(clk) then"
      code.indent=6
      code << "if ce='1' then"
      code.indent=8
      code << "if we='1' then"
      code.indent=10
      code << "case address is"
      code.indent=12
      zone.registers.each do |reg|
        if reg.writable
          code << "when ADDR_#{reg.name.upcase} =>"
          code.indent=14
          code << gen_reg_write(reg)
          code.indent=12
        end
      end
      code << "when others =>"
      code.indent=14
      code << "null;"
      code.indent=12
      code.indent=10
      code << "end case;"
      code.indent=8
      code << "end if;";
      code.indent=6
      code << "else --no bus preemption => sampling or toggle"
      code << "--sampling"
      code.indent=8
      no_sampling=zone.registers.collect{|r| r.sampling}
      no_sampling=zone.registers.collect{|r| r.sampling}.compact.empty?
      if no_sampling
         code << "null; --no_sampling"
      else
        zone.registers.each do |reg|
          code.indent=8
          if reg.sampling
            code << gen_reg_sampling(reg)
          end
          code.indent=6
        end
      end
      code << "--toggling"
      zone.registers.each do |reg|
        code.indent=8

        toggling_bits=reg.bits.collect{|bit| bit.toggle}.compact
        if toggling_bits
          code << gen_reg_toggle(reg)
        end
        code.indent=6
        end
      code.indent=6
      code << "end if;"
      code.indent=4
      code << "end if;"
      code.indent=2
      code <  def gen_processes_for_registers zone
    end< "end process;"
      #-----END write process
      code.newline
      code << "read_reg_p: process(reset_n,clk)"
      code << "begin"
      code.indent=4
      code << "if reset_n='0' then"
      code.indent=6
      code << "dataout <= (others=>'0');"
      code.indent=4
      code << "elsif rising_edge(clk) then"
      code.indent=6
      # code << "dataout <= (others=>'0');"
      code <  def gen_processes_for_registers zone
    end< "if ce='1' then"
      code.indent=8
      code << "if we='0' then"
      code.indent=10
      code << "dataout <= (others=>'0');"
      code << "case address is"
      code.indent=12
      zone.registers.each do |reg|
        code << gen_reg_read(reg)
      end
      code << "when others=>"
      code.indent=14
      code << "dataout <= (others=>'0');"
      code.indent=12
      code.indent=10
      code << "end case;"
      code.indent=8
      code << "end if;"
      code.indent=6
      code << "end if;"
      code.indent=4
      code << "end if;"
      code.indent=2
      code << "end process;"
      #-----
      code << "registers <= regs;"
      code.indent=0
      code.newline
      #code << gen_vivadohls_instances(zone)
      code << "end RTL;"
      filename="#{@dest_dir}/#{zone.name}_regif.vhd"
      #filename="#{zone.name}_regif.vhd"
      code.save_as filename,verbose=false
      @vhdl_files << filename
      code
    end

    def gen_ip_entity_arch zone
      filename=zone.name.to_s+".vhd"
      puts "   - code for IP "+(" "+filename).rjust(45,'.')
      code=Code.new
      code << header
      code << "use #{@work}.#{zone.name}_regif_pkg.all;"
      code.newline
      code << "entity #{zone.name} is"
      code.indent=2
      code << "port("
      code.indent=4
      code << clock_and_reset
      code << "ce      : in  std_logic;"
      code << "we      : in  std_logic;"
      code << "address : in  unsigned(#{@addr_size-1} downto 0);"
      code << "datain  : in  std_logic_vector(#{@data_size-1} downto 0);"
      code << "dataout : out std_logic_vector(#{@data_size-1} downto 0);"
      code.indent=2
      code << ");"
      code.indent=0
      code << "end #{zone.name};"
      code.newline
      code << "architecture RTL of #{zone.name} is"
      code.newline
      code.indent=2
      code << "--interface"
      code << "signal regs      : registers_type;"
      code << "signal sampling  : sampling_type;"
      code.newline
      code.indent=0
      code << "begin"
      code.newline
      code.indent=2
      code << gen_regif_instance(zone)
      code.newline
      code << gen_vivadohls_instances(zone)
      code.newline
      code.indent=0
      code << "end RTL;"
      filename="#{@dest_dir}/#{zone.name}.vhd"
      #filename="#{zone.name}.vhd"
      code.save_as filename,verbose=false
      if @options[:show_code]
        puts code.finalize
      end
      @vhdl_files << filename
      code
    end

    def writing_process mm
      code=Code.new
      code << "-- writing process"
      code << "write_proc: process(clk)"
      code << "begin"
      code.indent=2
      code << "if reset_n='0' then"
      code.indent=4
      code << "regs <= REGS_INIT;"
      code.indent=2
      code << "elsif rising_edge(clk) then"
      code.indent=4
      code << "if sreset='1' then"
      code.indent=6
      code << "regs <= REGS_INIT;"
      code.indent=4
      code << "else"
      code.indent=6
      code << "if ce='1' and we='1' then "

      code.indent=8
      code << "case address is "
      code.indent=10
      for zone in mm.zones
        code << "--zone #{zone.name.to_s.upcase.center(40,'-')}"
        for reg in zone.registers
          name="#{zone.name.upcase}_#{reg.name.upcase}"
          code << "when ADDR_#{zone.name.upcase}_#{reg.name.upcase} =>"
          code.indent=12
          code << "reg(#{name}) <= datain;"
          code.indent=10
        end
      end
      code << "when others => null;"
      code.indent=8
      code << "end case;"
      code.indent=6
      code << "end if;"
      code.indent=4
      code << "end if;"
      code.indent=2
      code << "end if;"
      code.indent=0
      code << "end process;"
      code
    end

    def gen_regif_instance zone
      code=Code.new
      code << "regif_inst : entity #{@work}.#{zone.name}_reg"
      code.indent=2
      code << "port map("
      code.indent=4
      code << "reset_n   => reset_n,"
      code << "clk       => clk,"
      code << "sreset    => sreset,"
      code << "ce        => ce,"
      code << "we        => we,"
      code << "address   => address,"
      code << "datain    => datain,"
      code << "dataout   => dataout,"
      code << "registers => regs,"
      code << "sampling  => sampling"
      code.indent=2
      code << ");"
      code.indent=0
      code
    end

    # in sexp, we can instanciate components
    # WARNING : default clk and reset are hardcoded here !!!!
    def gen_vivadohls_instances zone
      code=Code.new
      if zone.instances.any?
        zone.instances.each do |inst|
          @vhdl_files << inst.name.to_s+".vhd"
          code << "inst_#{inst.name} : entity #{@work}.#{inst.name}"
          code.indent=2
          code << "port map("
          code.indent=4
          if  @options[:from_vivado_hls]
            code << "ap_clk => clk,"
          else #standard mode
            code << "reset_n => reset_n,"
            code << "clk     => clk,"
          end
          inst.mapping.each do |cnx|
            if cnx.formal.is_a? Input
              sig="regs."+cnx.actual.name.to_s+"."+cnx.actual.field.to_s
            else
              sig="sampling.#{cnx.actual.name}_#{cnx.actual.field}"
            end
            code << "#{cnx.formal.name} => #{sig},"
          end
          code.indent=2
          code << ");"
          code.indent=0
        end
        code.newline
      end

      code
    end

    def declare_application_sampling_signals zone
      code=Code.new
      tmp_h={}
      zone.registers.each do |reg|
        if reg.sampling
          reg.bits.each do |bit|
            sig_name="#{reg.name}_#{bit.name}"
            tmp_h[sig_name]="std_logic;"
          end
          reg.bitfields.each do |bitfield|
            min,max=bitfield.position.minmax
            nb_bits=(max-min)
            sig_name="#{reg.name}_#{bitfield.name}"
            tmp_h[sig_name]="std_logic_vector(#{nb_bits} downto 0);"
          end
        end
      end
      max_size=(tmp_h.keys.max_by{|e|e.size} || []).size
      tmp_h.each do |signame,decl|
        code << "signal #{signame.ljust(max_size,' ')} : #{decl}"
      end
      code
    end

    def gen_reg_write reg
      code=Code.new
      reg.bits.each do |bit|
        code << "regs.#{reg.name}.#{bit.name} <= datain(#{bit.position});"
      end
      reg.bitfields.each do |bitfield|
        min,max=bitfield.position.minmax
        code << "regs.#{reg.name}.#{bitfield.name} <= datain(#{max} downto #{min});"
      end
      if code.empty?
        code << "regs.#{reg.name} <= datain;"
      end
      code
    end

    def gen_reg_read reg
      code=Code.new
      code << "when ADDR_#{reg.name.upcase} =>"
      code.indent=2
      reg.bits.each do |bit|
        code << "dataout(#{bit.position}) <= regs.#{reg.name}.#{bit.name};"
      end
      reg.bitfields.each do |bitfield|
        min,max=bitfield.position.minmax
        code << "dataout(#{max} downto #{min}) <= regs.#{reg.name}.#{bitfield.name};"
      end
      code.indent=0
      code
    end

    def gen_reg_sampling reg
      code=Code.new
      reg.bits.each do |bit|
        sig="sampling.#{reg.name}_#{bit.name}"
        code << "regs.#{reg.name}.#{bit.name} <= #{sig};"
      end
      reg.bitfields.each do |bitfield|
        sig="sampling.#{reg.name}_#{bitfield.name}"
        code << "regs.#{reg.name}.#{bitfield.name} <= #{sig};"
      end
      code
    end

    def gen_reg_toggle reg
      code=Code.new
      reg.bits.each do |bit|
        if bit.toggle
          bit_init="'0'"
          code << "regs.#{reg.name}.#{bit.name} <= #{bit_init};"
        end
      end
      reg.bitfields.each do |bitfield|
        if bitfield.toggle
          min,max=bitfield.position.minmax
          bitfield_init="0"*((max-min)+1)
          code << "regs.#{reg.name}.#{bitfield.name} <= \"#{bitfield_init}\";"
        end
      end
      code
    end

    #================= System stuff ================
    def gen_system mm
      filename="#{@dest_dir}/#{mm.name}.vhd"
      generate_assets
      puts "   - code for complete system "+(" "+filename).rjust(32,".") unless @options[:mute]
      code=Code.new
      code << header
      code << "entity #{mm.name} is"
      code.indent=2
      code << "port("
      code.indent=4
      code << "reset_n : in std_logic;"
      code << "clk     : in  std_logic;"
      code << "rx      : in  std_logic;"
      code << "tx      : out std_logic;"
      code << "leds    : out std_logic_vector(15 downto 0)"
      code.indent=2
      code << ");"
      code.indent=0
      code << "end entity;"
      code.newline

      code << gen_system_architecture(mm)
      puts code.finalize if @options[:show_code]
      code.save_as(filename,verbose=false)
      @vhdl_files << filename
    end

    def generate_assets
      puts "   - code for assets"+"<8 vhdl files>".rjust(42,'.') unless @options[:mute]
      dir=__dir__
      assets_dir=dir+"/../../assets/"
      #vhdl_assets=Dir["#{assets_dir}/*.vhd"]
      vhdl_assets=[
        "mod_m_counter.vhd",
        "fifo.vhd",
        "flag_buf.vhd",
        "uart_rx.vhd",
        "uart_tx.vhd",
        "uart.vhd",
        "slow_ticker.vhd",
        "uart_bus_master.vhd",
        "bram_xilinx.vhd",
      ]
      dest_dir=$working_dir+"/assets"
      if !Dir.exists?(dest_dir)
        FileUtils.mkdir(dest_dir)
      end
      vhdl_assets.each do |file|
        FileUtils.cp(assets_dir+file,dest_dir)
        @vhdl_files << "../assets/"+File.basename(file)
      end

    end

    def gen_synthesis_script
      dest_dir=$working_dir #+"/synthesis"
      filename="#{dest_dir}/synthesis.tcl"
      if !Dir.exists?(dest_dir)
        FileUtils.mkdir(dest_dir)
      end
      code=Code.new
      code << "# =====FPGA device : Artix7 in Nexys4DDR"
      code << "set partname \"xc7a100tcsg324-1\""
      code << "set xdc_constraints \"./Nexys4DDR_Master.xdc\""
      code.newline
      code << "# =====Define output directory"
      code << "set outputDir ./SYNTH_OUTPUTS"
      code << "file mkdir $outputDir"
      code.newline
      code << "# =====Setup design sources and constraints"
      code << "read_vhdl [ glob ../assets/*.vhd]"
      code << "read_vhdl [ glob ../hdl/*.vhd]"
      code << "read_xdc $xdc_constraints"
      code.newline
      code << "synth_design -top #{@model_name} -part $partname"
      code << "write_checkpoint -force $outputDir/post_synth.dcp"
      code << "report_timing_summary -file $outputDir/post_synth_timing_summary.rpt"
      code << "report_utilization -file $outputDir/post_synth_util.rpt"
      code << "opt_design"
      code << "# reportCriticalPaths $outputDir/post_opt_critpath_report.csv"
      code << "place_design"
      code << "# report_clock_utilization -file $outputDir/clock_util.rpt"
      code << "#"
      code << "write_checkpoint -force $outputDir/post_place.dcp"
      code << "report_utilization -file $outputDir/post_place_util.rpt"
      code << "report_timing_summary -file $outputDir/post_place_timing_summary.rpt"
      code.newline
      code << "# ====== run the router, write the post-route design checkpoint, report the routing"
      code << "# status, report timing, power, and DRC, and finally save the Verilog netlist."
      code << "#"
      code << "route_design"
      code << "write_checkpoint -force $outputDir/post_route.dcp"
      code << "report_route_status -file $outputDir/post_route_status.rpt"
      code << "report_timing_summary -file $outputDir/post_route_timing_summary.rpt"
      code << "report_power -file $outputDir/post_route_power.rpt"
      code << "report_drc -file $outputDir/post_imp_drc.rpt"
      code << "# write_verilog -force $outputDir/cpu_impl_netlist.v -mode timesim -sdf_anno true"
      code.newline
      code << "# ====== generate a bitstream"
      code << "write_bitstream -force $outputDir/top.bit"
      code << "exit"
      code.save_as(filename,verbose=false)

      dir=__dir__
      assets_dir=dir+"/../../assets/"
      file="Nexys4DDR_Master.xdc"
      FileUtils.cp(assets_dir+file,dest_dir)
    end

    def gen_compile_script
      dest_dir=$working_dir+"/hdl"
      if !Dir.exists?(dest_dir)
        FileUtils.mkdir(dest_dir)
      end
      File.open("#{dest_dir}/compile.x",'w') do |f|
        f.puts "echo \"=> cleaning\""
        f.puts "rm -rf *.o"
        f.puts
        f.puts "echo \"=> analyzing VHDL files\""
        @vhdl_files.each do |vhdl|
          f.puts "echo \"=> analyzing #{vhdl}\""
          f.puts "ghdl -a #{vhdl}"
        end
        f.puts "echo \"=> elaboration\""
        top=File.basename(@vhdl_files.last,".vhd")
        f.puts "ghdl -e #{top}"
        #f.puts "echo \"=> running simulation
        #f.puts "ghdl -r #{top} --wave=#{top}.ghw"
        #f.puts "echo \"=> viewing waveforms\""
        #f.puts "gtkwave #{top}.ghw #{top}.sav"
        puts "=> compile script"+" compile.x".rjust(45,'.')
      end
    end

    def gen_system_architecture mm
      code=Code.new
      code << "architecture rtl of #{mm.name} is"
      code.indent=2
      code << "-- bus"
      code << "signal ce      : std_logic;"
      code << "signal we      : std_logic;"
      code << "signal address : unsigned(#{@addr_size-1} downto 0);"
      code << "signal datain  : std_logic_vector(#{@data_size-1} downto 0);"
      code << "signal dataout : std_logic_vector(#{@data_size-1} downto 0);"
      code << "--"
      code << "signal sreset  : std_logic;"
      code << "-- debug"
      code << "signal slow_clk,slow_tick : std_logic;"
      code.newline
      code.indent=0
      code << "begin"
      code.indent=2
      code.newline
      code << instance_of_uart_bus_master if @options[:include_uart]
      code << ip_instanciations(mm)
      code << debug_stuff
      code.newline
      code.indent=0
      code << "end;"
      code
    end

    def instance_of_uart_bus_master
      code=Code.new
      code << "-- ============== UART as Master of bus !========="
      code << "uart_master : entity #{@work}.uart_bus_master"
      code << "  generic map (DATA_WIDTH => #{@data_size})"
      code << "  port map("
      code << "    reset_n => reset_n,"
      code << "    clk     => clk,"
      code << "    -- UART --"
      code << "    rx      => rx,"
      code << "    tx      => tx,"
      code << "    -- Bus --"
      code << "    ce      => ce,"
      code << "    we      => we,"
      code << "    address => address,"
      code << "    datain  => datain,"
      code << "    dataout => dataout"
      code << "    );"
      code
    end

    def ip_instanciations mm
      code=Code.new
      mm.zones.each do |zone|
        code.newline
        code << "-- "+zone.name.to_s.center(46,"=")
        code << "inst_#{zone.name} : entity work.#{zone.name}"
        code.indent=2
        code << "port map ("
        code.indent=4
        code << "reset_n => reset_n,"
        code << "clk     => clk,"
        code << "sreset  => sreset,"
        code << "ce      => ce,"
        code << "we      => we,"
        code << "address => address,"
        code << "datain  => datain,"
        code << "dataout => dataout"
        code.indent=2
        code << ");"
        code.indent=0
      end
      code
    end

    def debug_stuff
      code=Code.new
      code.newline
      code << "-- =================== DEBUG ===================="
      code << "ticker : entity #{@work}.slow_ticker(rtl)"
      code << "  port map("
      code << "    reset_n   => reset_n,"
      code << "    fast_clk  => clk,"
      code << "    slow_clk  => slow_clk,"
      code << "    slow_tick => slow_tick"
      code << "    );"
      code << "leds <= \"000000000000000\" & slow_clk;"
      code
    end



    def gen_xdc zone
      dest_dir=$working_dir #+"/synthesis"
      if !Dir.exists?(dest_dir)
        FileUtils.mkdir(dest_dir)
      end
      puts "==> generating XDC constraints file for Artix7"
      code=Code.new
      code
      code << "## clock signal"
      code << "set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }]; #IO_L12P_T1_MRCC_35"
      code << "create_clock -add -name clk -period 10.00 -waveform {0 5} [get_ports {clk}];"
      code.newline
      pinout_str=%Q(
         J15,L16,M13,R15,R17,T18,U18,R13,T8,U8,R16,T13,H6,U12,U11,V10,H17,K15,J13,N14,R18,V17,U17,U16,\
         V16,T15,U14,T16,V15,V14,V12,V11,R12,M16,N15,G14,R11,N16,T10,R10,K16,K13,P15,T11,L18,H15,J17,J18,\
         T9,J14,P14,T14,K2,U13,C12,N17,M18,P17,M17,P18,C17,D18,E18,G17,D17,E17,F18,G18,D14,F16,G16,H14,E16,\
         F13,G13,H16,K1,F6,J2,G6,E7,J3,J4,E6,H4,H1,G1,G3,H2,G4,G2,F3,A14,A13,A16,A15,B17,B16,A18,B18,A3,B4,\
         C5,A4,C6,A5,B6,A6,B7,C7,D7,D8,B11,B12,E2,A1,B1,C1,C2,E1,F1,D2,E15,F14,F15,D15,B13,C16,C14,C15,D13,\
         B14,J5,H5,F5,A11,D12,C4,D4,D3,E5,F4,B2,C9,A9,B3,D9,C10,C11,D10,B9,A10,A8,D5,B8,K17,K18,L14,M14,L13\
      )
      pinout=pinout_str.strip.split(',').map(&:strip)
      ports=[
        {:reset_n => 1},
        {:ce => 1},
        {:we => 1},
        {:address => @addr_size},
        {:datain  => @data_size},
        {:dataout => @data_size},
      ]
      mapping={}
      ports.each do |porth|
        name,size=porth.to_a.first
        for i in 0..size-1
          name=name.to_s
          pname=(size==1)? name : name+"[#{i}]"
          mapping[pname]=pinout.shift
          code << "set_property -dict { PACKAGE_PIN #{mapping[pname]} IOSTANDARD LVCMOS33 } [get_ports { #{pname} }];"
        end
      end

      file=code.save_as("#{dest_dir}/artix7.xdc",false)
      puts "   - mapped #{mapping.size} ports to pinout .................... #{file}"
    end

    def gen_ruby_sw_if mm
      dest_dir=$working_dir+"/esw"
      if !Dir.exists?(dest_dir)
        FileUtils.mkdir(dest_dir)
      end
      words_in_name=mm.name.to_s.split("_")
      filename=words_in_name.map(&:downcase).join("_")+".rb"
      puts "=> generating Ruby sw"+(" "+filename).rjust(41,'.')
      code=Code.new
      code << "require 'pp'"
      code << "require 'rubyserial'"
      code.newline
      classname=words_in_name.map(&:capitalize).join
      code << "class #{classname}"
      code.indent=2
      code.newline
      code << "def initialize"
      code.indent=4
      code << "@serial=Serial.new '/dev/ttyUSB1',19200,8"
      code.indent=2
      code << "end"
      code.newline
      code << "def to_byte_array num,bytes"
      code.indent=2
      code << "(bytes - 1).downto(0).collect{|byte|((num >> (byte * 8)) & 0xFF)}"
      code.indent=0
      code << "end"
      code.newline
      code << "def byte_array_to_int ary"
      code << "  val=0"
      code << "  nb_bytes=ary.size"
      code << "  ary.each_with_index{|b,i|"
      code << "    pow256=256**(nb_bytes-1-i)"
      code << "    val+=b*pow256"
      code << "  }"
      code << "  val"
      code << "end"
      code.newline
      code << "def read_reg address"
      code.indent=4
      code << "#               b4   b3   b2   b1   b0"
      code << "@serial.write [                   0x10].pack(\"C*\")"
      code << "@serial.write [                address].pack(\"C*\")"
      code << "bytes=[]"
      code << "for i in 0..3"
      code.indent=6
      code << "byte=nil"
      code << "byte=@serial.getbyte until byte"
      code << "bytes << byte"
      code.indent=4
      code << "end"
      code << "bytes # array of bytes"
      code << "byte_array_to_int(bytes)"
      code.indent=2
      code << "end"
      code.newline
      code << "def write_reg addr,data"
      code.indent=4
      code << "#               b4   b3   b2   b1   b0"
      code << "@serial.write [                   0x11].pack(\"C*\")"
      code << "@serial.write [                   addr].pack(\"C*\")"
      code << "bytes=to_byte_array(data,4)"
      code << "@serial.write bytes.unpack(\"C*\")"
      code.indent=2
      code << "end"
      code.newline
      mm.zones.each do |zone|
        code << "# === #{zone.name} ==="
        zone.registers.each do |reg|
          code << "def #{zone.name}_#{reg.name}"
          code.indent=4
          code << "read_reg #{reg.address}"
          code.indent=2
          code << "end"
          code.newline
          code << "def #{zone.name}_#{reg.name}=val"
          code.indent=4
          code << "write_reg #{reg.address},val"
          code.indent=2
          code << "end"
          code.newline
        end
      end
      code.indent=0
      code << "end"
      code.newline
      code << "if $PROGRAM_NAME==__FILE__"
      code.indent=2
      code << "#{classname.downcase}=#{classname}.new"
      code << "#{classname}."
      code.indent=0
      code << "end"
      puts code.finalize
      filename="#{dest_dir}/#{filename}"
      code.save_as(filename,verbose=false)
    end

  end

end
