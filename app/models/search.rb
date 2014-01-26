class Search < ActiveRecord::Base
  def self.query(query, max_results = 20, return_raw = false)
    query = query.norm
    movies = Sphinx.new("movies", return_raw)
    people = Sphinx.new("biography", return_raw)
    [movies.query(query, max_results), people.query(query, max_results)]
  end

  def self.query_movies(query, max_results = 20, filter = [], return_raw = false)
    query = query.norm
    movies = Sphinx.new("movies", return_raw)
    movies.query(query, max_results, filter)
  end

  def self.query_people(query, max_results = 20, return_raw = false)
    query = query.norm
    people = Sphinx.new("biography", return_raw)
    people.query(query, max_results)
  end

  def self.solr_query_movies(query, options = {})
    query = query.norm_case
    movies = Solr.new("movie")
    movies.query(query, options)
  end

  def self.solr_query_people(query, options = {})
    query = query.norm_case
    people = Solr.new("person")
    people.query(query, options)
  end

  def self.solr_suggest_movies(query, options = {})
    query = query.norm
    movies = Solr.new("movie", :suggest)
    movies.query(query, options)
  end

  def self.solr_suggest_people(query, options = {})
    query = query.norm
    people = Solr.new("person", :suggest)
    people.query(query, options)
  end
end

class Sphinx
  SOURCE_CLASSES = {
    ["movies", "movies-simple", "plots", "quotes"] => "Movie",
    ["people", "people-simple", "biography"] => "Person"
  }

  def initialize(source, return_raw = false)
    config = Rails.configuration.database_configuration[Rails.env]
    @sph = Riddle::Client.new(config["host"], 9312)
    @sph.match_mode = :extended2
    @sph.max_matches = 10000
    @sph.limit = @sph.max_matches
    @sph.field_weights = {
      :title => 120,
      :episode_title => 15,
      :name => 50,
      :cast => 4,
      :movie => 8,
      :character => 2,
      :genre => 5,
      :keyword => 5,
      :language => 3,
      :first => 10,
      :last => 10,
      :plot => 1000,
      :quote => 1000,
      :director => 1,
      :producer => 1,
      :writer => 1,
      :trivia => 1000,
      :goofs => 1000,
      :biography => 1
    }
    @source = source
    SOURCE_CLASSES.keys.each do |class_grp|
      @source_class = SOURCE_CLASSES[class_grp] if class_grp.include?(@source)
    end
    if ["movies", "plots", "quotes"].include?(@source)
      @sph.sort_mode = :expr
      @sph.sort_by = sort_expr
    end
    @return_raw = return_raw
  end

  def sort_expr
    aws = @@aws ||= Keyword.find_by_keyword("awards-show")
    aw = @@aw ||= Keyword.find_by_keyword("award")
    adult = @@adult ||= Genre.find_by_genre("Adult")

    catmult = "(3*iN(category, 2)+2*iN(category, 0)+1*iN(category, 3))"
    awsmult = "iN(keyword_ids, #{aws.id})*3*#{catmult}"
    awmult = "iN(keyword_ids, #{aw.id})*1*#{catmult}"
    adultmult = "iN(genre_ids, #{adult.id})*9"

    award_score = "5000*#{awmult}-5000*#{awsmult}"
    adult_score = "50000*#{adultmult}"

    "100000*(1-is_episode)+@weight+(1*link_score/2.0)*(occupation_score/30.0)+1*link_score+1*occupation_score-#{award_score}-#{adult_score}+votes/5.0"
  end

  # This is named as it is to not collide with the keyword 'in' and still work as a method whe
  # running eval on the sort_expr above which needs the method to be called in() since sphinx
  # has that name for it.
  def iN(expr, val1)
    if expr.class == Array
      return 1.0 if expr.include?(val1)
      return 0.0
    end
    return 1.0 if expr == val1
    return 0.0
  end

  def score(weight, from_exact, is_episode, link_score, occupation_score,
      keyword_ids, genre_ids, category, votes, rating)
    return nil if !weight || !from_exact || !is_episode || !link_score || !occupation_score
    @weight = weight
    value = eval sort_expr
    return 10000*from_exact + value
  end

  def query(query, max_results, filter = [])
    @sph.max_matches = max_results
    @sph.filters = filter
    results = @sph.query(query, @source)[:matches]
    return results if @return_raw
    doc_ids = results.map { |x| x[:doc] }
    doc_objs = doc_objects(doc_ids).group_by { |x| x.id }
    results.map do |result|
      tmp = doc_objs[result[:doc]].first
      if @source_class == "Movie"
        tmp.score = score(result[:weight],0,
                    result[:attributes]["is_episode"],
                    result[:attributes]["link_score"],
                    result[:attributes]["occupation_score"],
                    result[:attributes]["keyword_ids"],
                    result[:attributes]["genre_ids"],
                    result[:attributes]["category"],
                    result[:attributes]["votes"],
                    result[:attributes]["rating"])
      else
        tmp.score = result[:weight]
      end
      tmp
    end
  end

  def doc_objects(doc_ids)
    Kernel.const_get(@source_class).send(:find, doc_ids)
  end
end

class Solr
  SOURCE_CLASSES={
    "movie" => "Movie",
    "person" => "Person"
  }
  CORES={
    default: "core0",
    suggest: "core1"
  }
  SUGGEST_FIELDS={
    "movie" => "movie_title^10000 alternate_title^1000 episode_name^1",
    "person" => "person_name^5000 person_secondary^50"
  }

  def initialize(classname, section = :default, raw_data = false)
    @classname = classname
    @source_class = SOURCE_CLASSES[@classname]
    @raw_data = raw_data
    @section = section
  end

  def query(query, options = {})
    default_options = { limit: 20 }
    options = default_options.merge(options)
    fields = "movie_title^10000 alternate_title^1000 person_name^5000 movie_secondary^500 person_secondary^50 cast^1 character^1 movies^1 episode_name^1"
    fields = SUGGEST_FIELDS[@classname] if @section == :suggest
    res = solr.get('select',
               params: {
                     q: query,
                     fq: "class:#{@classname}",
                     qf: fields,
                     rows: options[:limit],
                     fl: 'id,nmdb_id,score,class'+(@raw_data ? ",*" : ""),
                     boost: boost,
                     defType: 'edismax'
                   })
    return res if @raw_data
    ids = res["response"]["docs"].map { |x| x["nmdb_id"] }
    objects = doc_objects(ids).group_by(&:id)
    res["response"]["docs"].map do |doc|
      tmp = objects[doc["nmdb_id"]].first
      tmp.score = doc["score"]
      tmp
    end
  end

  def boost
    @@boost ||= Infix.new(sort_expr).to_postfix.to_solr
  end

  def sort_expr
    # div(sub(add(add(product(100000,sub(1,is_episode)),add(div(product(product(3,link_score),occupation_score),30),product(3,div(link_score,add(movie_count,0.001))))),add(product(50,occupation_score),div(votes,5))),product(100000, product(product(category_award_value,1),product(20,award_keyword)))),100)
    episode = "10000*(1-is_episode)-100000*(is_episode)"
    link_occ = "(5000*link_score*occupation_score)/30"
    link = "5*(link_score/(movie_count+0.001))"
    occ = "50*occupation_score"
    scores = "(#{link_occ})+(#{link})+(#{occ})"
    votes = "votes/5"
    award = "300000*(category_award_value*20*award_keyword+reduce_genre*2000)"

    "((#{episode})+(#{scores})+(#{votes})-10*(#{award}))/100"
  end

  def solr
    config = Rails.configuration.database_configuration[Rails.env]
    @@rsolr ||= { }
    @@rsolr[@section] ||= RSolr.connect(url: "http://#{config["host"]}:8080/solr/#{CORES[@section]}/")
  end

  def doc_objects(doc_ids)
    Kernel.const_get(@source_class).send(:where, { id: doc_ids})
  end
end
