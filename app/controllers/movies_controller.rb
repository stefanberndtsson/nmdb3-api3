class MoviesController < ApplicationController
  def index
  end

  def show
    @movie = Movie.find(params[:id])
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
    render json: @goofs
  end

  def quotes
    @quotes = Quote.where(movie_id: params[:id]).order(:sort_order)
    render json: @quotes
  end

  def externals
    @movie = Movie.find(params[:id])
    @imdbid = @movie.google.imdbid
    @wikipedia = @movie.freebase.wikipedia_pages
    @netflixid = @movie.freebase.netflixid
    @thetvdbid = @movie.freebase.thetvdbid
    render json: {
      imdb_id: @imdbid,
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
end
