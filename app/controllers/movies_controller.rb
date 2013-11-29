class MoviesController < ApplicationController
  def index
  end

  def show
    @movie = Movie.find(params[:id])
    render json: @movie
  end
end
