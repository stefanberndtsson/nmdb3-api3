class Postfix
  def initialize(postfix_array)
    @pf = postfix_array
  end

  def to_solr
    stack = []
    @pf.each do |entry|
      if entry.is_a?(Operator)
        right = stack.pop
        left = stack.pop
        stack.push(entry.apply(left, right))
      else
        stack.push(entry)
      end
    end
    stack.pop
  end
end

class Operator
  SIGNS={
    "+" => "add",
    "-" => "sub",
    "/" => "div",
    "*" => "product"
  }

  def initialize(sign)
    @sign = sign
  end

  def apply(left, right)
    "#{SIGNS[@sign]}(#{left},#{right})"
  end

  def [](value)
    @sign[value]
  end
end

class Infix
  def initialize(str)
    @str = str
  end

  def to_postfix
    pflist = []
    pfstack = []
    last_chr = false

    @str.split("").each do |chr|
      if chr[/[a-z0-9_.]/]
        if !last_chr
          pflist << ""
        end
        pflist.last << chr
        last_chr = true
      elsif chr[/[+-]/]
        while pfstack.last && pfstack.last[/[*\/+-]/]
          pflist << pfstack.pop
        end
        pfstack.push(Operator.new(chr))
        last_chr = false
      elsif chr[/[*\/]/]
        pfstack.push(Operator.new(chr))
        last_chr = false
      elsif chr[/[(]/]
        pfstack.push(Operator.new(chr))
        last_chr = false
      elsif chr[/[)]/]
        while pfstack.last && !pfstack.last[/[(]/]
          pflist << pfstack.pop
        end
        if pfstack.last && pfstack.last[/[(]/]
          pfstack.pop
        end
        last_chr = false
      end
    end
    while pfstack.last
      pflist << pfstack.pop
    end
    Postfix.new(pflist)
  end
end
