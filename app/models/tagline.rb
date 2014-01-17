class Tagline < ActiveRecord::Base
  belongs_to :movie

  def as_json(options = { })
    {
      tagline: tagline
    }
  end
end
