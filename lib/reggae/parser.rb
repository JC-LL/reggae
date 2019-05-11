require 'sxp'
require 'pp'

require_relative 'ast'

class Array
  def header
    self.first
  end
end

module Reggae

  class Parser

    def parse filename
      str=IO.read(filename)
      str=fix_sexpistol_bug(str)
      mm_a=SXP.read(str)
      parseMemoryMap(mm_a)
    end

    def fix_sexpistol_bug str
      s1=str.gsub(/0x(\w+)/,'\1') #0x....
      s2=s1.gsub(/(\d+)\.\.(\d+)/,'\1 \2') #range
    end

    def parseMemoryMap ary
      mm=MemoryMap.new(nil,nil,[])
      ary.shift
      mm.name=ary.shift
      while ary.any?
        case h=ary.first.header
        when :comment
          mm.comments ||=[]
          mm.comments << parseComment(ary.shift)
        when :parameters
          mm.parameters=parseParameters(ary.shift)
        when :zone
          mm.zones << parseZone(ary.shift)
        else
          raise "error.expecting 'zone' or 'parameters'. got a '#{h}'"
        end
      end
      mm
    end

    def parseComment ary
      comment=Comment.new(nil)
      ary.shift
      comment.txt=ary.shift
      comment
    end

    def parseParameters ary
      param=Parameters.new(nil,nil)
      ary.shift
      while ary.any?
        case h=ary.first.header
        when :bus
          param.bus=parseBus(ary.shift)
        when :range
          param.range=parseRange(ary.shift)
        else
          raise "error.expecting 'bus' or 'range'. Got a '#{h}'"
        end
      end
      @param=param
      param
    end

    def parseBus ary
      bus=Bus.new(nil,nil,nil)
      ary.shift
      while ary.any?
        case h=ary.first.header
        when :frequency
          bus.frequency=ary.first.last.to_i
        when :address_size
          bus.address_size=ary.first.last.to_i
        when :data_size
          bus.data_size=ary.first.last.to_i
        else
          raise "error during parseBus. Expecting 'frequency','address_size' or 'data_size'. Got '#{h}'"
        end
        ary.shift
      end
      bus
    end

    def parseHexa sym
      "0x#{sym}"
    end

    def parseRange ary
      rg=Range.new(nil,nil)
      rg.from=parseHexa(ary[1])
      rg.to=parseHexa(ary[2])
      rg
    end

    def parseZone ary
      zone=Zone.new(nil,nil,[],[],[])
      ary.shift
      zone.name=ary.shift
      while ary.any?
        case h=ary.first.header
        when :range
          zone.range=parseRange(ary.shift)
        when :register
          zone.registers << parseRegister(ary.shift)
        when :subzone
          zone.subzones << parseSubZone(ary.shift)
        when :instance
          zone.instances << parseInstance(ary.shift)
        else
          raise "error during parseZone.Expecting 'range' or 'register'. Got '#{h}'"
        end
      end
      zone
    end

    def parseInstance ary
      inst=Instance.new(nil,[])
      ary.shift
      inst.name=ary.shift
      while ary.any?
        case h=ary.first.header
        when :connect
          inst.mapping << parseConnect(ary.shift)
        else
          raise "error during parseZone.Expecting 'connect'. Got '#{h}'"
        end
      end
      inst
    end

    def parseConnect ary
      map=Connect.new(nil,nil)
      ary.shift
      map.formal=parseFormalIO(ary.shift)
      map.actual=parseRegSig(ary.shift)
      map
    end

    def parseFormalIO ary
      dir=ary.shift
      case dir
      when :input
        return Input.new(ary.shift)
      when :output
        return Output.new(ary.shift)
      else
        raise "error in formal io : #{ary}"
      end
    end

    def parseRegSig ary
      sig=RegSig.new(nil,nil)
      ary.shift #register
      sig.name=ary.shift
      sig.field=ary.shift
      sig
    end

    def parseSubZone ary
      zone=Subzone.new(nil,nil,[],[])
      ary.shift
      zone.name=ary.shift
      while ary.any?
        case h=ary.first.header
        when :range
          zone.range=parseRange(ary.shift)
        when :register
          zone.registers << parseRegister(ary.shift)
        when :subzone
          zone.subzones << parseSubZone(ary.shift)
        else
          raise "error during parseZone.Expecting 'range' or 'register'. Got '#{h}'"
        end
      end
      zone
    end

    def parseRegister ary
      reg=Register.new(nil,nil,nil,nil,true,[],[])
      ary.shift
      reg.name=ary.shift
      while ary.any?
        case h=ary.first.header
        when :address
          reg.address=parseAddress(ary.shift)
        when :init
          reg.init=parseInit(ary.shift)
        when :sampling
          reg.sampling=parseSampling(ary.shift)
        when :writable
          reg.writable=parseWritable(ary.shift)
        when :bit
          reg.bits << parseBit(ary.shift)
        when :bitfield
          reg.bitfields << parseBitfield(ary.shift)
        else
          raise "Error during parseRegister"
        end
      end
      if reg.bits.empty? and reg.bitfields.empty?
        bus_size=@param.bus.data_size
        position=[bus_size-1,0]
        reg.bitfields << Bitfield.new(position,name=:value,nil,nil)
      end
      reg
    end

    def parseAddress ary
      parseHexa(ary.last)
    end

    def parseInit ary
      parseHexa(ary.last)
    end

    def parseSampling ary
      ary.shift
      ary.shift==:true
    end

    def parseWritable ary
      ary.shift
      ary.shift==:true
    end

    def parseBit ary
      bit=Bit.new(nil,nil,nil,nil)
      ary.shift
      bit.position=ary.shift.to_i
      while ary.any?
        case h=ary.first.header
        when :name
          bit.name=parseName(ary.shift)
        when :purpose
          bit.purpose=parsePurpose(ary.shift)
        when :toggle
          bit.toggle=parseToggle(ary.shift)
        end
      end
      bit
    end

    def parseName ary
      ary[1]
    end

    def parsePurpose ary
      ary[1]
    end

    def parseToggle ary
      ary[1]==:true
    end

    def parseBitfield ary
      bf=Bitfield.new(nil,nil,nil,nil)
      ary.shift
      bf.position=[]
      bf.position << ary.shift.to_s.to_i
      bf.position << ary.shift.to_s.to_i
      while ary.any?
        case h=ary.first.header
        when :name
          bf.name=parseName(ary.shift)
        when :purpose
          bf.purpose=parsePurpose(ary.shift)
        when :toggle
          bf.toggle=parseToggle(ary.shift)
        end
      end
      bf
    end
  end #parser
end #module
