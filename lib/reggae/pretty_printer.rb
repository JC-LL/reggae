require_relative 'code'
require_relative 'visitor'
module Reggae

  class PrettyPrinter < Visitor

    def initialize
      @indent=-2
    end

    def inc str=nil
      say(str) if str
      @indent+=2
    end

    def dec
      @indent-=2
    end

    def say str
      puts " "*@indent+str.to_s
    end

    def visit mm
      inc
      mm.accept(self,nil)
      dec
    end

    def visitMemoryMap mm,args=nil
      inc "MemoryMap"
      say mm.name
      mm.parameters.accept(self,nil)
      mm.zones.each{|zone| zone.accept(self,nil)}
      dec
    end

    def visitParameters params,args=nil
      inc "Parameters"
      params.bus.accept(self,nil)
      params.range.accept(self,nil)
      dec
    end

    def visitBus bus,args=nil
      inc "Bus"
      say bus.frequency
      say bus.address_size
      say bus.data_size
      dec
    end

    def visitRange range,args=nil
      inc "Range"
      say range.from
      say range.to
      dec
    end

    def visitZone zone,args=nil
      inc "Zone"
      say zone.name
      zone.range.accept(self)
      zone.registers.each{|reg| reg.accept(self)}
      zone.subzones.each{|subzone| subzone.accept(self)}
      dec
    end

    def visitSubzone zone,args=nil
      inc "Subzone"
      say zone.name
      zone.range.accept(self)
      zone.registers.each{|reg| reg.accept(self)}
      dec
    end

    def visitRegister reg,args=nil
      inc "Register"
      say reg.name
      say reg.address
      say reg.init
      reg.bits.each{|bit| bit.accept(self)}
      reg.bitfields.each{|bitfield| bitfield.accept(self)}
      dec
    end

    def visitBlockRam bram,args=nil
      inc "BlockRam"
      say bram.size
      say bram.width
      bram.range.accept(self)
      dec
    end

    def visitBit bit,args=nil
      inc "Bit"
      say bit.position
      say bit.name
      say bit.purpose
      say bit.toggle
      dec
    end

    def visitBitfield bitfield,args=nil
      inc "Bitfield"
      say bitfield.position
      say bitfield.name
      say bitfield.purpose
      say bitfield.toggle
      dec
    end

  end
end
