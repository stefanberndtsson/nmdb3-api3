class Certificate < ActiveRecord::Base
  belongs_to :movie

  def as_json(options = { })
    {
      certificate: certificate,
      country: country,
      info: info
    }.compact
  end
end
