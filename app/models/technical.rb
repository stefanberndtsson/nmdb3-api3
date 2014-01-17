class Technical < ActiveRecord::Base
  belongs_to :movie

  CATEGORIES = {
    "CAM" => "Camera",
    "LAB" => "Laboratory",
    "MET" => "Film length (metres)",
    "PCS" => "Cinematographic process",
    "PFM" => "Printed film format",
    "OFM" => "Film negative format (mm/video inches)",
    "RAT" => "Aspect ratio",
  }

  def self.sort_value(key)
    key_list = ["CAM", "LAB", "MET", "OFM", "PCS", "PFM", "RAT"]
    return 9999 if !key_list.include?(key)
    return key_list.index(key)
  end

  def category
    CATEGORIES[key]
  end

  def as_json(options = { })
    {
      category: category,
      key: key,
      value: value,
      info: info
    }
  end
end
