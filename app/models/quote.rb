class Quote < ActiveRecord::Base
  belongs_to :movie
  has_many :quote_data

  def quote_lines(full_mode = false)
    quotes = quote_data.order(:sort_order)
    return quotes.map(&:quote_line) if full_mode
    quotes.map(&:quote_line_fast)
  end

  def as_json(options={})
    { quote: quote_lines(options[:mode] == :full) }
  end
end
