class MoviesController < ApplicationController
  def index
  end

  def show
    @movie = Movie.find(params[:id])
    render json: {
      movie: @movie,
      genres: @movie.genres,
      keywords: @movie.keywords,
      cast_members: @movie.cast_members,
    }
  end
end
