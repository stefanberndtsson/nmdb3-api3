module Wikipedia
  class Page
    attr_reader :data
  end
end

class MovieExternal
  class Freebase
    def initialize(movie)
      @movie = movie
    end

    def search(query)
      type = "/film/film"
      if @movie.category_code == "TVS"
        type = "/tv/tv_program"
      end
      res = FreebaseAPI::Topic.search(query, filter: "(all type:#{type})")
      @query ||= res.first ? res.first.last.id : nil
    end

    def topic
      imdbid = @movie.imdb.imdbid
      return nil if !imdbid
      search_result = search(imdbid)
      return nil if !search_result
      @topic ||= FreebaseAPI::Topic.get(search_result)
    end

    def decode_string(str)
      str.gsub(/\$([0-9A-F]{4})/) { [$1.hex].pack("U") }
    end

    def wikipedia_pages
      return nil if !topic
      titles = {}
      cached_page_count = Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page_count")
      if cached_page_count
        cached_page_count.to_i.times do |i|
          lang = Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:lang")
          title = Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:title")
          titles[lang] = title
        end
      else
        topic.property('/type/object/key')
          .select { |x| x.value[/^\/wikipedia\/([^\/]+)_title\//] }
          .sort_by {|x| x.value}
          .each_with_index do |obj,i|
          if obj.value[/^\/wikipedia\/([^\/]+)_title\/(.*)/]
            lang = $1
            title = decode_string($2)
            titles[lang] = title
            Rails.rcache.set("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:lang", lang, 1.minute)
            Rails.rcache.set("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:title", title, 1.minute)
            Rails.rcache.set("movie:#{@movie.id}:external:freebase:wikipedia_page_count",
                         Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page_count").to_i+1,
                         1.minute)
          end
        end
      end
      titles
    end

    def netflixid
      return nil if !topic
      cached_id = Rails.rcache.get("movie:#{@movie.id}:external:freebase:netflix:id")
      return (cached_id == "" ? nil : cached_id) if cached_id
      netflix = topic.property('/type/object/key').select { |x| x.value[/^\/authority\/netflix\/movie\/(.*)$/] }.first
      id = netflix ? netflix.value[/\/authority\/netflix\/movie\/(.*)/,1] : nil
      Rails.rcache.set("movie:#{@movie.id}:external:freebase:netflix:id", id, 1.minute)
      id
    end

    def thetvdbid
      return nil if !topic
      cached_id = Rails.rcache.get("movie:#{@movie.id}:external:freebase:thetvdb:id")
      return (cached_id == "" ? nil : cached_id) if cached_id
      thetvdb = topic.property('/type/object/key').select { |x| x.value[/^\/authority\/thetvdb\/series\/(.*)$/] }.first
      id = thetvdb ? thetvdb.value[/\/authority\/thetvdb\/series\/(.*)/,1] : nil
      Rails.rcache.set("movie:#{@movie.id}:external:freebase:thetvdb:id", id, 1.minute)
      id
    end
  end

  class IMDb
    def initialize(movie)
      @movie = movie
    end

    def imdbid
      @movie.bing.imdbid
    end
  end

  class Bing
    require 'open-uri'
    BASEURL="http://www.bing.com/search?go=&qs=n&form=QBLH&filt=all&sc=0-14&sp=-1&sk=&format=rss&q="

    def initialize(movie)
      @movie = movie
    end

    def imdbid
      tmp_imdbid = @movie.imdb_id
      if !tmp_imdbid
        results = search_rss
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

    def search_rss
      query = URI.encode_www_form_component("\"#{@movie.imdb_search_title}\" site:www.imdb.com/title")
      open(BASEURL+query) do |u|
        rssdata = u.read
        doc = Nokogiri::XML(rssdata)
        results = {}
        results["items"] = []
        doc.search("/rss/channel/item").each do |item|
          link = item.search("link").text
          title = item.search("title").text
          results["items"] << {
            "link" => link,
            "title" => title
          }
        end
        return results
      end
    end
  end

  class Google
    def initialize(movie)
      @movie = movie
    end

    def imdbid
      tmp_imdbid = @movie.imdb_id
      if !tmp_imdbid
        results = GoogleCustomSearchApi.search(@movie.imdb_search_title+" site:www.imdb.com/title")
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

  class Wikipedia
    CATEGORIES={
      "TVS" => :television,
      "V" => :film,
      "TV" => :film,
      "M" => :film,
      "VG" => :videogame
    }
    TYPES={
      film: {
        type: "film",
        title: "name",
        image: "image"
      },
      television: {
        type: "television",
        title: "show_name",
        image: "image"
      }
    }
    def initialize(movie, page_title, lang = "en")
      @movie = movie
      @page_title = page_title
      @lang = lang
    end

    def client
      @client ||= ::Wikipedia::Client.new
    end

    def domain
      @domain ||= @lang+".wikipedia.org"
    end

    def page
      @page ||= client.find(@page_title, domain: domain)
    end

    def content
      page.content
    end

    def infobox
      @infobox ||= content.scan(/(?=\{\{Infobox((?:[^{}]++|\{\{\g<1>\}\})++)\}\})/).map do |box|
        box.map do |line|
          box_type = line.split(/[\n\|]+/).first.trim.downcase
          values = line.split(/\n+\s*\|\s*/).map do |item|
            item.scan(/^([^=]+?)\s*=\s*(.*)$/).first
          end
          hashed_values = nil
          if !values.blank? && !values.compact.blank?
            hashed_values = Hash[values.compact]
            hashed_values["box_type"] = box_type
          end
          hashed_values
        end.first
      end
    end

    def title
      type = TYPES[CATEGORIES[@movie.category_code]]
      box = infobox.select { |x| x["box_type"] == type[:type] }.first
      return nil if !box
      @title ||= box[type[:title]]
    end

    def image
      type = TYPES[CATEGORIES[@movie.category_code]]
      box = infobox.select { |x| x["box_type"] == type[:type] }.first
      return nil if !box
      image = box[type[:image]]
      if image.match(/^\[\[File:([^\|]+)(|\|.*)\]\]$/)
        image = $1
      end
      @image ||= image
    end

    def image_url(size = 640)
      @image_url ||= {}
      return @image_url[size] if @image_url[size]
      if !image
        @image_url[size] = nil
        return nil
      end

      options = size ? { iiurlwidth: size } : { }
      image_pages = client.find_image("File:"+image, options)
      image_page_ids = image_pages.data["query"]["pages"].keys if image_pages
      if !image_pages || image_page_ids.size == 0 || (image_page_ids.size == 1&& image_page_ids.first == "-1")
        @image_url[size] ||= nil
        return nil
      end
      image_page_id = image_pages.data["query"]["pages"].keys.first
      image_page = image_pages.data["query"]["pages"][image_page_id]["imageinfo"].first
      image_url = image_page["thumburl"] ? image_page["thumburl"] : image_page["url"]
      @image_url[size] ||= image_url
    end
  end
end
