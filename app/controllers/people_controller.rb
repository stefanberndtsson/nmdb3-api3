class PeopleController < ApplicationController
  def index
  end

  def show
    @person = Person.find(params[:id])
    render json: @person
  end
end
