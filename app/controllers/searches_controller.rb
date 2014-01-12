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

  def movies
    query = params[:query]
    max_results = params[:limit].to_i
    from_year = params[:from_year]
    to_year = params[:to_year]
    has_filter = false
    if from_year || to_year
      from_year = 0 if !from_year && to_year
      to_year = 9999 if from_year && !to_year
      has_filter = true
    end
    filter_range = Range.new(from_year.to_i, to_year.to_i)
    filter = has_filter ? [Riddle::Client::Filter.new("year_attr", filter_range, false)] : []

    max_results = 20 unless max_results > 0 && max_results <= 100
    if !query
      render json: {
        error: "No query"
      }
      return
    end
    @movies = Search.query_movies(query, max_results, filter)
    render json: @movies
  end

  def people
    query = params[:query]
    max_results = params[:limit].to_i
    max_results = 20 unless max_results > 0 && max_results <= 100
    if !query
      render json: {
        error: "No query"
      }
      return
    end
    @people = Search.query_people(query, max_results)
    render json: @people
  end

  def solr_movies
    query = params[:query]
    if !query
      render json: {
        error: "No query"
      }
      return
    end

    options = {}
    options[:limit] = params[:limit] if params[:limit]
    @movies = Search.solr_query_movies(query, options)
    render json: @movies
  end

  def solr_people
    query = params[:query]
    if !query
      render json: {
        error: "No query"
      }
      return
    end

    options = {}
    options[:limit] = params[:limit] if params[:limit]
    @people = Search.solr_query_people(query, options)
    render json: @people
  end

  def solr_suggest_movies
    query = params[:query]
    if !query
      render json: {
        error: "No query"
      }
      return
    end

    options = {}
    options[:limit] = params[:limit] if params[:limit]
    wildcard_query = query.split(/ +/).map { |x| x+'*' }.join(" ")
    @movies = Search.solr_suggest_movies(wildcard_query, options)
    render json: @movies
  end

  def solr_suggest_people
    query = params[:query]
    if !query
      render json: {
        error: "No query"
      }
      return
    end

    options = {}
    options[:limit] = params[:limit] if params[:limit]
    wildcard_query = query.split(/ +/).map { |x| x+'*' }.join(" ")
    @people = Search.solr_suggest_people(wildcard_query, options)
    render json: @people
  end
end
