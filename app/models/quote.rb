class Quote < ActiveRecord::Base
  belongs_to :movie
  has_many :quote_data

  def quote_lines
    quote_data.order(:sort_order).map(&:quote_line)
  end

  def as_json(options={})
    { quote: quote_lines }
  end
end
