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
      render json: @person.to_json(:methods => [:active_roles, :all_roles])
    end
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

  private
  def get_metadata(key_group)
    keys = PersonMetadatum.pages[key_group][:keys]
    @person = Person.find(params[:id])
    @metadata = @person.person_metadata.find_all_by_key(keys).group_by(&:key)
    PersonMetadatum.to_hash(@metadata)
  end
end
