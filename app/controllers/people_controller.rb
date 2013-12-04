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
    @role_data = @person.as_hash(@person.as_role(@role))
    render json: @role_data
  end
end
