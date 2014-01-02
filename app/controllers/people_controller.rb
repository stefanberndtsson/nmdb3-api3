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
    render json: {
      imdb_id: @imdbid,
      freebase_topic: @freebase_topic,
      wikipedia: @wikipedia.compact,
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

  private
  def get_metadata(key_group, keys = nil)
    keys = PersonMetadatum.pages[key_group][:keys] if !keys
    @person = Person.find(params[:id])
    @metadata = @person.person_metadata.find_all_by_key(keys).group_by(&:key)
    PersonMetadatum.to_hash(@metadata)
  end
end
