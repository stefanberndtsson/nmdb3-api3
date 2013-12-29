class MovieConnectionText < ActiveRecord::Base
  def self.store(m_id, l_id, ct_id, text)
    @@mc_store ||= { }
    @@mc_store[[m_id,l_id,ct_id]] ||=
      MovieConnectionText.find_or_create_by(movie_id: m_id,
                                         linked_movie_id: l_id,
                                         movie_connection_type_id: ct_id) do |mct|
      mct.value = text.blank? ? "[NONE]" : text
    end
    fetch(m_id, true)
    @@mc_store[[m_id,l_id,ct_id]]
  end

  def self.fetch(m_id, refetch = false)
    @@mc_text ||= { }
    if refetch
      @@mc_text[m_id] = MovieConnectionText.where(movie_id: m_id).group_by { |x| [x.linked_movie_id, x.movie_connection_type_id] }
    else
      @@mc_text[m_id] ||= MovieConnectionText.where(movie_id: m_id).group_by { |x| [x.linked_movie_id, x.movie_connection_type_id] }
    end
    @@mc_text.delete(m_id) if @@mc_text[m_id].blank?
    @@mc_text[m_id]
  end

  def self.find(m_id, l_id, ct_id)
    mcs = fetch(m_id)
    return nil if !mcs || !mcs[[l_id, ct_id]]
    mcs[[l_id, ct_id]].first
  end
end
