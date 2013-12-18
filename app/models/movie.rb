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
  belongs_to :main, :foreign_key => :parent_id, :class_name => "Movie"
  attr_accessor :score

  def display
    full_title
  end

  def can_have_episodes?
    title_category == "TVS" && !is_episode
  end

  def cast_members
    occupations.where(role_id: Role.cast_roles).includes(:person).order("sort_value::int").map do |cast_member|
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
               score: @score
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

  def active_pages
    pages = [:cast]
    pages << :keywords if movie_keywords.count > 0
    pages << :plots if plots.count > 0
    pages << :trivia if trivia.count > 0
    pages << :goofs if goofs.count > 0
    pages
  end
end
