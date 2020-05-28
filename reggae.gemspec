require_relative './lib/reggae/version'

Gem::Specification.new do |s|
  s.name        = 'reggae_eda'
  s.version     = Reggae::VERSION
  s.date        = Time.now.strftime('%F')
  s.summary     = "Register-map generator for VHDL"
  s.description = "Generates a bus-based VHDL IP from a register-map specification. An UART-bus master can be added if needed."
  s.authors     = ["Jean-Christophe Le Lann"]
  s.email       = 'jean-christophe.le_lann@ensta-bretagne.fr'
  s.files       = [
                   "bin/reggae",
                   "lib/reggae.rb",
                   "lib/reggae/ast.rb",
                   "lib/reggae/version.rb",
                   "lib/reggae/parser.rb",
                   "lib/reggae/code.rb",
                   "lib/reggae/compiler.rb",
                   "lib/reggae/visitor.rb",
                   "lib/reggae/pretty_printer.rb",
                   "lib/reggae/vhdl_generator.rb",
                   "assets/fifo.vhd",
                   "assets/flag_buf.vhd",
                   "assets/mod_m_counter.vhd",
                   "assets/Nexys4DDR_Master.xdc",
                   "assets/slow_ticker.vhd",
                   "assets/uart_bus_master.vhd",
                   "assets/uart_tx.vhd",
                   "assets/uart_rx.vhd",
                   "assets/uart.vhd",
                   "tests/regmap.sexp"
                  ]
  s.executables << 'reggae'
  s.homepage    = 'http://www.ensta-bretagne.fr/lelann/reggae'
  s.license       = 'MIT'
end
