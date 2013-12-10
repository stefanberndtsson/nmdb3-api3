class String
  def norm
    decomposed = Unicode.nfkd(self).gsub(/[^\u0000-\u00ff]/, "")
    Unicode.downcase(decomposed)
  end
end

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

  # Test for Solr
  def self.test(movie_id = 61184)
    query = %Q`
SELECT id,title,episode_name,
ARRAY(SELECT genre FROM genres WHERE id IN (SELECT genre_id FROM movie_genres WHERE movie_id = #{movie_id})) AS genre,
ARRAY(SELECT keyword FROM keywords WHERE id IN (SELECT keyword_id FROM movie_keywords WHERE movie_id = #{movie_id})) AS keyword,
ARRAY(SELECT language FROM languages WHERE id IN (SELECT language_id FROM movie_languages WHERE movie_id = #{movie_id})) AS language,
ARRAY(SELECT DISTINCT(title_norm) FROM movie_akas WHERE movie_id = #{movie_id}) AS alternative_title,
1
 FROM movies WHERE id = #{movie_id}
`
    Movie.find_by_sql(query)
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

    "100000*(1-is_episode)+@weight+(3*link_score)*(occupation_score/30.0)+3*link_score+15*occupation_score-#{award_score}-#{adult_score}+votes/5.0"
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
