class ColorInfo < ActiveRecord::Base
  belongs_to :movie

  def as_json(options = { })
    {
      color: color,
      info: info
    }
  end
end
