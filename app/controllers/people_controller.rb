class PeopleController < ApplicationController
  def index
  end

  def show
    @role = params[:role].blank? ? 'acting' : params[:role]
    @person = Person.find(params[:id])
    @role_data = {}
    @role_data['as_'+@role] = @person.as_hash(@person.as_role(@role))
    render json: {
      person: @person
    }.merge(@role_data)
  end
end
