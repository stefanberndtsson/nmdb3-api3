class PersonMetadatum < ActiveRecord::Base
  belongs_to :person
  MDTYPE={
    "AG" => "Age",
    "DB" => "Date of Birth",
    "DD" => "Date of Death",
    "RN" => "Birth Name",
    "NK" => "Nickname",
    "HT" => "Height",
    "BG" => "Mini Biography",
    "SP" => "Spouse",
    "TM" => "Trade Mark",
    "WN" => "Where are they now",
    "SA" => "Salary",
    "TR" => "Trivia",
    "QU" => "Personal quotes",
    "OW" => "Other works",
    "BT" => "Biographical movies",
    "PI" => "Portrayed in",
    "BO" => "Biography (print)",
    "IT" => "Interview",
    "AT" => "Article",
    "PT" => "Pictorial",
    "CV" => "Magazine cover photo",
  }

  MDSINGLE=["DB", "DD", "RN", "HT", "AG"]

  def self.pages
    {
      "biography" => {
        :keys => ["DB", "DD", "RN", "NK", "HT", "BG", "SP", "TM", "WN", "SA"],
        :display => "Biography"
      },
      "trivia" => {
        :keys => ["TR"],
        :display => "Trivia"
      },
      "quotes" => {
        :keys => ["QU"],
        :display => "Quotes"
      },
      "other_works" => {
        :keys => ["OW"],
        :display => "Other works"
      },
      "publicity" => {
        :keys => ["BT", "PI", "BO", "IT", "AT", "PT", "CV"],
        :display => "Publicity"
      }
    }
  end

  def self.info_keys
    ["DB", "DD", "HT", "RN"]
  end

  def self.age(page_data)
    age_data = nil
    if page_data.keys.include?("DB")
      db_stamp = page_data["DB"].first.value.get_timestamp
      dd_stamp = Time.now
      if db_stamp && page_data.keys.include?("DD")
        dd_stamp = page_data["DD"].first.value.get_timestamp
      end
      age = dd_stamp - db_stamp
      age_display = ApplicationController.helpers.distance_of_time_in_words(age)
      age_data = OpenStruct.new({ value: age_display, timestamp: age.to_i })
    end
    age_data
  end

  def self.page_from_key(key)
    pages.keys.each do |page|
      return page if pages[page][:keys].include?(key)
    end
  end

  def self.to_hash(page_data)
    pids = []
    mids = []
    page_data.values.flatten(1).each do |entry|
      pids += entry.value.get_links("PID")
      mids += entry.value.get_links("MID")
    end
    people = Person.where(id: pids).group_by(&:id)
    movies = Movie.where(id: mids).group_by(&:id)
    age_data = age(page_data)
    page_data["AG"] = [age_data] if age_data
    page_data.keys.sort_by { |x| MDTYPE.keys.index(x) }.map do |key|
      values = page_data[key].map do |entry|
        tmp = {}
        tmp[:value] = entry.value
        pids = entry.value.get_links("PID")
        mids = entry.value.get_links("MID")
        if !pids.blank? || !mids.blank?
          tmp[:links] = { }
          if !pids.blank?
            tmp[:links][:people] = pids.map { |pid| people[pid].first }.group_by { |x| x.id }
          end
          if !mids.blank?
            tmp[:links][:movies] = mids.map { |mid| movies[mid].first }.group_by { |x| x.id }
          end
        end
        tmp
      end
      value = nil
      timestamp = page_data[key].first[:timestamp]
      date = nil
      if MDSINGLE.include?(key)
        value = values.first[:value]
        values = nil
        if ["DB", "DD"].include?(key)
          timestamp = value.get_timestamp
          date = timestamp.strftime("%Y-%m-%d") if timestamp
        end
      end
      {
        code: key,
        display: MDTYPE[key],
        value: value,
        date: date,
        timestamp: timestamp,
        values: values
      }.compact
    end
  end
end
