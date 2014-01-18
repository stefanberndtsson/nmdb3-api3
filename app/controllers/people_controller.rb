class PeopleController < ApplicationController
  def index
  end

  def show
    if params[:full]
      @role = params[:role].blank? ? 'acting' : params[:role]
      @person = Person.find(params[:id])
      @role_data = {}
      @role_data['as_'+@role] = @person.as_hash(@person.as_role(@role))
      render json: {
        person: @person
      }.merge(@role_data)
    else
      @person = Person.find(params[:id])
      render json: @person.to_json(:methods => [:active_roles, :all_roles, :active_pages])
    end
  end

  def info
    render json: get_metadata("info", PersonMetadatum.info_keys)
  end

  def as_role
    @role = params[:role].blank? ? 'acting' : params[:role]
    @person = Person.find(params[:id])
    @role_data = @person.compress_episodes(@person.as_role(@role))
    render json: @role_data
  end

  def biography
    render json: get_metadata("biography")
  end

  def trivia
    render json: get_metadata("trivia")
  end

  def quotes
    render json: get_metadata("quotes")
  end

  def other_works
    render json: get_metadata("other_works")
  end

  def publicity
    render json: get_metadata("publicity")
  end

  def externals
    @person = Person.find(params[:id])
    @imdbid = @person.imdb.imdbid
    @wikipedia = @person.freebase.wikipedia_pages
    @freebase_topic = @person.freebase.search
    @twitter_name = @person.freebase.twitter_name
    render json: {
      imdb_id: @imdbid,
      freebase_topic: @freebase_topic,
      wikipedia: @wikipedia.compact,
      twitter: @twitter_name.blank? ? nil : @twitter_name
    }.compact
  end

  def cover
    @person = Person.find(params[:id])
    size = 640
    if params[:size]
      size = params[:size] == "full" ? nil : params[:size].to_i
    end
    image_url = @person.cover_image
    source = image_url ? "Wikipedia" : nil
    render json: {
      image: image_url,
      source: source
    }.compact
  end

  def top_movies
    @person = Person.find(params[:id])
    render json: @person.top_movies
  end

  def images
    @person = Person.find(params[:id])
    render json: {
      tmdb: @person.tmdb.images
    }.compact
  end

  def by_genre
    @person = Person.find(params[:id])
    movies = @person.as_cast.includes(movie: :genres)
    genres = []
    grouped = { }
    movies.each do |occ|
      occ.movie.genres.each do |genre|
        genres << genre
        grouped[genre.id] ||= []
        grouped[genre.id] << {
          movie: occ.movie,
          character: occ.character,
          extras: occ.extras
        }.compact
      end
    end
    genre_by_ids = genres.uniq.group_by(&:id)
    genres = []
    grouped.keys.each do |genre_id|
      genres << {
        id: genre_id,
        genre: genre_by_ids[genre_id].first.genre,
        count: grouped[genre_id].size
      }
    end
    genres = genres.sort_by { |x| -x[:count] }
    grouped_by_genre = genres.map do |genre|
      {
        id: genre[:id],
        genre: genre[:genre],
        count: genre[:count],
        movies: grouped[genre[:id]].sort_by { |x| -(x[:movie].movie_sort_value.to_i) }
      }
    end
    render json: grouped_by_genre
  end

  def by_keyword
    @person = Person.find(params[:id])
    movies = @person.as_cast.includes(movie: :keywords)
    keywords = []
    grouped = { }
    movies.each do |occ|
      occ.movie.keywords.each do |keyword|
        keywords << keyword
        grouped[keyword.id] ||= []
        grouped[keyword.id] << {
          movie: occ.movie,
          character: occ.character,
          extras: occ.extras
        }.compact
      end
    end
    keyword_by_ids = keywords.uniq.group_by(&:id)
    keywords = []
    grouped.keys.each do |keyword_id|
      keywords << {
        id: keyword_id,
        keyword: keyword_by_ids[keyword_id].first.keyword,
        display: keyword_by_ids[keyword_id].first.display,
        count: grouped[keyword_id].size
      }
    end
    keywords = keywords.sort_by { |x| -x[:count] }
    grouped_by_keyword = keywords.map do |keyword|
      {
        id: keyword[:id],
        keyword: keyword[:keyword],
        display: keyword[:display],
        count: keyword[:count],
        movies: grouped[keyword[:id]].sort_by { |x| -(x[:movie].movie_sort_value.to_i) }
      }
    end
    render json: grouped_by_keyword
  end

  private
  def get_metadata(key_group, keys = nil)
    keys = PersonMetadatum.pages[key_group][:keys] if !keys
    @person = Person.find(params[:id])
    @metadata = @person.person_metadata.find_all_by_key(keys).group_by(&:key)
    PersonMetadatum.to_hash(@metadata)
  end
end
