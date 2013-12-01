class SearchesController < ApplicationController
  def index
    query = params[:query]
    max_results = params[:limit].to_i
    max_results = 20 unless max_results > 0 && max_results <= 100
    if !query
      render json: {
        error: "No query"
      }
      return
    end
    @movies,@people = Search.query(query, max_results)
    render json: {
      movies: @movies,
      people: @people
    }
  end
end
