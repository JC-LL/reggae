require 'pp'
require 'optparse'
require_relative 'parser'
require_relative 'pretty_printer'
require_relative 'vhdl_generator'
require_relative 'version'

module Reggae

  class Compiler

    attr_accessor :ast
    attr_accessor :options

    def initialize options={}
      @options=options
      puts "Reggae generator #{VERSION}" unless @options[:mute]
    end

    def analyze_options args
      args << "-h" if args.empty?

      opt_parser = OptionParser.new do |opts|
        opts.banner = "Usage: reggae <filename.sexp>"

        opts.on("-v", "--version", "Prints version") do
          puts VERSION
          abort
        end

        opts.on("-h", "--help", "Prints this help") do
          puts
          puts "Generates an IP-based system, from its memory-map expressed in s-expressions."
          puts
          puts "Author mail: jean-christophe.le_lann@ensta-bretagne.fr"
          puts
          @options[:show_help]=true
          puts opts
          abort
        end

        opts.on("-s", "--system", "Generates a top-level system") do
          @options[:gen_system]=true
        end

        opts.on("-d","Shows VHDL generated in the terminal,during generation") do
          @options[:show_code]=true
        end

        opts.on("-u", "--include_uart", "Generates an UART Master in the system top-level") do
          @options[:include_uart]=true
        end

        opts.on("--gen_ruby", "Generates Ruby code to interact with the system from a PC host") do
          @options[:gen_ruby]=true
        end

        opts.on("-x", "--gen_xdc", "Generates a Xilinx XDC constraint file for Artix7 FPGA (IP only)") do
          @options[:gen_xdc]=true
        end

        opts.on("--from_vivado_hls", "Indicates that the sexp file is generated from VHDL_WRAP tuned for VivadoHLS") do
          @options[:from_vivado_hls]=true
        end

        opts.on("-m", "silently proceed") do
          @options[:mute]=true
        end
      end

      begin
        opt_parser.parse!(args)
      rescue Exception => e
        puts e
        #puts e.backtrace
        exit
      end
      @filename = ARGV.pop
      $dirname = File.dirname(@filename) if @filename
      unless @filename or @options[:show_help]
        puts "Need to specify a filename to process"
        #exit
      end
    end

    def compile
      if @options.any?
        unless @options[:mute]
          puts
          puts "running with the following options :"
          pp @options
          puts
        end
      end
      @ast=parse(@filename)
      #pretty_print
      vhdl_files=generate_vhdl()
      return vhdl_files
    end

    def parse filename
      puts "=> parsing #{filename}" unless @options[:mute]
      $working_dir=Dir.pwd
      @ast=Reggae::Parser.new.parse(filename)
    end

    def pretty_print
      puts "=> pretty print..." unless @options[:mute]
      Reggae::Visitor.new.visit(ast)
    end

    def generate_vhdl
      puts "=> generating VHDL..." unless @options[:mute]
      Reggae::VHDLGenerator.new(@options).generate_from(ast)
    end
  end

end
