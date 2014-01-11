class Language < ActiveRecord::Base
  has_many :movie_languages
  has_many :movies, :through => :movie_languages
end
