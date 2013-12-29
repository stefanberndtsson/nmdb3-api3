class MovieConnectionText < ActiveRecord::Base
  def self.store(m_id, l_id, ct_id, text)
    @@mc_store ||= { }
    @@mc_store[[m_id,l_id,ct_id]] ||= MovieConnectionText.
      find_or_create_by_movie_id_and_linked_movie_id_and_movie_connection_type_id(movie_id: m_id,
                                                                               linked_movie_id: l_id,
                                                                               movie_connection_type_id: ct_id,
                                                                               value: text)
  end

  def self.fetch(m_id)
    @@mc_text ||= { }
    @@mc_text[m_id] ||= MovieConnectionText.where(movie_id: m_id).group_by { |x| [x.linked_movie_id, x.movie_connection_type_id] }
    @@mc_text.delete(m_id) if @@mc_text[m_id].blank?
    @@mc_text[m_id]
  end

  def self.find(m_id, l_id, ct_id)
    mcs = fetch(m_id)
    return nil if !mcs || !mcs[[l_id, ct_id]]
    mcs[[l_id, ct_id]].first
  end
end
