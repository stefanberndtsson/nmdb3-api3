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

  def self.scan_imdb_connections(movie, options = { })
    options = { local_only: false }.merge(options)
    mcs = movie.movie_connections
    return mcs if mcs.blank? || options[:local_only]
    texts = MovieConnectionText.fetch(movie.id)
    return mcs if mcs.count == (texts || {}).keys.count

    imdb_data = movie.imdb.movie_connection_data
    return mcs if !imdb_data
    skip_ids = []
    mcs.each do |mc|
      next if mc.text
      imdb_linked_movie = imdb_data[mc.type].select do |x|
        next if skip_ids.include?(mc.linked_movie_id)
        linked_imdbid = mc.linked_movie.imdb.imdbid
        skip_ids << mc.linked_movie_id if !mc.linked_movie.imdb_id
        x[:imdbid] == linked_imdbid
      end.first
      next if !imdb_linked_movie
      MovieConnectionText.store(mc.movie_id, mc.linked_movie_id, mc.movie_connection_type_id, imdb_linked_movie[:text])
    end
    movie.movie_connections
  end
end
