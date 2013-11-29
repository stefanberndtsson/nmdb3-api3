class Keyword < ActiveRecord::Base
  has_many :movie_keyword
  has_many :movies, :through => :movie_keyword
end
