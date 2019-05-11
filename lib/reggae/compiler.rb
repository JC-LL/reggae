require 'pp'
require 'optparse'
require_relative 'parser'
require_relative 'pretty_printer'
require_relative 'vhdl_generator'
require_relative 'version'

module Reggae

  class Compiler

    attr_accessor :ast

    def initialize
      puts "Reggae generator #{VERSION}"
      @options={}
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
          puts "Author : Jean-Christophe Le Lann - mail: lelannje@ensta-bretagne.fr"
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
        puts
        puts "running with the following options :"
        pp @options
        puts
      end
      @ast=parse(@filename)
      #pretty_print
      generate_vhdl
    end

    def parse filename
      puts "=> parsing #{filename}"
      $working_dir=Dir.pwd
      @ast=Reggae::Parser.new.parse(filename)
    end

    def pretty_print
      puts "=> pretty print..."
      Reggae::Visitor.new.visit(ast)
    end

    def generate_vhdl
      puts "=> generating VHDL..."
      Reggae::VHDLGenerator.new(@options).generate_from(ast)
    end
  end

end
