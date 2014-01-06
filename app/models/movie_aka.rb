class MovieAka < ActiveRecord::Base
  belongs_to :movie

  def as_json(options = { })
    {
      title: title,
      info: info
    }
  end
end
