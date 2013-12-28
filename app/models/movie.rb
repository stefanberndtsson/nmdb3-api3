class Movie < ActiveRecord::Base
  has_many :occupations
  has_many :people, :through => :occupations
  has_many :movie_genres
  has_many :genres, :through => :movie_genres
  has_many :movie_keywords
  has_many :keywords, :through => :movie_keywords
  has_many :movie_years
  has_many :episodes, :foreign_key => :parent_id, :class_name => "Movie"
  has_many :plots
  has_many :trivia
  has_many :goofs
  has_many :quotes
  belongs_to :main, :foreign_key => :parent_id, :class_name => "Movie"
  attr_accessor :score

  def display
    full_title
  end

  def can_have_episodes?
    title_category == "TVS" && !is_episode
  end

  def cast
    occupations.where(role_id: Role.cast_roles).includes(:person).order("sort_value::int")
  end

  def cast_members
    cast.map do |cast_member|
      {
        id: cast_member.person_id,
        name: cast_member.person.display,
        character: cast_member.character,
        extras: cast_member.extras,
        sort_value: cast_member.sort_value,
        episode_count: can_have_episodes? ? cast_member.episode_count : nil
      }.compact
    end
  end

  def strong_keywords
    strong = []
    plots.each do |plot|
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
    strong.uniq
  end

  def as_json(options = {})
    json_hash = super(options)
      .merge({
               category_code: category_code,
               category: category,
               score: @score,
             })
    if Rails.rcache.get(cover_image_cache_key)
      json_hash[:image_url] = cover_image
    end
    json_hash.delete("title_category")
    json_hash.compact
  end

  def category_code
    title_category || "M"
  end

  def category
    @@categories ||= {
      "M" => "Movie",
      "V" => "Video",
      "TVS" => "TV-Series",
      "VG" => "Videogame",
      "TV" => "TV"
    }
    @@categories[category_code]
  end

  def active_pages
    pages = [:cast]
    pages << :keywords if movie_keywords.count > 0
    pages << :plots if plots.count > 0
    pages << :trivia if trivia.count > 0
    pages << :goofs if goofs.count > 0
    pages << :quotes if quotes.count > 0
    pages
  end

  def imdb
    @imdb ||= MovieExternal::IMDb.new(self)
  end

  def bing
    @bing ||= MovieExternal::Bing.new(self)
  end

  def freebase
    @freebase ||= MovieExternal::Freebase.new(self)
  end

  def google
    @google ||= MovieExternal::Google.new(self)
  end

  def wikipedia(lang = "en")
    wpages = freebase.wikipedia_pages
    return nil if !wpages || !wpages[lang]
    @wikipedia ||= {}
    @wikipedia[lang] ||= MovieExternal::Wikipedia.new(self, wpages[lang], lang)
  end

  def cover_image_cache_key(size = 640)
    movie_id = is_episode ? self.main.id : self.id
    "movie:#{movie_id}:externals:wikipedia:cover"
  end

  def cover_image(size = 640)
    image_url = Rails.rcache.get(cover_image_cache_key(size))
    if image_url && image_url != ""
      return image_url
    end
    if !wikipedia
      Rails.rcache.set(cover_image_cache_key(size), nil, 1.day)
      return nil
    end
    image_url = wikipedia.image_url(size)
    if !image_url
      Rails.rcache.set(cover_image_cache_key(size), nil, 1.day)
      return nil
    end
    Rails.rcache.set(cover_image_cache_key(size), image_url, 1.day)
    image_url
  end

  def imdb_search_title
    if title_category == "TVS"
      return full_title.gsub(/^"(.*)" \(/, '\1 (')
    end
    if title_category == "VG"
      return full_title
    end
    if title_category
      cpos = full_title.rindex("(#{title_category})")
      if cpos
        return full_title[0..cpos-2]
      end
    end
    return full_title
  end
end
