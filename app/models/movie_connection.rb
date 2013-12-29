class MovieConnection < ActiveRecord::Base
  belongs_to :movie
  belongs_to :movie_connection_type
  belongs_to :linked_movie, :class_name => "Movie", :foreign_key => :linked_movie_id # , :include => [:movie_akas]

  def type
    movie_connection_type.connection_type
  end

  def type_sort_value
    movie_connection_type.sort_order
  end

  def text
    MovieConnectionText.find(movie_id, linked_movie_id, movie_connection_type_id)
  end

  def as_json(options = {})
    super(options)
      .merge({
               text: text ? (text.value == "[NONE]" ? nil : text.value) : nil,
               linked_movie: linked_movie
             }.compact)
  end
end
