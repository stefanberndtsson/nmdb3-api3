module Wikipedia
  class Page
    attr_reader :data
  end
end

class MovieExternal
  class Freebase
    def initialize(movie)
      @movie = movie
      FreebaseAPI.session = FreebaseAPI::Session.new(key: GOOGLE_API_KEY)
    end

    def search(query)
      topic_id = Rails.rcache.get("movie:#{@movie.id}:external:freebase:topic:id")
      return topic_id if topic_id
      type = "/film/film"
      if @movie.category_code == "TVS"
        type = "/tv/tv_program"
      end
      res = FreebaseAPI::Topic.search(query, filter: "(all type:topic)")
      @query ||= res.first ? res.first.last.id : nil
      Rails.rcache.set("movie:#{@movie.id}:external:freebase:topic:id", @query, 1.week) if @query
      @query
    end

    def topic
      imdbid = @movie.is_episode ? @movie.main.imdb.imdbid : @movie.imdb.imdbid
      return nil if !imdbid
      search_result = search(imdbid)
      return nil if !search_result
      @topic ||= FreebaseAPI::Topic.get(search_result)
    end

    def decode_string(str)
      str.gsub(/\$([0-9A-F]{4})/) { [$1.hex].pack("U") }
    end

    def wikipedia_pages
      titles = {}
      cached_page_count = Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page_count")
      if cached_page_count
        cached_page_count.to_i.times do |i|
          lang = Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:lang")
          title = Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:title")
          titles[lang] = title
        end
      else
        return nil if !topic
        topic.property('/type/object/key')
          .select { |x| x.value[/^\/wikipedia\/([^\/]+)_title\//] }
          .sort_by {|x| x.value}
          .each_with_index do |obj,i|
          if obj.value[/^\/wikipedia\/([^\/]+)_title\/(.*)/]
            lang = $1
            title = decode_string($2)
            titles[lang] = title
            Rails.rcache.set("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:lang", lang, 1.week)
            Rails.rcache.set("movie:#{@movie.id}:external:freebase:wikipedia_page:#{i}:title", title, 1.week)
            Rails.rcache.set("movie:#{@movie.id}:external:freebase:wikipedia_page_count",
                         Rails.rcache.get("movie:#{@movie.id}:external:freebase:wikipedia_page_count").to_i+1,
                         1.week)
          end
        end
      end
      titles
    end

    def netflixid
      cached_id = Rails.rcache.get("movie:#{@movie.id}:external:freebase:netflix:id")
      return (cached_id == "" ? nil : cached_id) if cached_id
      return nil if !topic
      netflix = topic.property('/type/object/key').select { |x| x.value[/^\/authority\/netflix\/movie\/(.*)$/] }.first
      id = netflix ? netflix.value[/\/authority\/netflix\/movie\/(.*)/,1] : nil
      Rails.rcache.set("movie:#{@movie.id}:external:freebase:netflix:id", id, 1.week)
      id
    end

    def thetvdbid
      cached_id = Rails.rcache.get("movie:#{@movie.id}:external:freebase:thetvdb:id")
      return (cached_id == "" ? nil : cached_id) if cached_id
      return nil if !topic
      thetvdb = topic.property('/type/object/key').select { |x| x.value[/^\/authority\/thetvdb\/series\/(.*)$/] }.first
      id = thetvdb ? thetvdb.value[/\/authority\/thetvdb\/series\/(.*)/,1] : nil
      Rails.rcache.set("movie:#{@movie.id}:external:freebase:thetvdb:id", id, 1.week)
      id
    end
  end

  class IMDb
    IMDB_BASE="http://www.imdb.com/title/"
    MC_PAGE="/trivia?tab=mc"

    def initialize(movie)
      @movie = movie
    end

    def imdbid
      @movie.bing.imdbid
    end

    def movie_connection_data
      return nil if @movie.movie_connections.count == 0
      page = movie_connection_page
      doc = Nokogiri::HTML(page)
      content = doc.search("#connections_content .list")
      groups = content.search("a[@name]")
      grouped_data = {}
      groups.each do |group|
        group_name = group.attr("name").gsub(/_/," ")
        grouped_data[group_name] = []
        current_sibling = group.next_sibling
        while(!((current_sibling.node_name == "a") && current_sibling.attr("name")))
          if(current_sibling.node_name == "div" &&
              current_sibling.attr("class")[/^soda (odd|even)/])
            item_link = current_sibling.search("a[@href]")
            item_imdbid = item_link.first.attr("href").gsub(/\/title\/(.*)\//, '\1')
            item_text = ""
            if current_sibling.search("br").first
              item_text = current_sibling.search("br").first.next_sibling.text
            end
            if item_link && item_link.first && item_link.first.next_sibling
              item_title = item_link.text + " " + item_link.first.next_sibling.text.gsub(/\u00a0/,""
).trim
              grouped_data[group_name] << {
                :title => item_title.to_s,
                :imdbid => item_imdbid.to_s,
                :text => item_text.to_s.trim
              }
            end
          end
          current_sibling = current_sibling.next_sibling
          break if !current_sibling
        end
      end

      grouped_data
    end

    def movie_connection_page
      cached_page = Rails.rcache.get("movie:#{@movie.id}:externals:imdb:movie_connections:page")
      return cached_page if cached_page
      open(movie_connection_url) do |u|
        page_data = u.read
        Rails.rcache.set("movie:#{@movie.id}:externals:imdb:movie_connections:page", page_data, 1.week)
        return page_data
      end
    end

    def movie_connection_url
      IMDB_BASE+imdbid+MC_PAGE
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
        return nil if Rails.rcache.get("movie:#{@movie.id}:externals:imdb:failed_scan")
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
          find_same = results["items"].map do |item|
            tmp = item["link"][/^http:\/\/www.imdb.com\/title\/(tt\d+)\/.*$/,1]
            next false if !tmp
            tmp
          end.uniq
          if find_same.size == 1
            tmp_imdbid = find_same.first
          else
            Rails.rcache.set("movie:#{@movie.id}:externals:imdb:failed_scan", true, 1.week)
            return nil
          end
        end

        @movie.update_attribute(:imdb_id, tmp_imdbid)
      end
      tmp_imdbid
    end

    def search_rss(force_query = nil)
      query_string = force_query || @movie.imdb_search_title
      extra_query = "Full Cast & Crew"
      query = URI.encode_www_form_component("\"#{query_string}\" \"#{extra_query}\" site:www.imdb.com/title")
      open(BASEURL+query) do |u|
        rssdata = u.read
        doc = Nokogiri::XML(rssdata)
        results = {}
        results["items"] = []
        doc.search("/rss/channel/item").each do |item|
          link = item.search("link").text
          title = item.search("title").text
          results["items"] << {
            "title" => title,
            "link" => link
          } if results["items"].size < 5
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
          values = line.split(/\n*\s*\|\s*/).map do |item|
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
      box = infobox.first
      return nil if !box
      @title ||= box[type[:title]]
    end

    def image
      box = infobox.first
      return nil if !box
      image = box["image"]
      if image.match(/^(\[\[|)(File|Image):([^\|]+)(|\|.*)(\]\]|)$/)
        image = $3
        image.gsub!(/\]\]$/,'')
        image.gsub!(/^\[\[/,'')
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
      if !image_pages || image_page_ids.size == 0
        @image_url[size] ||= nil
        return nil
      end
      pgs = image_pages.data["query"]["pages"]
      pg_select = pgs.select do |pg|
        pgs[pg] && pgs[pg]["imageinfo"] &&
          (pgs[pg]["imageinfo"].first.keys.include?("thumburl") ||
          pgs[pg]["imageinfo"].first.keys.include?("url"))
      end
      if pg_select.blank?
        @image_url[size] ||= nil
        return nil
      end

      image_page_id = pg_select.keys.first
      image_page = pg_select[image_page_id]["imageinfo"].first
      image_url = image_page["thumburl"] ? image_page["thumburl"] : image_page["url"]
      @image_url[size] ||= image_url
    end
  end

  class TMDb
    TMDB_API_URL="http://api.themoviedb.org/3"
    TMDB_CFG_URL=TMDB_API_URL+"/configuration?api_key="+TMDB_API_KEY
    IMAGE_SIZES = {
      "backdrop" => {
        thumb: 0,
        medium: 1,
        large: 2
      },
      "poster" => {
        thumb: 1,
        medium: 3,
        large: 4
      }
    }

    def initialize(movie)
      @movie = movie
      @config = config
    end

    def config
      json_data = Rails.rcache.get("tmdb:config")
      return JSON.parse(json_data) if json_data
      begin
        open(TMDB_CFG_URL) do |file|
          json_data = file.read
          Rails.rcache.set("tmdb:config", json_data, 1.week)
          return JSON.parse(json_data)
        end
      rescue
      end
    end

    def find(use_parent = false)
      result = nil
      imdbid = use_parent ? @movie.main.imdb.imdbid : @movie.imdb.imdbid
      if !imdbid && !use_parent
        imdbid = @movie.main.imdb.imdbid
      end
      return nil if !imdbid
      open(TMDB_API_URL+"/find/#{imdbid}?external_source=imdb_id&api_key="+TMDB_API_KEY) do |u|
        result = JSON.parse(u.read)
      end
      if @movie.is_episode && results_blank?(result) && !use_parent
        return find(true)
      end
      if results_blank?(result)
        return nil
      end
      extract_results(result)
    end

    def info(cache_only = false)
      json_data = Rails.rcache.get("movie:#{@movie.id}:externals:tmdb:info")
      return JSON.parse(json_data) if json_data
      return nil if cache_only
      results = find
      return nil if !results
      info = get(results["id"], results["type"])
      info["type"] = results["type"]
      Rails.rcache.set("movie:#{@movie.id}:externals:tmdb:info", info.to_json, 1.week)
      info
    end

    def get(tmdb_id, type, section = nil)
      section = section ? "/#{section}" : ""
      open(TMDB_API_URL+"/#{type}/#{tmdb_id}#{section}?api_key="+TMDB_API_KEY) do |u|
        return JSON.parse(u.read)
      end
    end

    def results_blank?(results)
      results["movie_results"].blank? && results["tv_results"].blank?
    end

    def extract_results(results)
      unless results["movie_results"].blank?
        results["movie_results"].first["type"] = "movie"
        return results["movie_results"].first
      end
      unless results["tv_results"].blank?
        results["tv_results"].first["type"] = "tv"
        return results["tv_results"].first
      end
      nil
    end

    def images(cache_only = false)
      return nil if !info
      json_images = Rails.rcache.get("movie:#{@movie.id}:externals:tmdb:images")
      return JSON.parse(json_images) if json_images
      return nil if cache_only
      imgs = get(info["id"], info["type"], "images")
      imgs["backdrops"].each_with_index do |img,i|
        imgs["backdrops"][i].merge!(image_urls(img, "backdrop"))
      end
      imgs["posters"].each_with_index do |img,i|
        imgs["posters"][i].merge!(image_urls(img, "poster"))
      end
      return nil if imgs["backdrops"].blank? && imgs["posters"].blank?
      Rails.rcache.set("movie:#{@movie.id}:externals:tmdb:images", imgs.to_json, 1.week)
      imgs
    end

    def image_urls(img, type)
      base = @config["images"]["base_url"]
      thumb = @config["images"]["#{type}_sizes"][IMAGE_SIZES[type][:thumb]]
      medium = @config["images"]["#{type}_sizes"][IMAGE_SIZES[type][:medium]]
      large = @config["images"]["#{type}_sizes"][IMAGE_SIZES[type][:large]]
      {
        "image_url_thumb" => base+thumb+img["file_path"],
        "image_url_medium" => base+medium+img["file_path"],
        "image_url_large" => base+large+img["file_path"],
        "image_url" => base+"original"+img["file_path"]
      }
    end
  end
end
