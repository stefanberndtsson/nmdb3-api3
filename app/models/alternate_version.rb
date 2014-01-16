class AlternateVersion < ActiveRecord::Base
  belongs_to :movie
  belongs_to :main, :class_name => "AlternateVersion", :foreign_key => :parent_id
  has_many :versions, :foreign_key => :parent_id, :class_name => "AlternateVersion"

  def links
    pids = alternate_version.get_links("PID")
    mids = alternate_version.get_links("MID")
    people = Person.where(id: pids).group_by(&:id)
    movies = Movie.where(id: mids).group_by(&:id)
    link_list = {}
    link_list[:people] = people if !people.blank?
    link_list[:movies] = movies if !movies.blank?
    link_list.blank? ? nil : link_list
  end

  def version_hash
    version_data = {
      id: id,
      version: alternate_version,
      spoiler: spoiler,
      links: links
    }.compact
    if versions.count > 0
      version_data[:versions] = versions.map(&:version_hash)
    end
    version_data
  end

  def as_json(options = {})
    version_hash
  end
end
