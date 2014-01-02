module Externals
  class IMDb
    def initialize(obj)
      @obj = obj
      @objclass = "movie_or_person"
      setup
    end

    def imdbid
      @obj.bing.imdbid
    end

    def cache_prefix
      "#{@objclass}:#{@obj.id}:externals:imdb"
    end
  end
end
