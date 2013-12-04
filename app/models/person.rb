class Person < ActiveRecord::Base
  has_many :occupations
  has_many :movies, :through => :occupations
  attr_accessor :score

  def display
    [first_name, last_name].join(" ")
  end

  def as_cast
    occupations.where(role_id: Role.cast_roles).includes(:movie).joins(movie: :movie_years)
      .references(movie: :movie_years)
  end

  def as_noncast_base
    occupations.where("role_id NOT IN (?)", Role.cast_roles)
  end

  def as_self_base
    as_cast.where("character_norm ~ E'(himself|herself|themselves)'")
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
    query.order("MIN(COALESCE(NULLIF(movie_years.year,'Unknown'),'0000')) DESC").group("occupations.id,movies.id,movie_years.id")
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
    occupations.where("role_id IN (#{Role.where(role: role_name).select(:id).to_sql})").includes(:movie).joins(movie: :movie_years)
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

  def as_hash(query)
    query.map do |cast|
      {
        id: cast.movie.id,
        movie: cast.movie.display,
        character: cast.character,
        extras: cast.extras,
        episode_count: cast.movie.can_have_episodes? ? cast.episode_count : nil
      }.compact
    end
  end

  def as_json(options)
    super(options)
      .merge({
               score: @score
             }).compact
  end
end
