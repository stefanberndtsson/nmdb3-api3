module Wikipedia
  class Page
    attr_reader :data
  end
end

module PersonExternal
  class Freebase
    def initialize(person)
      @person = person
    end

    def search(query)
      res = FreebaseAPI::Topic.search(query, filter: "(all type:person)")
      @query ||= res.first ? res.first.last.id : nil
    end

    def topic
      imdbid = @person.imdb.imdbid
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
      cached_page_count = Rails.rcache.get("person:#{@person.id}:external:freebase:wikipedia_page_count")
      if cached_page_count
        cached_page_count.to_i.times do |i|
          lang = Rails.rcache.get("person:#{@person.id}:external:freebase:wikipedia_page:#{i}:lang")
          title = Rails.rcache.get("person:#{@person.id}:external:freebase:wikipedia_page:#{i}:title")
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
            Rails.rcache.set("person:#{@person.id}:external:freebase:wikipedia_page:#{i}:lang", lang, 1.minute)
            Rails.rcache.set("person:#{@person.id}:external:freebase:wikipedia_page:#{i}:title", title, 1.minute)
            Rails.rcache.set("person:#{@person.id}:external:freebase:wikipedia_page_count",
                         Rails.rcache.get("person:#{@person.id}:external:freebase:wikipedia_page_count").to_i+1,
                         1.minute)
          end
        end
      end
      titles
    end
  end

  class IMDb
    def initialize(person)
      @person = person
    end

    def imdbid
      @person.bing.imdbid
    end
  end

  class Bing
    require 'open-uri'
    BASEURL="http://www.bing.com/search?go=&qs=n&form=QBLH&filt=all&sc=0-14&sp=-1&sk=&format=rss&q="

    def initialize(person)
      @person = person
    end

    def imdbid
      tmp_imdbid = Rails.rcache.get("person:#{@person.id}:externals:imdb:id")
      if !tmp_imdbid || tmp_imdbid.blank?
        results = search_rss
        found_exact = false
        find_one = results["items"].select do |item|
          tmp = item["link"][/^http:\/\/www.imdb.com\/name\/(nm\d+)\/$/]
          next false if !tmp
          tmp
        end.map {|x| x["link"]}.uniq

        if find_one.size == 1
          tmp_imdbid = find_one.first[/^http:\/\/www.imdb.com\/name\/(nm\d+)\/$/,1]
        else
          find_same = results["items"].select do |item|
            tmp = item["link"][/^http:\/\/www.imdb.com\/name\/(nm\d+)\/.*$/,1]
            next false if !tmp
            tmp
          end.uniq
          if find_same.size == 1
            tmp_imdbid = find_same.first
          else
            return nil
          end
        end

        Rails.rcache.set("person:#{@person.id}:externals:imdb:id", tmp_imdbid) if !tmp_imdbid
      end
      tmp_imdbid
    end

    def search_rss
      query = URI.encode_www_form_component("\"#{@person.imdb_search_name}\" site:www.imdb.com/name")
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
    def initialize(person)
      @person = person
    end

    def imdbid
      tmp_imdbid = Rails.rcache.get("person:#{@person.id}:externals:google:imdbid")
      if !tmp_imdbid || tmp_imdbid.blank?
        results = GoogleCustomSearchApi.search("\"#{@person.imdb_search_name}\" site:www.imdb.com/name")
        pp results
        found_exact = false
        find_one = results["items"].select do |item|
          tmp = item["link"][/^http:\/\/www.imdb.com\/name\/(nm\d+)\/$/]
          pp tmp
          next false if !tmp
          tmp
        end.map {|x| x["link"]}.uniq

        if find_one.size == 1
          tmp_imdbid = find_one.first[/^http:\/\/www.imdb.com\/name\/(nm\d+)\/$/,1]
        else
          find_same = results["items"].select do |item|
            tmp = item["link"][/^http:\/\/www.imdb.com\/name\/(nm\d+)\/.*$/,1]
            next false if !tmp
            tmp
          end.uniq
          if find_same.size == 1
            tmp_imdbid = find_same.first
          else
            return nil
          end
        end

        Rails.rcache.set("person:#{@person.id}:externals:google:imdbid", tmp_imdbid) if !tmp_imdbid
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
      box = infobox.first
      return nil if !box
      image = box["image"]
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
end
