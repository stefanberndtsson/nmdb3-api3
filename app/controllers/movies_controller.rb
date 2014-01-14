class MoviesController < ApplicationController
  def index
  end

  def show
    @movie = Movie.find(params[:id])
    @movie.fetch_full = true
    if params[:full]
      render json: {
        movie: @movie,
        genres: @movie.genres,
        keywords: @movie.keywords,
        cast_members: @movie.cast_members,
      }
    else
      render json: @movie.to_json(methods: [:active_pages])
    end
  end

  def genres
    @genres = Genre.joins(:movie_genres).where(movie_genres: { movie_id: params[:id]})
    render json: @genres
  end

  def languages
    @languages = Language.joins(:movie_languages).where(movie_languages: { movie_id: params[:id]})
    render json: @languages
  end

  def keywords
    movie = Movie.find(params[:id])
    keywords = Keyword.joins(:movie_keyword).where(movie_keywords: { movie_id: params[:id]})
    strong_keywords = movie.strong_keywords
    @keywords = (strong_keywords + (keywords - strong_keywords)).sort_by { |x| x.display }
    render json: @keywords
  end

  def cast_members
    @movie = Movie.find(params[:id])
    render json: @movie.cast_members
  end

  def plots
    @plots = Plot.where(movie_id: params[:id])
    render json: @plots
  end

  def trivia
    @trivia = Trivium.where(movie_id: params[:id])
    render json: @trivia
  end

  def goofs
    @goofs = Goof.where(movie_id: params[:id])
    groups = @goofs.group_by { |x| x.category }
    categories = groups.keys.map do |category_code|
      {
        category_code: category_code,
        category_display: groups[category_code].first.category_display,
        goofs: groups[category_code]
      }
    end
    render json: categories
  end

  def quotes
    mode = params[:mode] == "full" ? :full : nil
    @quotes = Quote.where(movie_id: params[:id]).order(:sort_order)
    render json: @quotes.to_json(mode: mode)
  end

  def externals
    @movie = Movie.find(params[:id])
    @imdbid = @movie.imdb.imdbid
    @wikipedia = @movie.freebase.wikipedia_pages
    @netflixid = @movie.freebase.netflixid
    @thetvdbid = @movie.freebase.thetvdbid
    @freebase_topic = @movie.freebase.search
    render json: {
      imdb_id: @imdbid,
      freebase_topic: @freebase_topic,
      wikipedia: @wikipedia.compact,
      netflix_id: @netflixid,
      thetvdb_id: @thetvdbid
    }.compact
  end

  def cover
    @movie = Movie.find(params[:id])
    size = 640
    if params[:size]
      size = params[:size] == "full" ? nil : params[:size].to_i
    end
    image_url = @movie.cover_image
    source = image_url ? "Wikipedia" : nil
    render json: {
      image: image_url,
      source: source
    }.compact
  end

  def images
    @movie = Movie.find(params[:id])
    render json: {
      tmdb: @movie.tmdb.images
    }.compact
  end

  def episodes
    @movie = Movie.find(params[:id])
    seasons = []
    episodes = @movie.episodes.map do |episode|
      seasons << episode.episode_season || "Unknown"
      {
        episode: episode,
        episode_name: episode.episode_name.blank? ? "Unnamed" : episode.episode_name,
        plot: episode.plots.sort_by { |x| -x.plot_norm.size}.first,
        release_date: episode.first_release_date
      }.compact
    end.group_by { |x| x[:episode].episode_season }
    seasons = seasons.uniq.map do |season|
      {
        season: season,
        season_name: season.blank? ? "Unknown" : season,
        episodes: episodes[season]
      }
    end
    render json: {
      seasons: seasons
    }.compact
  end

  def local_connections
    @local = true
    common_connections
  end

  def connections
    @local = false
    common_connections
  end

  def common_connections
    @movie = Movie.find(params[:id])
    groups = MovieConnection.scan_imdb_connections(@movie, local_only: @local).group_by(&:movie_connection_type_id)
    types = groups.keys.sort_by { |x| groups[x].first.type_sort_value }.map do |group|
      {
        type: groups[group].first.type,
        type_id: group,
        connections: groups[group]
      }
    end
    render json: types
  end

  def additionals
    @movie = Movie.find(params[:id])
    render json: {
      akas: @movie.movie_akas
    }
  end

  def similar
    @movie = Movie.find(params[:id])
    render json: @movie.find_similar
  end

  def new_title
    ids = params[:id] ? [params[:id]] : params[:ids].split(",")
    @movies = Movie.find(ids)
    new_titled_movies = { }
    @movies.each do |movie|
      movie.fetch_extra = { display_title: true }
      movie.freebase.topic_name
      new_titled_movies[movie.id] = {
        display_full_title: movie.display_full_title,
        display_title: movie.display_title
      }
    end

    render json: params[:id] ? new_titled_movies.values.first : new_titled_movies
  end
end
