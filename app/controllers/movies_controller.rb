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
end
