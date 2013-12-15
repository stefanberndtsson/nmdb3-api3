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
    pages += person_metadata.pluck(:key).uniq.map { |x| PersonMetadatum.page_from_key(x) }.uniq
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

  def as_json(options)
    super(options)
      .merge({
               score: @score
             }).compact
  end
end
