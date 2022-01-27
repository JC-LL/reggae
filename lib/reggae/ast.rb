module Reggae

  module Visitable
    def accept(visitor, arg=nil)
      name = self.class.name.split(/::/)[1]
      visitor.send("visit#{name}".to_sym, self ,arg) # Metaprograming !
    end
  end

  class MemoryMap < Struct.new(:name,:parameters,:zones,:comments)
    include Visitable
  end

  class Comment < Struct.new(:txt)
    include Visitable
  end

  class Parameters < Struct.new(:bus,:range)
    include Visitable
  end

  class Bus < Struct.new(:frequency,:address_size,:data_size)
    include Visitable
  end

  class Range < Struct.new(:from,:to)
    include Visitable
  end

  class Zone < Struct.new(:name,:range,:registers,:subzones,:instances)
    include Visitable
  end


  class Instance < Struct.new(:name,:mapping)
    include Visitable
  end

  class Connect < Struct.new(:formal,:actual)
    include Visitable
  end

  class Input < Struct.new(:name)
    include Visitable
  end

  class Output < Struct.new(:name)
    include Visitable
  end

  class RegSig < Struct.new(:name,:field)
    include Visitable
  end

  class Subzone < Zone
    include Visitable
  end

  class Register < Struct.new(:name,:address,:init,:sampling,:writable,:bits,:bitfields)
    include Visitable
    def bit(n)
      @bits.find{|bit| bit.position==n}
    end
  end

  class Bit < Struct.new(:position,:name,:purpose,:toggle)
    include Visitable
  end

  class Bitfield < Bit
    include Visitable
  end
end
