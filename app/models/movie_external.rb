class MovieExternal
  class Freebase
    def initialize(movie)
      @movie = movie
      @topic = topic
    end

    def search(query)
      type = "/film/film"
      if @movie.category_code == "TVS"
        type = "/tv/tv_program"
      end
      res = FreebaseAPI::Topic.search(query, filter: "(all type:#{type})")
      res.first ? res.first.last.id : nil
    end

    def topic
      imdbid = @movie.google.imdbid
      return nil if !imdbid
      search_result = search(imdbid)
      return nil if !search_result
      @topic = FreebaseAPI::Topic.get(search_result)
    end

    def decode_string(str)
      str.gsub(/\$([0-9A-F]{4})/) { [$1.hex].pack("U") }
    end

    def wikipedia_pages
      return nil if !@topic
      titles = {}
      @topic.property('/type/object/key').select { |x| x.value[/^\/wikipedia\/([^\/]+)_title\//] }.sort_by {|x| x.value}.each do |obj|
        if obj.value[/^\/wikipedia\/([^\/]+)_title\/(.*)/]
          titles[$1] = decode_string($2)
        end
      end
      titles
    end

    def netflixid
      return nil if !@topic
      netflix = @topic.property('/type/object/key').select { |x| x.value[/^\/authority\/netflix\/movie\/(.*)$/] }.first
      netflix ? netflix.value[/\/authority\/netflix\/movie\/(.*)/,1] : nil
    end

    def thetvdbid
      return nil if !@topic
      thetvdb = @topic.property('/type/object/key').select { |x| x.value[/^\/authority\/thetvdb\/series\/(.*)$/] }.first
      thetvdb ? thetvdb.value[/\/authority\/thetvdb\/series\/(.*)/,1] : nil
    end
  end

  class Google
    def initialize(movie)
      @movie = movie
    end

    def imdbid
      tmp_imdbid = @movie.imdb_id
      if !tmp_imdbid
        results = GoogleCustomSearchApi.search(@movie.imdb_search_title)
        found_exact = false
        find_one = results["items"].select do |item|
          tmp = item["link"][/^http:\/\/www.imdb.com\/title\/(tt\d+)\/$/]
          next false if !tmp
          if item["title"] == "#{@movie.imdb_search_title} - IMDb"
            found_exact = true
            next true
          end
          found_exact ? nil: tmp
        end.map {|x| x["link"]}.uniq

        if find_one.size == 1
          tmp_imdbid = find_one.first[/^http:\/\/www.imdb.com\/title\/(tt\d+)\/$/,1]
        else
          return nil
        end

        @movie.update_attribute(:imdb_id, tmp_imdbid)
      end
      tmp_imdbid
    end
  end
end
