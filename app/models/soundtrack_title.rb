class SoundtrackTitle < ActiveRecord::Base
  belongs_to :movie
  has_many :soundtrack_title_data, -> { order(:sort_order) }

  def links
    pids = title.get_links("PID")
    mids = title.get_links("MID")
    people = Person.where(id: pids).group_by(&:id)
    movies = Movie.where(id: mids).group_by(&:id)
    link_list = {}
    link_list[:people] = people if !people.blank?
    link_list[:movies] = movies if !movies.blank?
    link_list.blank? ? nil : link_list
  end

  def as_json(options = {})
    {
      title: title,
      links: links,
      lines: soundtrack_title_data
    }.compact
  end
end
