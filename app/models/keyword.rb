class Keyword < ActiveRecord::Base
  has_many :movie_keyword
  has_many :movies, :through => :movie_keyword
  attr_accessor :strong

  def self.strong_keywords(movie)
    strong = []
    movie.plots.each do |plot|
      next if !plot || !plot.plot_norm
      tmpplot = plot.plot_norm.downcase.gsub("-", " ").gsub(/[^ a-z0-9]/, "")
      movie.keywords.each do |keyword|
        tmpkeyword = keyword.keyword.downcase.gsub("-", " ").gsub(/[^ a-z0-9]/, "").norm
        if tmpplot.index(tmpkeyword)
          keyword.strong = true
          strong << keyword
        end
      end
    end
    strong.uniq
  end

  def self.keywords_preview(movie, limit = 10)
    keywords = movie.keywords
    strong = []
    movie.plots.each do |plot|
      next if !plot || !plot.plot_norm
      tmpplot = plot.plot_norm.downcase.gsub("-", " ").gsub(/[^ a-z0-9]/, "")
      keywords.each do |keyword|
        tmpkeyword = keyword.keyword.downcase.gsub("-", " ").gsub(/[^ a-z0-9]/, "").norm
        if tmpplot.index(tmpkeyword)
          keyword.strong = true
          strong << keyword
        end
      end
    end
    normal = (keywords - strong)
    strong = strong.uniq.sort_by { |keyword| [keyword.keyword.gsub(/-/,"")[2..2]] }
    normal = normal.sort_by { |keyword| [keyword.keyword.gsub(/-/,"")[2..2]] }
    output = strong[0...limit]
    if output.size < limit
      output += normal[0...limit-output.size]
    end
    output.sort_by { |keyword| [keyword.strong ? "0" : "1", keyword.display] }
  end

  def display
    kw = keyword
    keepdash.each do |kd|
      if kw.index(kd)
        kdrepl = kd.gsub(/-/, "\t")
        kw.gsub!(kd, kdrepl)
      end
    end
    forcenext = true
    lastword = ""
    text = kw.split("-").map do |word|
      matchword = word.downcase.gsub(/[^a-z0-9]/, "")
      tmp = word
      if allup.include?(matchword) || allup.include?(word)
        tmp = word.upcase
      elsif forcenext || !stopwords.include?(matchword)
        if ["a", "de"].include?(lastword) == false || ["la"].include?(word) == false
          tmp = word.capitalize
        end
      end
      if word[-1..-1] == ","
        forcenext = false
      else
        forcenext = false
      end
      lastword = word
      tmp.gsub(/\t/, "-")
    end.join(" ")

    text
  end

  def stopwords
    ["a","an","and","are","as","at",
     "be","but","by","for","if","in",
     "into","is","it","no","not","of",
     "on","or","s","such","t","that",
     "the","their","then","there",
     "these","they","this","to","was",
     "will","with","de"]
  end

  def keepdash
    # Order is relevant
    ["mini-series", "non-fiction", "in-laws", "-in-law", "in-law", "x-ray", "f-word"]
  end

  def allup
    ["tv", "vcr", "u.s.", "uk", "usa", "ussr", "d.c.", "nyc", "l.a.", "cia", "fbi", "nsa", "ak"]
  end

  def as_json(options = {})
    super(options)
      .merge({
               display: display,
               strong: strong
             }).compact
  end
end
