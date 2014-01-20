module Externals
  class IMDb
    BASEURL="http://www.imdb.com/find?exact=true&"
    require 'open-uri'

    def initialize(obj)
      @obj = obj
      @objclass = "movie_or_person"
      setup
    end

    def imdbid(cache_only = false)
      tmp_imdbid = fetch_id
      return tmp_imdbid if tmp_imdbid
      return nil if cache_only
      search
    end

    def cache_prefix
      "#{@objclass}:#{@obj.id}:externals:imdb"
    end
  end
end
