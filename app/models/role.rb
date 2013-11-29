class Role < ActiveRecord::Base
  has_many :occupations

  def self.cast_roles
    @@cast_roles ||= Role.where(role: ['actor', 'actress']).map(&:id)
  end
end
