class Code

  attr_accessor :indent,:code

  def initialize indent=0
    @code=[]
    @indent=indent
  end

  def empty?
    @code.size==0
  end

  def <<(str)
    if str.is_a? Code
      str.code.each do |line|
        @code << " "*@indent+line
      end
    elsif str.nil?
    else
      @code << " "*@indent+str
    end
  end

  def finalize dot=false
    if dot
      return @code.join('\n')
    end
    @code.join("\n")
  end

  def newline
    @code << " "
  end

  def save_as filename,verbose=true
    str=self.finalize
    if filename.end_with? ".vhd"
      str=clean_vhdl(str)
    end
    File.open(filename,'w'){|f| f.puts(str)}
    puts "saved code in file #{filename}" if verbose
    return filename
  end

  def size
    @code.size
  end

  def clean_vhdl str
    str1=str.gsub(/\;\s*\)/,")")
    str2=str1.gsub(/\,\s*\)/,")")
  end

end
