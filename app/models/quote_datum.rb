class QuoteDatum < ActiveRecord::Base
  belongs_to :quote

  def links
    pids = content.get_links("PID")
    mids = content.get_links("MID")
    people = Person.where(id: pids).group_by(&:id)
    movies = Movie.where(id: mids).group_by(&:id)
    link_list = {}
    link_list[:people] = people if !people.blank?
    link_list[:movies] = movies if !movies.blank?
    link_list.blank? ? nil : link_list
  end

  def quote_line
    {
      content: content,
      quoter: quoter.blank? ? nil : {
        character: quoter,
        person: quoter_person,
      }.compact,
      links: links
    }.compact
  end

  def quote_line_fast
    {
      content: content,
      quoter: quoter.blank? ? nil : {
        character: quoter
      }.compact
    }.compact
  end

  def content
    @content ||= quoter.blank? ? value : value[quoter.size+1..-1].gsub(/^\s+/,'')
  end

  def quoter
    return nil if value[/^\[/]
    @quoter ||= value.index(':') ? value.gsub(/^([^:]+):.*$/,'\1') : nil
  end

  def quoter_person
    @@quoter_person_cache ||= { }
    return @@quoter_person_cache[[quote.movie_id, quoter]] if @@quoter_person_cache[[quote.movie_id, quoter]]
    movie = quote.movie
    return nil if quoter.blank?
    qnorm = quoter.norm.split(" ").reject { |x| x == "the" }.join(" ")
    return nil if qnorm.blank?

    character_list = movie.cast.map do |member|
      next if member.character.blank? || member.character_norm.blank? || qnorm.blank?
      [Levenshtein.distance(member.character_norm, qnorm), member]
    end.compact.sort_by do |member|
      member[0]
    end

    return nil if character_list.blank?

    best_match = find_best_match(character_list)
    @@quoter_person_cache[[movie.id, quoter]] = best_match if best_match
    best_match
  end

  def find_best_match(character_list)
    # Get best scored
    tmp = character_list.first
    tmp[0] = tmp[0].to_f/[quoter.size, tmp[1].character.size].max.to_f

    # If best score isn't good enough, look for exact match within name
    return tmp[1].person if tmp[0] <= 0.25

    new_tmp = character_list.select do |member|
      member[1].character.index(quoter)
    end

    # If we got multiple exact matches, see if a single one matches the end part.
    if !new_tmp.blank? && new_tmp.size != 1
      new_tmp = new_tmp.select do |member|
        member[1].character[/#{quoter}( |$)/]
      end
    end

    # Still multiple hits or no hits at all...
    # Now look for matching name parts (split on space) where all parts exists within name
    if new_tmp.blank? || new_tmp.size != 1
      quoter_parts = quoter.split(" ").reject { |x| x.downcase == "the" }
      new_tmp = character_list.select do |member|
        quoter_parts_count = 0
        quoter_parts.each do |qpart|
          quoter_parts_count += 1 if member[1].character.index(qpart)
        end
        quoter_parts_count == quoter_parts.size
      end
    end
    # Skip if we got multiple or none...
    return nil if new_tmp.blank? || new_tmp.size != 1
    new_tmp.first[1].person
  end
end
