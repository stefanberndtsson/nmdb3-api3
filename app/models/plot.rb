class Plot < ActiveRecord::Base
  belongs_to :movie

  def links
    pids = plot.get_links("PID")
    mids = plot.get_links("MID")
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
      plot: plot,
      author: author,
      links: links
    }.compact
  end
end
