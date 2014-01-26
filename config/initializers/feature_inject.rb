class String
  require 'time'

  def get_links(link_type)
    links = []
    self.gsub(/@@#{link_type}@(\d+)@@/) do |match|
      links << $1.to_i
    end
    links
  end

  def get_timestamp
    timestamp = nil
    begin
      timestamp = Time.parse(self)
    rescue ArgumentError
    end
    return timestamp
  end

  def norm
    decomposed = Unicode.nfkd(self).gsub(/[^\u0000-\u00ff]/, "")
    Unicode.downcase(decomposed)
  end

  def norm_case
    Unicode.nfkd(self).gsub(/[^\u0000-\u00ff]/, "")
  end

  def ltrim
    self.gsub(/^\s+/,'')
  end

  def rtrim
    self.gsub(/\s+$/,'')
  end

  def trim
    self.ltrim.rtrim
  end
end

class Hash
  def compact(opts={})
    inject({}) do |new_hash, (k,v)|
      if !v.blank?
        new_hash[k] = opts[:recurse] && v.class == Hash ? v.compact(opts) : v
      end
      new_hash
    end
  end
end

class NilClass
  def compact(opts={})
    nil
  end
end
