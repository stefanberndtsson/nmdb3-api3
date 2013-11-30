class Person < ActiveRecord::Base
  has_many :occupations
  has_many :movies, :through => :occupations

  def display
    [first_name, last_name].join(" ")
  end

  def as_cast
    occupations.where(role_id: Role.cast_roles).includes(:movie).joins(movie: :movie_years)
      .references(movie: :movie_years)
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

  def cast_hashes
    {
      as_acting: as_hash(as_acting),
      as_self: as_hash(as_self),
      as_archive: as_hash(as_archive)
    }
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
end
