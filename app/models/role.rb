class Role < ActiveRecord::Base
  GROUP_SORT_ORDER={ 1 => 1, 2 => 3, 3 => 2, 4 => 4 }
  has_many :occupations

  def self.cast_roles
    @@cast_roles ||= Role.where(role: ['actor', 'actress']).map(&:id)
  end

  def self.all_noncast_role_names
    @@all_noncast_role_names ||= Role.order(:group, :id)
      .where("\"group\" >= 2")
      .sort_by { |x| GROUP_SORT_ORDER[x.group] }
      .map(&:role)
  end
end
