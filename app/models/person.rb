class Person < ActiveRecord::Base
  has_many :occupations
  has_many :movies, :through => :occupations

  def display
    [first_name, last_name].join(" ")
  end

  def as_cast
    occupations.where(role_id: Role.cast_roles).includes(:movie)
  end

  def as_self
    as_cast.where("character_norm ~ E'(himself|herself|themselves)'")
  end

  def as_archive
    as_cast.where("extras ~ E'\(archive'")
  end

  def as_acting
  end
end
