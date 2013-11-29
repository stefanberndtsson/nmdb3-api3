class Hash
  def compact(opts={})
    inject({}) do |new_hash, (k,v)|
      if !v.nil?
        new_hash[k] = opts[:recurse] && v.class == Hash ? v.compact(opts) : v
      end
      new_hash
    end
  end
end

class Movie < ActiveRecord::Base
  has_many :occupations
  has_many :people, :through => :occupations
  has_many :movie_genres
  has_many :genres, :through => :movie_genres
  has_many :movie_keywords
  has_many :keywords, :through => :movie_keywords

  def cast_members
    occupations.where(role_id: Role.cast_roles).includes(:person).order("sort_value::int").map do |cast_member|
      {
        id: cast_member.person_id,
        name: cast_member.person.display,
        character: cast_member.character,
        extras: cast_member.extras,
        sort_value: cast_member.sort_value,
        episode_count: is_episode ? cast_member.episode_count : nil
      }.compact
    end
  end

  def as_json(options)
    json_hash = super(options)
      .merge({
               category_code: category_code,
               category: category
             })
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
end
