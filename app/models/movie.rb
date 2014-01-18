class Movie < ActiveRecord::Base
  has_many :occupations
  has_many :people, :through => :occupations
  has_many :movie_genres
  has_many :genres, :through => :movie_genres
  has_many :movie_keywords
  has_many :keywords, :through => :movie_keywords
  has_many :movie_languages
  has_many :languages, :through => :movie_languages
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
  has_many :alternate_versions, -> { where(parent_id: nil) }
  has_many :soundtrack_titles, -> { order(:sort_order) }
  has_many :taglines, -> { order(:sort_order) }
  has_many :technicals
  has_many :color_infos
  has_many :certificates
  has_one :rating
  belongs_to :main, :foreign_key => :parent_id, :class_name => "Movie"
  attr_accessor :score
  attr_accessor :fetch_full
  attr_accessor :fetch_extra
  attr_accessor :display_title_fresh

  def extra?(key)
    fetch_full || (fetch_extra && fetch_extra[key])
  end

  def first_release_date
    @first_release_date ||= release_dates.sort_by(&:release_stamp).first
  end

  def is_swedish?
    if(languages.include?(Language.lang_id("Swedish")) &&
        first_release_date && ["Sweden", "Denmark", "Norway"].include?(first_release_date.country))
      return true
    end
    return false
  end

  def display_full_title
    # If episode, just reply with original name
    return full_title if is_episode
    # First check our cache for entry
    cached_title = Rails.rcache.get("movie:#{self.id}:extra:display_full_title")
    if cached_title
      @display_title_fresh = true
      return cached_title
    end
    # Special handling of original title for scandinavian titles
    if extra?(:display_title) && is_swedish?
      @display_title_fresh = true
      Rails.rcache.set("movie:#{self.id}:extra:display_full_title", full_title, 1.week)
      return full_title
    end
    # Check if we have a stored name from freebase, use if so...
    if extra?(:display_title) && freebase.topic_name(true)
      @display_title_fresh = true
      new_title = (is_tvseries? ? "\"#{freebase.topic_name}\"" : freebase.topic_name) + " (#{title_year})"
      if title_category && title_category != "TVS"
        new_title += " (#{title_category})"
      end
      Rails.rcache.set("movie:#{self.id}:extra:display_full_title", new_title, 1.week)
      return new_title
    end
    # Return plain title if we have none of the above
    full_title
  end

  def display_title
    # If episode, just reply with original name
    return title if is_episode
    # First check our cache for entry
    cached_title = Rails.rcache.get("movie:#{self.id}:extra:display_title")
    if cached_title
      @display_title_fresh = true
      return cached_title
    end
    # Special handling of original title for scandinavian titles if we're fetching display_title
    if extra?(:display_title) && is_swedish?
      Rails.rcache.set("movie:#{self.id}:extra:display_title", title, 1.week)
      @display_title_fresh = true
      return title
    end
    # Check if we have a stored name from freebase, use if so...
    if extra?(:display_title) && freebase.topic_name(true)
      new_title = (is_tvseries? ? "\"#{freebase.topic_name}\"" : freebase.topic_name)
      @display_title_fresh = true
      Rails.rcache.set("movie:#{self.id}:extra:display_title", new_title, 1.week)
      return new_title
    end
    # Return plain title if we have none of the above
    title
  end

  def is_tvseries?
    title_category == "TVS"
  end

  def can_have_episodes?
    is_tvseries? && !is_episode
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

  def crew_by_role(role)
    role = Role.where(role: role).first
    return [] if !role
    crew = occupations.where(role_id: role.id).includes(:person)
    crew.map do |member|
      crew_data(member)
    end.compact
  end

  def crew_data(member)
    {
      id: member.person.id,
      name: member.person.display,
      extras: member.extras,
      sort_value: member.sort_value
    }.compact
  end

  def strong_keywords
    Keyword.strong_keywords(self)
  end

  def keywords_preview(limit = 10)
    Keyword.keywords_preview(self, limit)
  end

  def as_json(options = {})
    json_hash = super(options)
      .merge({
               display_title: display_title,
               display_full_title: display_full_title,
               display_title_fresh: @display_title_fresh,
               category_code: category_code,
               category: category,
               score: @score,
             })
    cached_cover = Rails.rcache.get(cover_image_cache_key)
    if extra?(:cover) && cached_cover && cached_cover != ""
      json_hash[:image_url] = cached_cover
      if Rails.rcache.get("#{cover_image_cache_key}:expire").to_i < Time.now.to_i
        json_hash[:image_url_expired] = true
      end
    end
    if extra?(:episode_links) && is_episode
      json_hash[:prev_episode] = prev_episode.short_data if prev_episode
      json_hash[:next_episode] = next_episode.short_data if next_episode
    end
    if extra?(:movie_links)
      next_f = next_followed
      prev_f = prev_followed
      json_hash[:next_followed] = next_followed.short_data if next_f
      json_hash[:prev_followed] = prev_followed.short_data if prev_f
      json_hash[:is_linked] = true if next_f || prev_f
    end
    if extra?(:rating) && rating
      json_hash[:rating] = {
        rating: rating.rating,
        votes: rating.votes,
        distribution: rating.distribution
      }
    end
    if extra?(:first_release_date) && release_dates.count > 0
      json_hash[:first_release_date] = first_release_date
    end
    if extra?(:tagline) && taglines.count > 0
      json_hash[:tagline] = taglines.first.tagline
    end
    if extra?(:keywords) && keywords.count > 0
      json_hash[:keywords] = keywords_preview
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
    pages << :additionals
    pages << :versions if alternate_versions.count > 0
    pages << :soundtrack if soundtrack_titles.count > 0
    pages << :taglines if taglines.count > 0
    pages << :technicals if technicals.count > 0
    pages << :similar if has_similar?
    pages
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

  def cover_image_cache_key
    movie_id = is_episode ? self.main.id : self.id
    "movie:#{movie_id}:externals:wikipedia:cover"
  end

  def cover_image_set_cache(image_url, expire = 1.month)
    expire = 1.day if !image_url
    Rails.rcache.set(cover_image_cache_key, image_url)
    Rails.rcache.set("#{cover_image_cache_key}:expire", (Time.now + expire).to_i)
  end

  def cover_image
    if Rails.rcache.get("#{cover_image_cache_key}:expire").to_i >= Time.now.to_i
      image_url = Rails.rcache.get(cover_image_cache_key)
      if image_url && image_url != ""
        return image_url
      end
    end
    if !wikipedia
      cover_image_set_cache(nil)
      return nil
    end
    image_url = wikipedia.image_url
    if !image_url
      cover_image_set_cache(nil)
      return nil
    end
    cover_image_set_cache(image_url)
    image_url
  end

  def imdb_search_text
    if title_category == "TVS"
      if episode_name
        return "\"#{title} \"#{episode_name}\"\""
      else
        return "\"#{full_title.gsub(/^"(.*)" \(/, '\1 (')}\""
      end
    end
    if title_category == "VG"
      return "+intitle:\"#{full_title}\""
    end
    if title_category
      cpos = full_title.rindex("(#{title_category})")
      if cpos
        return "+intitle:\"#{full_title[0..cpos-2]}\""
      end
    end
    return "+intitle:\"#{full_title}\""
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
      display_title: display_title,
      display_full_title: display_full_title,
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

  # Similar
  def has_similar?
    Movie.select("movie_id").from("compare_overlaps").where("movie_id = ?", self.id).count != 0
  end

  def find_similar(result_count = 30)
    lc = "co.language_overlap_count::float"
    gc = "co.genre_overlap_count::float"
    knn = "co.normal_normal_count::float"
    kns = "co.normal_strong_count::float"
    ksn = "co.strong_normal_count::float"
    kss = "co.strong_strong_count::float"
    cmy = "convert_to_integer(m.title_year)::float"
    selfgc = genre_ids.count.to_f
    selfkc = keyword_ids.count.to_f
    selflc = language_ids.count.to_f
    selfskc = strong_keywords.count.to_f
    selfyear = title_year.to_i

    nnw = 1.0
    nsw = 2.0
    snw = 3.0
    ssw = 4.0
    gcw = 0.3
    lcw = 0.1
    yrw = 0.01

    score_kwnn = selfkc == 0 ? "" : "(#{nnw}*#{knn}/#{selfkc})"
    score_kwns = selfkc == 0 ? "" : "(#{nsw}*#{kns}/#{selfkc})"
    score_kwsn = selfskc == 0 ? "" : "(#{snw}*#{ksn}/#{selfskc})"
    score_kwss = selfskc == 0 ? "" : "(#{ssw}*#{kss}/#{selfskc})"
    score_genre = selfgc == 0 ? "" : "(#{gcw}*#{gc}/#{selfgc})"
    score_lang = selflc == 0 ? "" : "(#{lcw}*#{lc}/#{selflc})"
    score_divisor = nnw+nsw+snw+ssw+gcw+lcw
    score_year = "(1+(ABS(#{cmy}-#{selfyear})*#{yrw}))"

    score_expr_top = ([score_kwnn, score_kwns, score_kwsn,
                       score_kwss, score_genre, score_lang]-[""]).join("+")
    score_expr_middle = score_divisor
    score_expr_bottom = score_year

#    score_expr_top = "((1+#{lc}/10) * (1+#{gc}/5) * (#{knn}+2*#{kns}+2*#{ksn}+3*#{kss}))"
#    score_expr_middle = ((1+selflc/10.0)*(1+selfgc/5.0)*(selfkc))
#    score_expr_bottom = "(1+(ABS(#{cmy}-#{selfyear})/50.0))"
    score_expr = "(#{score_expr_top})/(#{score_expr_middle})/(#{score_expr_bottom})"
#    STDERR.puts(score_expr)
    query = "SELECT co.compare_movie_id AS id, #{score_expr} AS score_value"+
                                " FROM compare_overlaps co"+
                                " INNER JOIN movies m"+
                                "  ON co.compare_movie_id = m.id"+
                                " WHERE movie_id = #{self.id}"+
                                " ORDER BY 2 DESC"+
                                " LIMIT #{result_count}"
    movies = Movie.find_by_sql(query)

    movie_list = { }
    Movie.find_all_by_id(movies.map(&:id), :include => :rating).each do |movie|
      movie_list[movie.id.to_i] = movie
    end

    return (movies.map do |item|
              movie = movie_list[item.id.to_i]
              next if movie.nil?
              movie.fetch_extra = { rating: true }
              score = item.score_value.to_f
              score *= 100.0
              score = 100.0 if score > 100.0
              score = 15 if score <= 0.01
              {
                movie: movie,
                similarity: sprintf("%3.1f%", score)
              }
    end - [nil])
  end

  def clear_all_caches
    Rails.rcache.keys("movie:#{self.id}:*").each do |key|
      Rails.rcache.del(key)
    end
  end
end
