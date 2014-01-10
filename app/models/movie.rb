class Movie < ActiveRecord::Base
  has_many :occupations
  has_many :people, :through => :occupations
  has_many :movie_genres
  has_many :genres, :through => :movie_genres
  has_many :movie_keywords
  has_many :keywords, :through => :movie_keywords
  has_many :movie_years
  has_many :episodes, -> {
    includes([:plots, :release_dates])
    .select(["*", "ARRAY[COALESCE(episode_season,0),COALESCE(episode_episode,0),COALESCE(movie_sort_value,0)] AS episode_sort_value"])
    .order("episode_sort_value")
  }, :foreign_key => :parent_id, :class_name => "Movie"
  has_many :plots
  has_many :trivia
  has_many :goofs
  has_many :quotes
  has_many :release_dates
  has_many :movie_connections, -> { includes([:movie_connection_type, :linked_movie]) }
  has_many :movie_akas
  has_one :rating
  belongs_to :main, :foreign_key => :parent_id, :class_name => "Movie"
  attr_accessor :score
  attr_accessor :fetch_full

  def first_release_date
    release_dates.sort_by(&:release_stamp).first
  end

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
    Keyword.strong_keywords(self)
  end

  def as_json(options = {})
    json_hash = super(options)
      .merge({
               category_code: category_code,
               category: category,
               score: @score,
             })
    if fetch_full && Rails.rcache.get(cover_image_cache_key)
      json_hash[:image_url] = cover_image
    end
    if fetch_full && is_episode
      json_hash[:prev_episode] = prev_episode.short_data if prev_episode
      json_hash[:next_episode] = next_episode.short_data if next_episode
    end
    if fetch_full
      next_f = next_followed
      prev_f = prev_followed
      json_hash[:next_followed] = next_followed.short_data if next_f
      json_hash[:prev_followed] = prev_followed.short_data if prev_f
      json_hash[:is_linked] = true if next_f || prev_f
    end
    if fetch_full && rating
      json_hash[:rating] = {
        rating: rating.rating,
        votes: rating.votes,
        distribution: rating.distribution
      }
    end
    if fetch_full && release_dates
      json_hash[:first_release_date] = first_release_date
    end
    json_hash.delete("title_category")
    json_hash.delete("episode_sort_value")
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
    pages << :images if has_images?
    pages << :episodes if episodes.count > 0
    pages << :connections if movie_connections.count > 0
    pages << :additionals if has_additionals?
    pages
  end

  def has_additionals?
    return true if movie_akas.count > 0
    false
  end

  def has_images?
    return false if !tmdb
    images = tmdb.images(true)
    images && !(images["backdrops"].blank? && images["posters"].blank?)
  end

  def imdb
    @imdb ||= MovieExternal::IMDb.new(self)
  end

  def tmdb
    return nil if !defined?(TMDB_API_KEY)
    @tmdb ||= MovieExternal::TMDb.new(self)
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
    Rails.rcache.set(cover_image_cache_key(size), image_url, 1.month)
    image_url
  end

  def imdb_search_text
    if title_category == "TVS"
      if episode_name
        return "#{title} \"#{episode_name}\""
      else
        return full_title.gsub(/^"(.*)" \(/, '\1 (')
      end
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

  # Episode
  def episode_index
    main.episodes.index(self)
  end

  def next_episode
    return nil if !is_episode
    main.episodes[episode_index + 1]
  end

  def prev_episode
    return nil if !is_episode
    return nil if episode_index == 0
    main.episodes[episode_index - 1]
  end

  def short_data
    {
      id: id,
      full_title: full_title,
      title: title,
      parent_id: parent_id,
      title_year: title_year,
      episode_season: episode_season,
      episode_episode: episode_episode,
      episode_name: episode_name,
      movie_sort_value: movie_sort_value,
      first_release_date: first_release_date
    }
  end

  # Connections
  def next_followed
    followed_by = MovieConnectionType.find_by_connection_type("followed by")
    mc = movie_connections.where(movie_connection_type_id: followed_by.id)
    return nil if mc.empty?
    selected = mc.select do |x|
      !x.linked_movie.suspended
    end
    return nil if selected.empty?
    selected.sort_by do |x|
      [x.linked_movie.title_year == "????" ? 99999 : x.linked_movie.title_year.to_i, (x.linked_movie.movie_sort_value || 0)]
    end.first.linked_movie
  end

  def prev_followed
    follows = MovieConnectionType.find_by_connection_type("follows")
    mc = movie_connections.where(movie_connection_type_id: follows.id)
    return nil if mc.empty?
    selected = mc.select do |x|
      !x.linked_movie.suspended
    end
    return nil if selected.empty?
    selected.sort_by do |x|
      [-(x.linked_movie.title_year == "????" ? 99999 : x.linked_movie.title_year.to_i), -(x.linked_movie.movie_sort_value || 0)]
    end.first.linked_movie
  end
end
