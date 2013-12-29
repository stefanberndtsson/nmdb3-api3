class Person < ActiveRecord::Base
  has_many :occupations
  has_many :movies, :through => :occupations
  has_many :person_metadata
  attr_accessor :score

  def display
    [first_name, last_name].join(" ")
  end

  def as_cast
    occupations.where(role_id: Role.cast_roles)
      .includes(:movie)
      .joins(movie: :movie_years)
      .includes(movie: :main)
      .references(movie: :movie_years)
  end

  def as_noncast_base
    occupations.where("role_id NOT IN (?)", Role.cast_roles)
  end

  def as_self_base
    as_cast.where("lower(character) ~ E'(himself|herself|themselves)'")
      .where("occupations.id NOT IN (#{as_archive_base.select("occupations.id").to_sql})")
  end

  def as_archive_base
    as_cast.where("extras ~ E'\\\\(archive'")
  end

  def as_acting_base
    as_cast.where("occupations.id NOT IN (#{as_archive_base.select("occupations.id").to_sql})")
      .where("occupations.id NOT IN (#{as_self_base.select("occupations.id").to_sql})")
  end

  def cast_order(query)
    query.order("MIN(COALESCE(NULLIF(movie_years.year,'Unknown'),'0000')) DESC").group("mains_movies.id,occupations.id,movies.id,movie_years.id")
  end

  def as_acting
    cast_order(as_acting_base)
  end

  def as_archive
    cast_order(as_archive_base)
  end

  def as_self
    cast_order(as_self_base)
  end

  def as_noncast(role_name)
    occupations.where("role_id IN (#{Role.where(role: role_name).select(:id).to_sql})")
      .includes(:movie)
      .joins(movie: :movie_years)
      .includes(movie: :main)
      .references(movie: :movie_years)
  end

  def as_role(role_name)
    case role_name
    when "acting"
      return as_acting
    when "self"
      return as_self
    when "archive"
      return as_archive
    else
      cast_order(as_noncast(role_name))
    end
  end

  def active_role_names
    as_noncast_base.select("DISTINCT(roles.*)")
      .joins(:role)
      .sort_by { |x| Role::GROUP_SORT_ORDER[x.group] }
      .map { |x| x.attributes["role"] }
  end

  def cast_hashes
    {
      as_acting: as_hash(as_acting),
      as_self: as_hash(as_self),
      as_archive: as_hash(as_archive)
    }
  end

  def all_roles
    roles = ["acting", "self", "archive"]
    roles + Role.all_noncast_role_names
  end

  def active_roles
    roles = []
    roles << "acting" if as_acting_base.count > 0
    roles << "self" if as_self_base.count > 0
    roles << "archive" if as_archive_base.count > 0
    roles + active_role_names
  end

  def active_pages
    pages = [:as_role]
    pages << :top_movies if as_cast.count > 0
    pages << :images if has_images?
    pages += person_metadata.pluck(:key).uniq.map { |x| PersonMetadatum.page_from_key(x) }.uniq
  end

  def has_images?
    return false if !tmdb
    images = tmdb.images(true)
    images && !images["profiles"].blank?
  end

  def array_as_hash(query)
    query.map { |cast| as_hash(cast) }
  end

  def as_hash(entry)
    {
      id: entry.movie.id,
      movie: entry.movie,
      character: entry.character,
      extras: entry.extras,
      episode_count: entry.movie.can_have_episodes? ? entry.episode_count : nil
    }.compact
  end

  def as_episode_hash(hashed_entry)
    sort_value = hashed_entry[:movie].movie_sort_value
    {
      id: hashed_entry[:id],
      episode_name: hashed_entry[:movie].episode_name,
      episode_season: hashed_entry[:movie].episode_season,
      episode_episode: hashed_entry[:movie].episode_episode,
      episode_sort_value: sort_value,
      character: hashed_entry[:character],
      extras: hashed_entry[:extras]
    }.compact
  end

  def compress_episodes(query)
    movie_keys = query.group_by { |x| x.movie_id }.keys
    entries = array_as_hash(query)
    entry_index = {}
    entries.each_with_index do |entry,i|
      entry_index[entry[:id]] = i
    end
    remove_index_list = []
    entries.each_with_index do |cast_entry,i|
      if cast_entry[:movie].is_episode
        if movie_keys.include?(cast_entry[:movie].parent_id)
          e_index = entry_index[cast_entry[:movie].parent_id]
          entries[e_index][:episodes] ||= []
          entries[e_index][:episodes] << as_episode_hash(cast_entry)
          entries[e_index][:episodes] = entries[e_index][:episodes].sort_by { |x| x[:episode_sort_value].to_i }
          remove_index_list << i
        else
          main = cast_entry[:movie].main
          entries[i][:episodes] = [as_episode_hash(cast_entry.dup)]
          entries[i][:id] = main.id
          entries[i][:movie] = main
          movie_keys << entries[i][:id]
          entry_index[entries[i][:id]] = i
        end
      end
    end
    remove_index_list.each do |i|
      entries[i] = nil
    end
    return entries.compact
  end

  def as_json(options = {})
    json_hash = super(options)
      .merge({
               score: @score
             }).compact
    if Rails.rcache.get(cover_image_cache_key)
      json_hash[:image_url] = cover_image
    end
    json_hash
  end

  def imdb
    @imdb ||= PersonExternal::IMDb.new(self)
  end

  def tmdb
    return nil if !defined?(TMDB_API_KEY)
    @tmdb ||= PersonExternal::TMDb.new(self)
  end

  def bing
    @bing ||= PersonExternal::Bing.new(self)
  end

  def freebase
    @freebase ||= PersonExternal::Freebase.new(self)
  end

  def google
    @google ||= PersonExternal::Google.new(self)
  end

  def wikipedia(lang = "en")
    wpages = freebase.wikipedia_pages
    return nil if !wpages || !wpages[lang]
    @wikipedia ||= {}
    @wikipedia[lang] ||= PersonExternal::Wikipedia.new(self, wpages[lang], lang)
  end

  def cover_image_cache_key(size = 640)
    "person:#{self.id}:externals:wikipedia:cover"
  end

  def cover_image(size = 640)
    image_url = Rails.rcache.get("person:#{self.id}:externals:wikipedia:cover")
    if image_url && image_url != ""
      return image_url
    end
    if !wikipedia
      Rails.rcache.set("person:#{self.id}:externals:wikipedia:cover", nil, 1.day)
      return nil
    end
    image_url = wikipedia.image_url(size)
    if !image_url
      Rails.rcache.set("person:#{self.id}:externals:wikipedia:cover", nil, 1.day)
      return nil
    end
    Rails.rcache.set("person:#{self.id}:externals:wikipedia:cover", image_url, 1.day)
    image_url
  end

  def imdb_search_name
    search_name = [first_name, last_name].join(" ")
    if name_count
      search_name += " (#{name_count})"
    end
    search_name
  end

  def top_movies
    movies = Search.solr_query_movies("cast_ids:#{self.id}", limit: 50)
    movie_ids = movies.map(&:id)
    occs = Occupation.where(movie_id: movie_ids).where(person_id: self.id).group_by(&:movie_id)
    movies.map do |movie|
      movie.reduce_fetching = true
      next if !occs[movie.id]
      {
        id: movie.id,
        movie: movie,
        character: occs[movie.id].first.character,
        extras: occs[movie.id].first.extras,
        score: movie.score
      }.compact
    end.compact
  end
end
