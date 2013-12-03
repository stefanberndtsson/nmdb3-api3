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
      render json: @movie
    end
  end

  def genres
    @genres = Genre.joins(:movie_genres).where(movie_genres: { movie_id: params[:id]})
    render json: @genres
  end

  def keywords
    @keywords = Keyword.joins(:movie_keyword).where(movie_keywords: { movie_id: params[:id]})
    render json: @keywords
  end

  def cast_members
    @movie = Movie.find(params[:id])
    render json: @movie.cast_members
  end
end
