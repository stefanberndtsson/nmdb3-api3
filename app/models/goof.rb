class Goof < ActiveRecord::Base
  belongs_to :movie

  CATEGORIES = {
    "DATE" => "Anachronisms",
    "FACT" => "Factual errors",
    "FAIR" => "Incorrectly regarded as goofs",
    "CHAR" => "Errors made by characters",
    "CREW" => "Crew or equipment visible",
    "CONT" => "Continuity",
    "FAKE" => "Revealing mistakes",
    "MISC" => "MISC",
    "PLOT" => "Plot Hole",
    "GEOG" => "Geographical Error",
    "BOOM" => "Boom mic visible",
    "SYNC" => "A/V unsynchronized"
  }

  def category_display
    CATEGORIES[category]
  end

  def links
    pids = goof.get_links("PID")
    mids = goof.get_links("MID")
    people = Person.where(id: pids).group_by(&:id)
    movies = Movie.where(id: mids).group_by(&:id)
    link_list = {}
    link_list[:people] = people if !people.blank?
    link_list[:movies] = movies if !movies.blank?
    link_list.blank? ? nil : link_list
  end

  def as_json(options = {})
    {
      id: id,
      category: category_display,
      category_code: category,
      goof: goof,
      spoiler: spoiler,
      links: links
    }.compact
  end
end
