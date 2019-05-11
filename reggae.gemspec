require_relative './lib/compiler'

Gem::Specification.new do |s|
  s.name        = 'reggae'
  s.version     = Reggae::Compiler::VERSION
  s.date        = Time.now.strftime('%F')
  s.summary     = "Register-map generator for VHDL"
  s.description = "Generates a bus-based VHDL IP from a register-map specification. An UART-bus master can be added if needed."
  s.authors     = ["Jean-Christophe Le Lann"]
  s.email       = 'jean-christophe.le_lann@ensta-bretagne.fr'
  s.files       = [
                   "bin/reggae",
                   "lib/ast.rb",
                   "lib/version.rb",
                   "lib/parser.rb",
                   "lib/code.rb",
                   "lib/compiler.rb",
                   "lib/visitor.rb",
                   "lib/pretty_printer.rb",
                   "lib/vhdl_generator.rb",
                   "assets/fifo.vhd",
                   "assets/flag_buf.vhd",
                   "assets/mod_m_counter.vhd",
                   "assets/Nexys4DDR_Master.xdc",
                   "assets/slow_ticker.vhd",
                   "assets/uart_bus_master.vhd",
                   "assets/uart_tx.vhd",
                   "assets/uart_rx.vhd",
                   "assets/uart.vhd",
                   "tests/ip.sexp"
                  ]
  s.executables << 'reggae'
  s.homepage    = 'http://www.ensta-bretagne.fr/lelann/reggae'
  s.license       = 'MIT'
end
